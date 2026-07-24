/* test_app_ota.c — F14.1–F14.4 on the host.
 *
 * The whole OTA path runs here: the image inspector against the first 288
 * bytes of REAL builds (protocol/fixtures/ota/), the admission rules, the
 * phase machine and its throttled progress, the injected flash seam with
 * every failure mode a board would take a reflash to produce, and design
 * 03 §3.7's health gate as a table.
 *
 * Nothing in F14 touches the board before F14.9, and this file is why.
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "app_ota_core.h"
#include "app_ota_gate.h"
#include "test_util.h"

/* ── fixtures ──────────────────────────────────────────────────────── */

static size_t load_fixture(const char *name, uint8_t *buf, size_t cap) {
    char path[512];
    snprintf(path, sizeof path, "%s/%s", FIXTURES_OTA_DIR, name);
    FILE *f = fopen(path, "rb");
    if (!f) {
        fprintf(stderr, "FAIL: cannot open %s\n", path);
        return 0;
    }
    const size_t n = fread(buf, 1, cap, f);
    fclose(f);
    return n;
}

static void test_image_inspect(void) {
    uint8_t app[APP_OTA_HEADER_MIN];
    uint8_t boot[APP_OTA_HEADER_MIN];
    uint8_t ptab[APP_OTA_HEADER_MIN];
    CHECK_EQ_INT(load_fixture("app-heltec-v3-header.bin", app, sizeof app),
                 APP_OTA_HEADER_MIN);
    CHECK_EQ_INT(load_fixture("bootloader-header.bin", boot, sizeof boot),
                 APP_OTA_HEADER_MIN);
    CHECK_EQ_INT(
        load_fixture("partition-table-header.bin", ptab, sizeof ptab),
        APP_OTA_HEADER_MIN);

    /* The real thing. */
    app_ota_image_info_t info;
    CHECK_EQ_INT(app_ota_image_inspect(app, sizeof app, &info),
                 APP_OTA_IMG_OK);
    CHECK_EQ_INT(info.chip_id, APP_OTA_CHIP_ID_ESP32S3);
    CHECK(strcmp(info.project, "smoke_bridge") == 0);
    /* F14.7 — the descriptor now carries the release version rather than
     * a git-describe abbreviation. This assertion is what keeps the two
     * from drifting apart again. */
    CHECK(strcmp(info.version, "1.0.0") == 0);
    CHECK(info.idf_ver[0] == 'v');

    /* THE mistake this exists to catch: the merged image, which starts
     * with the bootloader — right magic, right chip, no app descriptor. */
    CHECK_EQ_INT(app_ota_image_inspect(boot, sizeof boot, &info),
                 APP_OTA_IMG_NO_APP_DESC);
    CHECK_EQ_INT(info.chip_id, APP_OTA_CHIP_ID_ESP32S3);

    /* partition-table.bin starts 0xAA 0x50. */
    CHECK_EQ_INT(app_ota_image_inspect(ptab, sizeof ptab, &info),
                 APP_OTA_IMG_BAD_MAGIC);

    /* Every reason must be distinct — "invalid image" with no detail is
     * what makes a support conversation take an hour. */
    CHECK(strcmp(app_ota_image_verdict_str(APP_OTA_IMG_BAD_MAGIC),
                 app_ota_image_verdict_str(APP_OTA_IMG_NO_APP_DESC)) != 0);
    CHECK(strcmp(app_ota_image_verdict_str(APP_OTA_IMG_WRONG_CHIP),
                 app_ota_image_verdict_str(APP_OTA_IMG_NO_APP_DESC)) != 0);
    CHECK(strcmp(app_ota_image_verdict_str(APP_OTA_IMG_UNDECIDED),
                 app_ota_image_verdict_str(APP_OTA_IMG_OK)) != 0);

    /* Undecided is a boundary, not an approximation. */
    CHECK_EQ_INT(app_ota_image_inspect(app, APP_OTA_HEADER_MIN - 1, &info),
                 APP_OTA_IMG_UNDECIDED);
    CHECK_EQ_INT(app_ota_image_inspect(app, APP_OTA_HEADER_MIN, &info),
                 APP_OTA_IMG_OK);
    CHECK_EQ_INT(app_ota_image_inspect(NULL, 4096, &info),
                 APP_OTA_IMG_UNDECIDED);

    /* Degenerate buffers are rejected without reading past the end. */
    uint8_t zeros[APP_OTA_HEADER_MIN];
    memset(zeros, 0, sizeof zeros);
    CHECK_EQ_INT(app_ota_image_inspect(zeros, sizeof zeros, &info),
                 APP_OTA_IMG_BAD_MAGIC);
    uint8_t ones[APP_OTA_HEADER_MIN];
    memset(ones, 0xFF, sizeof ones);
    CHECK_EQ_INT(app_ota_image_inspect(ones, sizeof ones, &info),
                 APP_OTA_IMG_BAD_MAGIC);

    /* A right-shaped header for a different part. */
    uint8_t other[APP_OTA_HEADER_MIN];
    memcpy(other, app, sizeof other);
    other[12] = 0x00; /* ESP32 (chip id 0x0000) */
    other[13] = 0x00;
    CHECK_EQ_INT(app_ota_image_inspect(other, sizeof other, &info),
                 APP_OTA_IMG_WRONG_CHIP);
    CHECK_EQ_INT(info.chip_id, 0);

    /* Unterminated char[32] fields must still come out NUL-terminated. */
    uint8_t unterm[APP_OTA_HEADER_MIN];
    memcpy(unterm, app, sizeof unterm);
    memset(unterm + 48, 'A', 32);  /* version */
    memset(unterm + 80, 'B', 32);  /* project */
    memset(unterm + 144, 'C', 32); /* idf_ver */
    CHECK_EQ_INT(app_ota_image_inspect(unterm, sizeof unterm, &info),
                 APP_OTA_IMG_OK);
    CHECK_EQ_INT(strlen(info.version), 32);
    CHECK_EQ_INT(strlen(info.project), 32);
    CHECK_EQ_INT(strlen(info.idf_ver), 32);
    CHECK_EQ_INT(info.version[32], '\0');
}

/* ── the injected flash seam ───────────────────────────────────────── */

typedef struct {
    int begins;
    int writes;
    int ends;
    int set_boots;
    int reboots;
    size_t written;
    uint8_t first[APP_OTA_HEADER_MIN];
    size_t first_len;
    /* Failure injection. */
    bool fail_begin;
    bool fail_write_after;  /* fail once `written` exceeds this */
    size_t fail_write_at;
    bool fail_end;
    bool fail_set_boot;
} fake_flash_t;

static int fake_begin(void *ctx, size_t total_hint) {
    fake_flash_t *f = ctx;
    (void)total_hint;
    f->begins++;
    return f->fail_begin ? -1 : 0;
}

static int fake_write(void *ctx, const void *data, size_t n) {
    fake_flash_t *f = ctx;
    f->writes++;
    if (f->first_len < sizeof f->first) {
        const size_t take = (n < sizeof f->first - f->first_len)
                                ? n
                                : sizeof f->first - f->first_len;
        memcpy(f->first + f->first_len, data, take);
        f->first_len += take;
    }
    f->written += n;
    if (f->fail_write_after && f->written > f->fail_write_at) {
        return -1;
    }
    return 0;
}

static int fake_end(void *ctx) {
    fake_flash_t *f = ctx;
    f->ends++;
    return f->fail_end ? -1 : 0;
}

static int fake_set_boot(void *ctx) {
    fake_flash_t *f = ctx;
    f->set_boots++;
    return f->fail_set_boot ? -1 : 0;
}

static void fake_reboot(void *ctx, uint32_t delay_ms) {
    fake_flash_t *f = ctx;
    (void)delay_ms;
    f->reboots++;
}

static const char *fake_slot(void *ctx) {
    (void)ctx;
    return "ota_1";
}

static void fake_ops_init(app_ota_ops_t *ops, fake_flash_t *f) {
    memset(f, 0, sizeof *f);
    ops->begin = fake_begin;
    ops->write = fake_write;
    ops->end = fake_end;
    ops->set_boot = fake_set_boot;
    ops->reboot_later = fake_reboot;
    ops->slot_name = fake_slot;
    ops->ctx = f;
}

/* ── admission ─────────────────────────────────────────────────────── */

static void test_admission(void) {
    app_ota_session_t s;
    app_ota_session_reset(&s);

    CHECK_EQ_INT(app_ota_session_admit(&s, false, false, 1024),
                 APP_OTA_ADMIT_OK);
    /* 06 §6.2: refused while a cook is running, unless forced. Nobody
     * discovers a bad flash 14 hours into a brisket. */
    CHECK_EQ_INT(app_ota_session_admit(&s, true, false, 1024),
                 APP_OTA_ADMIT_SESSION_ACTIVE);
    CHECK_EQ_INT(app_ota_session_admit(&s, true, true, 1024),
                 APP_OTA_ADMIT_OK);
    CHECK_EQ_INT(app_ota_session_admit(&s, false, false, 0),
                 APP_OTA_ADMIT_EMPTY);

    /* A live upload outranks everything, force or not. */
    app_ota_ops_t ops;
    fake_flash_t flash;
    fake_ops_init(&ops, &flash);
    app_ota_session_begin(&s, &ops, 4096);
    CHECK_EQ_INT(app_ota_session_admit(&s, false, false, 1024),
                 APP_OTA_ADMIT_IN_PROGRESS);
    CHECK_EQ_INT(app_ota_session_admit(&s, false, true, 1024),
                 APP_OTA_ADMIT_IN_PROGRESS);

    /* A failed upload must NOT wedge the endpoint at 503 forever. */
    app_ota_session_fail(&s, "test");
    CHECK_EQ_INT(app_ota_session_admit(&s, false, false, 1024),
                 APP_OTA_ADMIT_OK);
    app_ota_session_reset(&s);
    CHECK_EQ_INT(app_ota_session_admit(&s, false, false, 1024),
                 APP_OTA_ADMIT_OK);

    /* Distinct codes, because they map to distinct HTTP statuses. */
    CHECK(strcmp(app_ota_admit_str(APP_OTA_ADMIT_SESSION_ACTIVE),
                 "session_active") == 0);
    CHECK(strcmp(app_ota_admit_str(APP_OTA_ADMIT_IN_PROGRESS),
                 "ota_in_progress") == 0);
    CHECK(strcmp(app_ota_admit_str(APP_OTA_ADMIT_EMPTY), "invalid_body") ==
          0);
}

/* ── the upload, chunk by chunk ────────────────────────────────────── */

/* Builds a plausible image: the real header fixture followed by filler. */
static uint8_t *make_image(size_t total, const uint8_t *header) {
    uint8_t *img = malloc(total);
    if (!img) {
        return NULL;
    }
    memcpy(img, header, APP_OTA_HEADER_MIN);
    for (size_t i = APP_OTA_HEADER_MIN; i < total; i++) {
        img[i] = (uint8_t)(i & 0xFF);
    }
    return img;
}

static void test_upload_happy_path(const uint8_t *header) {
    app_ota_session_t s;
    app_ota_ops_t ops;
    fake_flash_t flash;
    fake_ops_init(&ops, &flash);

    const size_t total = 1304736u; /* the real image size, near enough */
    uint8_t *img = make_image(total, header);
    CHECK(img != NULL);
    if (!img) {
        return;
    }

    app_ota_session_begin(&s, &ops, total);

    int writing_events = 0, verifying_events = 0, rebooting_events = 0;
    int first_pct = -1, last_pct = -1;
    app_ota_phase_t phase;
    int pct;

    for (size_t off = 0; off < total; off += 4096) {
        const size_t n = (total - off) < 4096 ? (total - off) : 4096;
        CHECK_EQ_INT(app_ota_session_feed(&s, img + off, n), 0);
        while (app_ota_session_take_progress(&s, &phase, &pct)) {
            CHECK_EQ_INT(phase, APP_OTA_PHASE_WRITING);
            if (first_pct < 0) {
                first_pct = pct;
            }
            last_pct = pct;
            writing_events++;
        }
    }
    CHECK_EQ_INT(app_ota_session_finish(&s), 0);
    while (app_ota_session_take_progress(&s, &phase, &pct)) {
        if (phase == APP_OTA_PHASE_VERIFYING) {
            verifying_events++;
        } else if (phase == APP_OTA_PHASE_REBOOTING) {
            rebooting_events++;
        }
        CHECK_EQ_INT(pct, 100);
    }

    /* Every whole 5 % from 0 to 100, and NOT one per chunk: 1.3 MB in
     * 4 KB reads is 319 chunks and the WebSocket cap is two clients. */
    CHECK_EQ_INT(writing_events, 21);
    CHECK_EQ_INT(first_pct, 0);
    CHECK_EQ_INT(last_pct, 100);
    CHECK_EQ_INT(verifying_events, 1);
    CHECK_EQ_INT(rebooting_events, 1);

    /* The bytes on flash are the bytes uploaded, exactly — an off-by-one
     * here is an image that fails SHA-256 after four minutes. */
    CHECK_EQ_INT(flash.written, total);
    CHECK_EQ_INT(s.received, total);
    CHECK_EQ_INT(flash.begins, 1);
    CHECK_EQ_INT(flash.ends, 1);
    CHECK_EQ_INT(flash.set_boots, 1);
    CHECK_EQ_INT(flash.reboots, 1);
    /* The held-back header is flushed, in order, before anything else. */
    CHECK_EQ_INT(flash.first_len, APP_OTA_HEADER_MIN);
    CHECK_EQ_INT(memcmp(flash.first, header, APP_OTA_HEADER_MIN), 0);
    CHECK_EQ_INT(s.phase, APP_OTA_PHASE_REBOOTING);
    CHECK(strcmp(s.info.project, "smoke_bridge") == 0);

    free(img);
}

static void test_upload_failures(const uint8_t *header,
                                 const uint8_t *bootloader) {
    app_ota_session_t s;
    app_ota_ops_t ops;
    fake_flash_t flash;
    const size_t total = 64u * 1024u;
    uint8_t *img = make_image(total, header);
    CHECK(img != NULL);
    if (!img) {
        return;
    }

    /* A bad image never opens a slot: begin() must not be called, so a
     * refused upload cannot leave a half-erased partition behind. */
    {
        fake_ops_init(&ops, &flash);
        uint8_t *bad = make_image(total, bootloader);
        CHECK(bad != NULL);
        app_ota_session_begin(&s, &ops, total);
        CHECK_EQ_INT(app_ota_session_feed(&s, bad, 4096), -1);
        CHECK_EQ_INT(s.phase, APP_OTA_PHASE_FAILED);
        CHECK(strcmp(s.fail_reason,
                     app_ota_image_verdict_str(APP_OTA_IMG_NO_APP_DESC)) ==
              0);
        CHECK_EQ_INT(flash.begins, 0);
        CHECK_EQ_INT(flash.writes, 0);
        /* A chunk arriving after failure is dropped, not accounted. */
        const size_t was = s.received;
        CHECK_EQ_INT(app_ota_session_feed(&s, bad + 4096, 4096), -1);
        CHECK_EQ_INT(s.received, was);
        free(bad);
    }

    /* begin() fails (no free slot). */
    {
        fake_ops_init(&ops, &flash);
        flash.fail_begin = true;
        app_ota_session_begin(&s, &ops, total);
        CHECK_EQ_INT(app_ota_session_feed(&s, img, 4096), -1);
        CHECK_EQ_INT(s.phase, APP_OTA_PHASE_FAILED);
        CHECK(strcmp(s.fail_reason, "ota_begin_failed") == 0);
        CHECK_EQ_INT(flash.writes, 0);
    }

    /* write() fails mid-image. */
    {
        fake_ops_init(&ops, &flash);
        flash.fail_write_after = true;
        flash.fail_write_at = 16384;
        app_ota_session_begin(&s, &ops, total);
        int rc = 0;
        for (size_t off = 0; off < total && rc == 0; off += 4096) {
            rc = app_ota_session_feed(&s, img + off, 4096);
        }
        CHECK_EQ_INT(rc, -1);
        CHECK_EQ_INT(s.phase, APP_OTA_PHASE_FAILED);
        CHECK(strcmp(s.fail_reason, "ota_write_failed") == 0);
        CHECK_EQ_INT(flash.ends, 0);
        CHECK_EQ_INT(flash.set_boots, 0);
    }

    /* end() fails validation — the corrupt-image case. The boot
     * partition MUST be left alone; that is what keeps a corrupt image
     * from ever being booted. */
    {
        fake_ops_init(&ops, &flash);
        flash.fail_end = true;
        app_ota_session_begin(&s, &ops, total);
        for (size_t off = 0; off < total; off += 4096) {
            CHECK_EQ_INT(app_ota_session_feed(&s, img + off, 4096), 0);
        }
        CHECK_EQ_INT(app_ota_session_finish(&s), -1);
        CHECK_EQ_INT(s.phase, APP_OTA_PHASE_FAILED);
        CHECK(strcmp(s.fail_reason, "image_validation_failed") == 0);
        CHECK_EQ_INT(flash.set_boots, 0);
        CHECK_EQ_INT(flash.reboots, 0);
    }

    /* set_boot() fails: still no reboot. */
    {
        fake_ops_init(&ops, &flash);
        flash.fail_set_boot = true;
        app_ota_session_begin(&s, &ops, total);
        for (size_t off = 0; off < total; off += 4096) {
            CHECK_EQ_INT(app_ota_session_feed(&s, img + off, 4096), 0);
        }
        CHECK_EQ_INT(app_ota_session_finish(&s), -1);
        CHECK(strcmp(s.fail_reason, "set_boot_failed") == 0);
        CHECK_EQ_INT(flash.reboots, 0);
    }

    /* A body that ends before a whole header arrived. */
    {
        fake_ops_init(&ops, &flash);
        app_ota_session_begin(&s, &ops, 100);
        CHECK_EQ_INT(app_ota_session_feed(&s, img, 100), 0);
        CHECK_EQ_INT(app_ota_session_finish(&s), -1);
        CHECK_EQ_INT(s.phase, APP_OTA_PHASE_FAILED);
        CHECK_EQ_INT(flash.begins, 0);
    }

    /* A body shorter than Content-Length. */
    {
        fake_ops_init(&ops, &flash);
        app_ota_session_begin(&s, &ops, total);
        CHECK_EQ_INT(app_ota_session_feed(&s, img, 4096), 0);
        CHECK_EQ_INT(app_ota_session_finish(&s), -1);
        CHECK(strcmp(s.fail_reason, "short_body") == 0);
        CHECK_EQ_INT(flash.set_boots, 0);
    }

    /* One byte at a time still assembles the header and writes it once. */
    {
        fake_ops_init(&ops, &flash);
        app_ota_session_begin(&s, &ops, 1024);
        uint8_t *small = make_image(1024, header);
        CHECK(small != NULL);
        for (size_t i = 0; i < 1024; i++) {
            CHECK_EQ_INT(app_ota_session_feed(&s, small + i, 1), 0);
        }
        CHECK_EQ_INT(app_ota_session_finish(&s), 0);
        CHECK_EQ_INT(flash.begins, 1);
        CHECK_EQ_INT(flash.written, 1024);
        CHECK_EQ_INT(memcmp(flash.first, header, APP_OTA_HEADER_MIN), 0);
        free(small);
    }

    free(img);
}

/* ── the health gate (03 §3.7) ─────────────────────────────────────── */

static app_ota_gate_facts_t healthy(void) {
    app_ota_gate_facts_t f = {
        .pending_verify = true,
        .storage_mounted = true,
        .net_settled = true,
        .httpd_listening = true,
        .reset_was_crash = false,
        .uptime_s = APP_OTA_GATE_UPTIME_S,
    };
    return f;
}

static void test_gate(void) {
    uint32_t mask = 0xFFFFFFFFu;

    /* The happy verdict. */
    app_ota_gate_facts_t f = healthy();
    CHECK_EQ_INT(app_ota_gate_eval(&f, &mask), APP_OTA_GATE_PASS);
    CHECK_EQ_INT(mask, 0);

    /* 119 s is waiting; 120 s is not. */
    f = healthy();
    f.uptime_s = APP_OTA_GATE_UPTIME_S - 1;
    CHECK_EQ_INT(app_ota_gate_eval(&f, &mask), APP_OTA_GATE_WAITING);
    f.uptime_s = APP_OTA_GATE_UPTIME_S;
    CHECK_EQ_INT(app_ota_gate_eval(&f, &mask), APP_OTA_GATE_PASS);

    /* Each clause on its own. */
    f = healthy();
    f.storage_mounted = false;
    CHECK_EQ_INT(app_ota_gate_eval(&f, &mask), APP_OTA_GATE_FAIL);
    CHECK_EQ_INT(mask, APP_OTA_GATE_CLAUSE_STORAGE);
    f = healthy();
    f.net_settled = false;
    CHECK_EQ_INT(app_ota_gate_eval(&f, &mask), APP_OTA_GATE_FAIL);
    CHECK_EQ_INT(mask, APP_OTA_GATE_CLAUSE_NET);
    f = healthy();
    f.httpd_listening = false;
    CHECK_EQ_INT(app_ota_gate_eval(&f, &mask), APP_OTA_GATE_FAIL);
    CHECK_EQ_INT(mask, APP_OTA_GATE_CLAUSE_HTTPD);

    /* The mask names EVERY failing clause, not just the first. */
    f = healthy();
    f.storage_mounted = false;
    f.net_settled = false;
    f.httpd_listening = false;
    CHECK_EQ_INT(app_ota_gate_eval(&f, &mask), APP_OTA_GATE_FAIL);
    CHECK_EQ_INT(mask, APP_OTA_GATE_CLAUSE_STORAGE |
                           APP_OTA_GATE_CLAUSE_NET |
                           APP_OTA_GATE_CLAUSE_HTTPD);

    /* A crash reset fails AT ONCE — waiting out the remaining 119 s
     * serves nothing when the verdict is already known. */
    f = healthy();
    f.reset_was_crash = true;
    f.uptime_s = 1;
    CHECK_EQ_INT(app_ota_gate_eval(&f, &mask), APP_OTA_GATE_FAIL);
    CHECK(mask & APP_OTA_GATE_CLAUSE_CRASH);

    /* A brownout is the world's fault, not the image's: with every other
     * clause met this must PASS. (reset_was_crash is false for
     * BROWNOUT/POWERON/SW — see app_ota.c's reset_was_crash().) */
    f = healthy();
    CHECK_EQ_INT(app_ota_gate_eval(&f, &mask), APP_OTA_GATE_PASS);

    /* Not pending verify: nothing to confirm and nothing to roll back,
     * however badly the clauses fail. Confirming or rolling back an image
     * nobody is verifying is a bug. */
    f = healthy();
    f.pending_verify = false;
    f.storage_mounted = false;
    f.net_settled = false;
    f.httpd_listening = false;
    f.reset_was_crash = true;
    CHECK_EQ_INT(app_ota_gate_eval(&f, &mask), APP_OTA_GATE_NOT_APPLICABLE);
    CHECK_EQ_INT(mask, 0);

    CHECK_EQ_INT(app_ota_gate_eval(NULL, &mask),
                 APP_OTA_GATE_NOT_APPLICABLE);

    /* Verdict names are the /status.ota strings. */
    CHECK(strcmp(app_ota_gate_verdict_str(APP_OTA_GATE_NOT_APPLICABLE),
                 "not_applicable") == 0);
    CHECK(strcmp(app_ota_gate_verdict_str(APP_OTA_GATE_WAITING),
                 "waiting") == 0);
    CHECK(strcmp(app_ota_gate_verdict_str(APP_OTA_GATE_PASS), "passed") ==
          0);
    CHECK(strcmp(app_ota_gate_verdict_str(APP_OTA_GATE_FAIL), "failed") ==
          0);

    /* Clause rendering, including the truncation path. */
    char buf[64];
    CHECK_EQ_INT(app_ota_gate_clauses_str(0, buf, sizeof buf), 0);
    CHECK_EQ_INT(buf[0], '\0');
    (void)app_ota_gate_clauses_str(APP_OTA_GATE_CLAUSE_STORAGE |
                                       APP_OTA_GATE_CLAUSE_HTTPD,
                                   buf, sizeof buf);
    CHECK(strcmp(buf, "storage,httpd") == 0);
    (void)app_ota_gate_clauses_str(0xFu, buf, sizeof buf);
    CHECK(strcmp(buf, "storage,net,httpd,crash") == 0);
    char tiny[8];
    (void)app_ota_gate_clauses_str(0xFu, tiny, sizeof tiny);
    CHECK(strcmp(tiny, "storage") == 0); /* truncates, never overruns */
}

int main(void) {
    uint8_t app[APP_OTA_HEADER_MIN];
    uint8_t boot[APP_OTA_HEADER_MIN];
    CHECK_EQ_INT(load_fixture("app-heltec-v3-header.bin", app, sizeof app),
                 APP_OTA_HEADER_MIN);
    CHECK_EQ_INT(load_fixture("bootloader-header.bin", boot, sizeof boot),
                 APP_OTA_HEADER_MIN);

    test_image_inspect();
    test_admission();
    test_upload_happy_path(app);
    test_upload_failures(app, boot);
    test_gate();

    return test_summary("test_app_ota");
}
