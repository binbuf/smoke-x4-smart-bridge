/*
 * test_ui_render.c - host coverage for the OLED renderer, display sleep and
 * SSD1306 transfer core (T22).
 *
 * The .fb goldens are the contract: they are 1 KB page-ordered framebuffer
 * bytes, exactly what the panel receives. Set SX4_UPDATE_UI_GOLDENS=1 to
 * regenerate them intentionally; the PNG tool is for human review only.
 */
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "ssd1306.h"
#include "test_util.h"
#include "ui_render.h"
#include "ui_sleep.h"

#ifndef SX4_UI_GOLDEN_DIR
#error "SX4_UI_GOLDEN_DIR must be defined by the test build"
#endif

#define CHECK_CONTAINS(haystack, needle)                                  \
    do {                                                                  \
        const char *sx4_h_ = (haystack);                                  \
        const char *sx4_n_ = (needle);                                    \
        if (sx4_h_ == NULL || sx4_n_ == NULL ||                           \
            strstr(sx4_h_, sx4_n_) == NULL) {                             \
            sx4_test_fail_str(__FILE__, __LINE__, #haystack " contains "  \
                                                   #needle,               \
                              sx4_h_, sx4_n_);                            \
        }                                                                 \
    } while (0)

#define CHECK_NOT_CONTAINS(haystack, needle)                              \
    do {                                                                  \
        const char *sx4_h_ = (haystack);                                  \
        const char *sx4_n_ = (needle);                                    \
        if (sx4_h_ != NULL && sx4_n_ != NULL &&                           \
            strstr(sx4_h_, sx4_n_) != NULL) {                             \
            sx4_test_fail_str(__FILE__, __LINE__, #haystack " excludes "  \
                                                   #needle,               \
                              sx4_h_, sx4_n_);                            \
        }                                                                 \
    } while (0)

typedef struct {
    unsigned calls;
    struct {
        bool data;
        size_t len;
        uint8_t bytes[160];
    } call[64];
} mock_bus_t;

static int mock_write(void *ctx, bool data, const uint8_t *buf, size_t len) {
    mock_bus_t *bus = (mock_bus_t *)ctx;
    if (bus->calls >= 64u || len > sizeof(bus->call[0].bytes)) {
        return -1;
    }
    bus->call[bus->calls].data = data;
    bus->call[bus->calls].len = len;
    memcpy(bus->call[bus->calls].bytes, buf, len);
    bus->calls++;
    return 0;
}

static ui_snapshot_t full_snapshot(void) {
    ui_snapshot_t s;
    ui_snapshot_init(&s);
    s.seq = 42;
    s.attached_mask = 0x0Fu;
    s.temp_f10[0] = 1652; /* P1 165.2 F */
    s.temp_f10[1] = 2250;
    s.temp_f10[2] = 803;
    s.temp_f10[3] = 800;
    s.app_connected = true;
    s.storage_ok = true;
    s.battery_pct = 87;
    s.battery_mv = 3890;
    snprintf(s.name, sizeof(s.name), "SmokeX4-A4F2");
    s.phones_paired = 2;
    s.phones_max = UI_PHONES_MAX;
    s.smoke_paired = true;
    s.x4_age_s = 12;
    s.rssi = -71;
    s.frequency_hz = 910500000u;
    s.billows_detected = true;
    s.billows_target_valid = true;
    s.billows_target_f10 = 2250;
    snprintf(s.version, sizeof(s.version), "%s", UI_VERSION);
    s.log_days_left_x10 = 124;
    s.readings_count = 35712u;
    s.uptime_s = 14u * 3600u + 15u * 60u + 30u;
    s.mem_free_kb = 142;
    s.mem_low_kb = 128;
    snprintf(s.passkey, sizeof(s.passkey), "418302");
    s.power_countdown_s = 2;
    return s;
}

static void extract_rows(const ui_framebuffer_t *fb, char rows[UI_TEXT_ROWS][96]) {
    for (uint8_t row = 0; row < UI_TEXT_ROWS; row++) {
        CHECK(ui_fb_extract_row(fb, row, rows[row], 96));
    }
}

static void join_rows(char rows[UI_TEXT_ROWS][96], char *out, size_t out_size) {
    out[0] = '\0';
    for (unsigned i = 0; i < UI_TEXT_ROWS; i++) {
        if (i > 0) {
            strncat(out, " | ", out_size - strlen(out) - 1u);
        }
        strncat(out, rows[i], out_size - strlen(out) - 1u);
    }
}

static void test_primitives(void) {
    ui_framebuffer_t fb;
    ui_fb_clear(&fb);
    for (unsigned i = 0; i < UI_FB_SIZE; i++) {
        CHECK_EQ_INT(((const uint8_t *)&fb)[i], 0);
    }
    ui_fb_set_pixel(&fb, 0, 0, true);
    ui_fb_set_pixel(&fb, 127, 63, true);
    ui_fb_set_pixel(&fb, 1, 9, true);
    CHECK(ui_fb_get_pixel(&fb, 0, 0));
    CHECK(ui_fb_get_pixel(&fb, 127, 63));
    CHECK(ui_fb_get_pixel(&fb, 1, 9));
    CHECK(!ui_fb_get_pixel(&fb, 2, 9));
    CHECK_EQ_INT(fb.page[0][0], 0x01);   /* y=0, page 0 */
    CHECK_EQ_INT(fb.page[1][1], 0x02);   /* y=9 -> page 1, bit 1 */
    CHECK_EQ_INT(fb.page[7][127], 0x80); /* y=63 -> page 7, bit 7 */
    ui_fb_clear(&fb);
    CHECK(!ui_fb_get_pixel(&fb, 0, 0));

    /* The task flushes only on a byte change: identical snapshots must produce
     * an identical frame, and a real value change must not. */
    ui_snapshot_t s = full_snapshot();
    ui_framebuffer_t first;
    ui_render(&first, UI_PAGE_PROBES, &s);
    ui_framebuffer_t again;
    ui_render(&again, UI_PAGE_PROBES, &s);
    CHECK(memcmp(&first, &again, sizeof(first)) == 0);
    s.battery_pct = 41;
    ui_render(&again, UI_PAGE_PROBES, &s);
    CHECK(memcmp(&first, &again, sizeof(first)) != 0);
}

static void test_driver(void) {
    mock_bus_t bus;
    memset(&bus, 0, sizeof(bus));
    ssd1306_io_t io = {.write = mock_write, .ctx = &bus};

    CHECK_EQ_INT(ssd1306_init(&io), SSD1306_OK);
    CHECK(bus.calls == 1u);
    CHECK(!bus.call[0].data);
    CHECK_EQ_INT(bus.call[0].bytes[0], 0xAE);
    CHECK_EQ_INT(bus.call[0].bytes[bus.call[0].len - 1u], 0xAF);

    memset(&bus, 0, sizeof(bus));
    CHECK_EQ_INT(ssd1306_set_power(&io, false), SSD1306_OK);
    CHECK(bus.calls == 1u);
    CHECK_EQ_INT(bus.call[0].bytes[0], 0xAE);
    bus.calls = 0;
    CHECK_EQ_INT(ssd1306_set_power(&io, true), SSD1306_OK);
    CHECK(bus.calls == 1u);
    CHECK_EQ_INT(bus.call[0].bytes[0], 0xAF);

    uint8_t pages[SSD1306_PAGES][SSD1306_WIDTH];
    for (unsigned p = 0; p < SSD1306_PAGES; p++) {
        for (unsigned c = 0; c < SSD1306_WIDTH; c++) {
            pages[p][c] = (uint8_t)((p << 4) | (c & 0x0Fu));
        }
    }
    memset(&bus, 0, sizeof(bus));
    CHECK_EQ_INT(ssd1306_flush(&io, pages), SSD1306_OK);
    CHECK_EQ_INT(bus.calls, SSD1306_PAGES * 3u);
    for (unsigned p = 0; p < SSD1306_PAGES; p++) {
        unsigned base = p * 3u;
        CHECK(!bus.call[base].data);
        CHECK_EQ_INT(bus.call[base].len, 2);
        CHECK_EQ_INT(bus.call[base].bytes[0], 0xB0u | p);
        CHECK_EQ_INT(bus.call[base].bytes[1], 0x00);
        CHECK(!bus.call[base + 1u].data);
        CHECK_EQ_INT(bus.call[base + 1u].bytes[0], 0x10);
        CHECK(bus.call[base + 2u].data);
        CHECK_EQ_INT(bus.call[base + 2u].len, 128);
        CHECK(memcmp(bus.call[base + 2u].bytes, pages[p], 128) == 0);
    }
}

static void test_probes_page(void) {
    ui_snapshot_t s = full_snapshot();
    ui_framebuffer_t fb;
    char rows[UI_TEXT_ROWS][96];
    char joined[768];

    ui_render_page(&fb, UI_PAGE_PROBES, &s);
    extract_rows(&fb, rows);
    join_rows(rows, joined, sizeof(joined));
    CHECK_CONTAINS(rows[0], "P1");
    CHECK_CONTAINS(rows[0], "165.2\xC2\xB0" "F");
    CHECK_CONTAINS(rows[1], "P2");
    CHECK_CONTAINS(rows[1], "225.0\xC2\xB0" "F");
    CHECK_CONTAINS(rows[2], "80.3");
    CHECK_CONTAINS(rows[3], "80.0");
    CHECK_CONTAINS(joined, "App");
    CHECK_CONTAINS(joined, "X4");
    CHECK_CONTAINS(joined, "87%");
    CHECK_NOT_CONTAINS(joined, "0%");

    /* Detached is ---, never 0.0. */
    s.attached_mask = 0x0Eu; /* P1 detached */
    s.temp_f10[0] = INT16_MIN;
    ui_render_page(&fb, UI_PAGE_PROBES, &s);
    extract_rows(&fb, rows);
    join_rows(rows, joined, sizeof(joined));
    CHECK_CONTAINS(rows[0], "---");
    CHECK_NOT_CONTAINS(rows[0], "0.0°F");
    CHECK_NOT_CONTAINS(rows[0], "0.0");

    /* Invalid-but-present is ERR. */
    s.attached_mask = 0x0Fu;
    s.temp_f10[1] = (int16_t)(INT16_MIN + 1);
    ui_render_page(&fb, UI_PAGE_PROBES, &s);
    extract_rows(&fb, rows);
    CHECK_CONTAINS(rows[1], "ERR");

    /* Unknown battery is an em dash, never 0%. */
    s = full_snapshot();
    s.battery_pct = UI_BATTERY_UNKNOWN;
    s.battery_mv = 0;
    ui_render_page(&fb, UI_PAGE_PROBES, &s);
    extract_rows(&fb, rows);
    join_rows(rows, joined, sizeof(joined));
    CHECK_CONTAINS(joined, "\xE2\x80\x94");
    CHECK_NOT_CONTAINS(joined, "0%");

    /* Idle + advertising shows a blinking BT mark; the off phase removes it
     * and a connected bridge never shows it. */
    s = full_snapshot();
    s.app_connected = false;
    s.ble_advertising = true;
    s.ble_blink_on = true;
    ui_render_page(&fb, UI_PAGE_PROBES, &s);
    extract_rows(&fb, rows);
    CHECK_CONTAINS(rows[7], "BT");
    s.ble_blink_on = false;
    ui_render_page(&fb, UI_PAGE_PROBES, &s);
    extract_rows(&fb, rows);
    CHECK_NOT_CONTAINS(rows[7], "BT");
    s.app_connected = true;
    s.ble_advertising = false;
    s.ble_blink_on = true;
    ui_render_page(&fb, UI_PAGE_PROBES, &s);
    extract_rows(&fb, rows);
    CHECK_NOT_CONTAINS(rows[7], "BT");
}

static void test_connection_and_billows(void) {
    ui_snapshot_t s = full_snapshot();
    ui_framebuffer_t fb;
    char rows[UI_TEXT_ROWS][96];
    char joined[768];

    ui_render_page(&fb, UI_PAGE_CONNECTION, &s);
    extract_rows(&fb, rows);
    join_rows(rows, joined, sizeof(joined));
    CHECK_CONTAINS(rows[0], "App");
    CHECK_CONTAINS(rows[0], "connected");
    CHECK_CONTAINS(rows[1], "Name");
    CHECK_CONTAINS(rows[1], "SmokeX4-A4F2");
    CHECK_CONTAINS(rows[2], "Phones paired");
    CHECK_CONTAINS(rows[2], "2/4");
    CHECK_CONTAINS(rows[4], "X4");
    CHECK_CONTAINS(rows[4], "paired");
    CHECK_CONTAINS(rows[5], "Radio");
    CHECK_CONTAINS(rows[5], "910.5 MHz");
    CHECK_CONTAINS(rows[6], "Signal");
    CHECK_CONTAINS(rows[6], "-71");
    CHECK_CONTAINS(rows[0], "App");

    s.smoke_paired = false;
    ui_render_page(&fb, UI_PAGE_CONNECTION, &s);
    extract_rows(&fb, rows);
    join_rows(rows, joined, sizeof(joined));
    CHECK_CONTAINS(joined, "not paired");
    CHECK_CONTAINS(joined, "Scanning 915/920 MHz");
    CHECK_CONTAINS(joined, "Put the Smoke X4 in");
    CHECK_CONTAINS(joined, "SYNC, then hold its");
    CHECK_CONTAINS(joined, "button until it beeps");

    s = full_snapshot();
    ui_render_page(&fb, UI_PAGE_BILLOWS, &s);
    extract_rows(&fb, rows);
    join_rows(rows, joined, sizeof(joined));
    CHECK_CONTAINS(rows[0], "BILLOWS");
    CHECK_CONTAINS(rows[0], "DETECTED");
    CHECK_CONTAINS(rows[1], "SET");
    CHECK_CONTAINS(rows[1], "225.0\xC2\xB0" "F");
    CHECK_CONTAINS(rows[2], "P4");
    CHECK_CONTAINS(rows[2], "80.0");
    CHECK_CONTAINS(joined, "Set on the Smoke X4");
    CHECK_NOT_CONTAINS(joined, "running");

    s.billows_detected = false;
    s.billows_target_valid = false;
    ui_render_page(&fb, UI_PAGE_BILLOWS, &s);
    extract_rows(&fb, rows);
    join_rows(rows, joined, sizeof(joined));
    CHECK_CONTAINS(rows[0], "NOT DETECTED");
    CHECK_CONTAINS(rows[1], "\xE2\x80\x94"); /* SET - until validated */
    CHECK_NOT_CONTAINS(rows[1], "0.0");

    s = full_snapshot();
    s.attached_mask = 0x07u; /* P4 detached */
    s.temp_f10[3] = INT16_MIN;
    ui_render_page(&fb, UI_PAGE_BILLOWS, &s);
    extract_rows(&fb, rows);
    CHECK_CONTAINS(rows[2], "---");
}

static void test_bridge_page(void) {
    ui_snapshot_t s = full_snapshot();
    ui_framebuffer_t fb;
    char rows[UI_TEXT_ROWS][96];
    char joined[768];

    ui_render_page(&fb, UI_PAGE_BRIDGE, &s);
    extract_rows(&fb, rows);
    join_rows(rows, joined, sizeof(joined));
    CHECK_CONTAINS(rows[0], "BRIDGE");
    CHECK_CONTAINS(rows[0], "v0.1.0");
    CHECK_CONTAINS(rows[1], "Battery");
    CHECK_CONTAINS(rows[1], "3.89V");
    CHECK_CONTAINS(rows[1], "87%");
    CHECK_CONTAINS(rows[2], "Log");
    CHECK_CONTAINS(rows[2], "12.4 days left");
    CHECK_CONTAINS(rows[3], "Readings");
    CHECK_CONTAINS(rows[3], "35,712");
    CHECK_CONTAINS(rows[4], "Uptime");
    CHECK_CONTAINS(rows[4], "14:15:30");
    CHECK_CONTAINS(rows[5], "Memory");
    CHECK_CONTAINS(rows[5], "142k/128k");

    s.battery_pct = UI_BATTERY_UNKNOWN;
    s.battery_mv = 0;
    ui_render_page(&fb, UI_PAGE_BRIDGE, &s);
    extract_rows(&fb, rows);
    join_rows(rows, joined, sizeof(joined));
    CHECK_CONTAINS(rows[1], "\xE2\x80\x94");
    CHECK_NOT_CONTAINS(joined, "0%");
}

static void test_overlays(void) {
    ui_snapshot_t s = full_snapshot();
    ui_framebuffer_t fb;
    char rows[UI_TEXT_ROWS][96];
    char joined[768];

    s.overlay_mask = UI_OVERLAY_MASK_PASSKEY;
    CHECK_EQ_INT(ui_effective_overlay(&s), UI_OVERLAY_PASSKEY);
    ui_render(&fb, UI_PAGE_PROBES, &s);
    extract_rows(&fb, rows);
    join_rows(rows, joined, sizeof(joined));
    CHECK_CONTAINS(joined, "PAIR WITH PHONE");
    CHECK_CONTAINS(joined, "enter this code");
    CHECK_CONTAINS(joined, "on your phone");
    /* The 12x24 passkey occupies the middle band; it must be non-empty. */
    unsigned lit = 0;
    for (int y = 16; y < 40; y++) {
        for (int x = 0; x < 128; x++) {
            if (ui_fb_get_pixel(&fb, x, y)) {
                lit++;
            }
        }
    }
    CHECK(lit > 100u);

    s.overlay_mask = UI_OVERLAY_MASK_POWER_OFF;
    s.power_countdown_s = 2;
    ui_render(&fb, UI_PAGE_PROBES, &s);
    extract_rows(&fb, rows);
    join_rows(rows, joined, sizeof(joined));
    CHECK_CONTAINS(joined, "POWER OFF");
    CHECK_CONTAINS(joined, "keep holding");
    CHECK_CONTAINS(joined, "2");
    CHECK_CONTAINS(joined, "release to cancel");
    s.power_countdown_s = 0;
    ui_render(&fb, UI_PAGE_PROBES, &s);
    extract_rows(&fb, rows);
    join_rows(rows, joined, sizeof(joined));
    CHECK_CONTAINS(joined, "release to confirm");

    s.overlay_mask = UI_OVERLAY_MASK_STORAGE_FAILURE;
    ui_render(&fb, UI_PAGE_PROBES, &s);
    extract_rows(&fb, rows);
    join_rows(rows, joined, sizeof(joined));
    CHECK_CONTAINS(joined, "STORAGE UNAVAILABLE");
    CHECK_CONTAINS(joined, "live readings only");
    CHECK_CONTAINS(joined, "this session will");
    CHECK_CONTAINS(joined, "not be recorded");

    s.overlay_mask = UI_OVERLAY_MASK_RESETTING;
    ui_render(&fb, UI_PAGE_PROBES, &s);
    extract_rows(&fb, rows);
    join_rows(rows, joined, sizeof(joined));
    CHECK_CONTAINS(joined, "RESETTING.");
    CHECK_CONTAINS(joined, "do not power off");

    s.overlay_mask = UI_OVERLAY_MASK_CLEARING_LOG;
    ui_render(&fb, UI_PAGE_PROBES, &s);
    extract_rows(&fb, rows);
    join_rows(rows, joined, sizeof(joined));
    CHECK_CONTAINS(joined, "CLEARING LOG.");

    s.overlay_mask = UI_OVERLAY_MASK_OFF;
    ui_render(&fb, UI_PAGE_PROBES, &s);
    unsigned off_lit = 0;
    for (int y = 0; y < 64; y++) {
        for (int x = 0; x < 128; x++) {
            if (ui_fb_get_pixel(&fb, x, y)) {
                off_lit++;
            }
        }
    }
    CHECK(off_lit > 100u);

    s.overlay_mask = UI_OVERLAY_MASK_BOOT;
    ui_render(&fb, UI_PAGE_PROBES, &s);
    extract_rows(&fb, rows);
    join_rows(rows, joined, sizeof(joined));
    CHECK_CONTAINS(joined, "SMOKE X4 BRIDGE");
    CHECK_CONTAINS(joined, "v0.1.0");
    CHECK_CONTAINS(joined, "Attach antenna before");
    CHECK_CONTAINS(joined, "power");

    /* Priority: resetting > clearing > passkey > power > storage > boot. */
    s.overlay_mask = UI_OVERLAY_MASK_BOOT | UI_OVERLAY_MASK_STORAGE_FAILURE |
                     UI_OVERLAY_MASK_POWER_OFF | UI_OVERLAY_MASK_PASSKEY |
                     UI_OVERLAY_MASK_CLEARING_LOG | UI_OVERLAY_MASK_RESETTING |
                     UI_OVERLAY_MASK_OFF;
    CHECK_EQ_INT(ui_effective_overlay(&s), UI_OVERLAY_OFF);
    s.overlay_mask &= (uint8_t)~UI_OVERLAY_MASK_OFF;
    CHECK_EQ_INT(ui_effective_overlay(&s), UI_OVERLAY_RESETTING);
    s.overlay_mask &= (uint8_t)~UI_OVERLAY_MASK_RESETTING;
    CHECK_EQ_INT(ui_effective_overlay(&s), UI_OVERLAY_CLEARING_LOG);
    s.overlay_mask &= (uint8_t)~UI_OVERLAY_MASK_CLEARING_LOG;
    CHECK_EQ_INT(ui_effective_overlay(&s), UI_OVERLAY_PASSKEY);
    s.overlay_mask &= (uint8_t)~UI_OVERLAY_MASK_PASSKEY;
    CHECK_EQ_INT(ui_effective_overlay(&s), UI_OVERLAY_POWER_OFF);
    s.overlay_mask &= (uint8_t)~UI_OVERLAY_MASK_POWER_OFF;
    CHECK_EQ_INT(ui_effective_overlay(&s), UI_OVERLAY_STORAGE_FAILURE);
    s.overlay_mask &= (uint8_t)~UI_OVERLAY_MASK_STORAGE_FAILURE;
    CHECK_EQ_INT(ui_effective_overlay(&s), UI_OVERLAY_BOOT);
    s.overlay_mask = 0;
    CHECK_EQ_INT(ui_effective_overlay(&s), UI_OVERLAY_NONE);
}

static void test_sleep(void) {
    ui_view_t view;
    ui_view_init(&view, UI_PAGE_CONNECTION, UI_TIMEOUT_60S, 1000u);
    CHECK(!view.asleep);
    CHECK_EQ_INT(ui_view_next_tick_ms(&view, 1000u), 60000);
    CHECK(!ui_view_tick(&view, 60999u));
    CHECK_EQ_INT(view.page, UI_PAGE_CONNECTION);
    CHECK(ui_view_tick(&view, 61000u));
    CHECK(view.asleep);
    CHECK_EQ_INT(view.page, UI_PAGE_CONNECTION);
    CHECK_EQ_INT(ui_view_next_tick_ms(&view, 61000u), UINT64_MAX);

    /* Wake resets the timer and never changes the page. */
    CHECK(ui_view_wake(&view, 70000u));
    CHECK(!view.asleep);
    CHECK_EQ_INT(view.page, UI_PAGE_CONNECTION);
    CHECK(!ui_view_tick(&view, 129999u));
    CHECK(ui_view_tick(&view, 130000u));

    /* Never is genuinely never, including after a very long idle. */
    ui_view_init(&view, UI_PAGE_PROBES, UI_TIMEOUT_NEVER, 0u);
    CHECK(!ui_view_tick(&view, UINT64_MAX - 1u));
    CHECK_EQ_INT(ui_view_next_tick_ms(&view, 0u), UINT64_MAX);

    ui_view_init(&view, UI_PAGE_PROBES, UI_TIMEOUT_30S, 0u);
    CHECK(!ui_view_tick(&view, 29999u));
    CHECK(ui_view_tick(&view, 30000u));

    /* Activity restarts the timeout. */
    ui_view_init(&view, UI_PAGE_PROBES, UI_TIMEOUT_120S, 0u);
    ui_view_activity(&view, 100000u);
    CHECK(!ui_view_tick(&view, 159999u));
    CHECK(ui_view_tick(&view, 220000u));

    /* Waking is consumed by the caller: it only changes sleep state. */
    ui_view_init(&view, UI_PAGE_BRIDGE, UI_TIMEOUT_60S, 0u);
    (void)ui_view_wake(&view, 0u);
    CHECK_EQ_INT(view.page, UI_PAGE_BRIDGE);

    ui_view_init(&view, UI_PAGE_PROBES, UI_TIMEOUT_60S, 0u);
    CHECK_EQ_INT(ui_view_next_page(&view, false), UI_PAGE_CONNECTION);
    CHECK_EQ_INT(ui_view_next_page(&view, false), UI_PAGE_BRIDGE);
    CHECK_EQ_INT(ui_view_next_page(&view, false), UI_PAGE_PROBES);

    ui_view_init(&view, UI_PAGE_CONNECTION, UI_TIMEOUT_60S, 0u);
    CHECK_EQ_INT(ui_view_next_page(&view, true), UI_PAGE_BILLOWS);
}

typedef struct {
    const char *name;
    ui_page_t page;
    ui_snapshot_t snapshot;
} golden_case_t;

static void golden_check(const golden_case_t *cases, size_t count) {
    bool update = getenv("SX4_UPDATE_UI_GOLDENS") != NULL;
    for (size_t i = 0; i < count; i++) {
        ui_framebuffer_t fb;
        ui_render(&fb, cases[i].page, &cases[i].snapshot);

        char path[512];
        snprintf(path, sizeof(path), "%s/%s.fb", SX4_UI_GOLDEN_DIR,
                 cases[i].name);
        if (update) {
            FILE *out = fopen(path, "wb");
            CHECK(out != NULL);
            if (out != NULL) {
                size_t written = fwrite(&fb, 1, sizeof(fb), out);
                CHECK_EQ_UINT(written, sizeof(fb));
                fclose(out);
            }
            continue;
        }

        uint8_t expected[UI_FB_SIZE];
        FILE *in = fopen(path, "rb");
        if (in == NULL) {
            fprintf(stderr, "missing golden %s (regenerate with SX4_UPDATE_UI_GOLDENS=1)\n",
                    path);
            sx4_test_fail(__FILE__, __LINE__, "golden file exists");
            continue;
        }
        size_t got = fread(expected, 1, sizeof(expected), in);
        int extra = fgetc(in);
        fclose(in);
        CHECK_EQ_UINT(got, sizeof(expected));
        CHECK_EQ_INT(extra, EOF);
        if (got != sizeof(expected)) {
            continue;
        }
        if (memcmp(expected, &fb, sizeof(fb)) != 0) {
            size_t at = 0;
            while (at < sizeof(fb) && expected[at] == ((uint8_t *)&fb)[at]) {
                at++;
            }
            fprintf(stderr, "golden mismatch %s at byte %u\n", path,
                    (unsigned)at);
            sx4_test_fail(__FILE__, __LINE__, "framebuffer matches golden");
        }
    }
}

/* The golden list is also the coverage gate: every page and every overlay must
 * have at least one committed framebuffer. Adding a page/overlay without a
 * golden fails here even if every existing byte still matches. */
static void check_golden_coverage(const golden_case_t *cases, size_t count) {
    bool page_seen[UI_PAGE_COUNT] = {false};
    uint8_t overlay_seen = 0;
    const uint8_t all_overlays = UI_OVERLAY_MASK_BOOT |
                                 UI_OVERLAY_MASK_STORAGE_FAILURE |
                                 UI_OVERLAY_MASK_POWER_OFF |
                                 UI_OVERLAY_MASK_PASSKEY |
                                 UI_OVERLAY_MASK_CLEARING_LOG |
                                 UI_OVERLAY_MASK_RESETTING |
                                 UI_OVERLAY_MASK_OFF;

    for (size_t i = 0; i < count; i++) {
        CHECK(cases[i].page < UI_PAGE_COUNT);
        page_seen[cases[i].page] = true;
        overlay_seen |= cases[i].snapshot.overlay_mask;
    }
    for (unsigned page = 0; page < UI_PAGE_COUNT; page++) {
        CHECK(page_seen[page]);
    }
    CHECK_EQ_INT(overlay_seen & all_overlays, all_overlays);
    CHECK_EQ_INT(overlay_seen, all_overlays);
}

static void test_goldens(void) {
    golden_case_t cases[17];
    size_t n = 0;
    ui_snapshot_t s;

#define ADD_CASE(label, page_value, snapshot_value)  \
    do {                                             \
        cases[n].name = label;                       \
        cases[n].page = page_value;                  \
        cases[n].snapshot = snapshot_value;          \
        n++;                                         \
    } while (0)

    s = full_snapshot();
    ADD_CASE("01-probes-four", UI_PAGE_PROBES, s);

    s = full_snapshot();
    s.attached_mask = 0x0Eu;
    s.temp_f10[0] = INT16_MIN;
    ADD_CASE("02-probes-detached", UI_PAGE_PROBES, s);

    s = full_snapshot();
    s.temp_f10[1] = (int16_t)(INT16_MIN + 1);
    ADD_CASE("03-probes-invalid", UI_PAGE_PROBES, s);

    s = full_snapshot();
    s.battery_pct = UI_BATTERY_UNKNOWN;
    s.battery_mv = 0;
    ADD_CASE("04-probes-unknown-battery", UI_PAGE_PROBES, s);

    s = full_snapshot();
    ADD_CASE("05-connection-paired", UI_PAGE_CONNECTION, s);

    s = full_snapshot();
    s.smoke_paired = false;
    ADD_CASE("06-connection-unpaired", UI_PAGE_CONNECTION, s);

    s = full_snapshot();
    ADD_CASE("07-billows-detected", UI_PAGE_BILLOWS, s);

    s = full_snapshot();
    s.billows_detected = false;
    s.billows_target_valid = false;
    ADD_CASE("08-billows-not-detected", UI_PAGE_BILLOWS, s);

    s = full_snapshot();
    ADD_CASE("09-bridge", UI_PAGE_BRIDGE, s);

    s = full_snapshot();
    s.overlay_mask = UI_OVERLAY_MASK_PASSKEY;
    ADD_CASE("10-passkey", UI_PAGE_PROBES, s);

    s = full_snapshot();
    s.overlay_mask = UI_OVERLAY_MASK_POWER_OFF;
    s.power_countdown_s = 2;
    ADD_CASE("11-power-off-countdown", UI_PAGE_PROBES, s);

    s = full_snapshot();
    s.overlay_mask = UI_OVERLAY_MASK_STORAGE_FAILURE;
    ADD_CASE("12-storage-failure", UI_PAGE_PROBES, s);

    s = full_snapshot();
    s.overlay_mask = UI_OVERLAY_MASK_RESETTING;
    ADD_CASE("13-resetting", UI_PAGE_PROBES, s);

    s = full_snapshot();
    s.overlay_mask = UI_OVERLAY_MASK_CLEARING_LOG;
    ADD_CASE("14-clearing-log", UI_PAGE_PROBES, s);

    s = full_snapshot();
    s.overlay_mask = UI_OVERLAY_MASK_OFF;
    ADD_CASE("15-off", UI_PAGE_PROBES, s);

    s = full_snapshot();
    s.overlay_mask = UI_OVERLAY_MASK_BOOT;
    ADD_CASE("16-boot", UI_PAGE_PROBES, s);

    s = full_snapshot();
    s.overlay_mask = UI_OVERLAY_MASK_POWER_OFF;
    s.power_countdown_s = 0;
    ADD_CASE("17-power-off-confirm", UI_PAGE_PROBES, s);
#undef ADD_CASE

    check_golden_coverage(cases, n);
    golden_check(cases, n);
}

int main(void) {
    test_primitives();
    test_driver();
    test_probes_page();
    test_connection_and_billows();
    test_bridge_page();
    test_overlays();
    test_sleep();
    test_goldens();
    return sx4_test_summary("ui-render");
}
