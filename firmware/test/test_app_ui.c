/* test_app_ui.c — the display layer on the host (F11a.1–F11a.5).
 *
 * Every pixel decision in M3's display work is settled here, without a
 * panel: primitives are pixel-asserted, clipping is asserted at the exact
 * boundary, the fonts and the §7.3 overlay are byte-compared against
 * committed golden framebuffers (which tools/oled renders to PNG for
 * review — F11a.2), and the SSD1306 bring-up ORDER is asserted through
 * the injected seam, because getting it wrong is a board-found bug that
 * has already cost one bench sitting (V1.4).
 *
 * Run with --write-goldens to regenerate GOLDEN_DIR after a deliberate
 * visual change; review the PNGs before committing.
 */
#include "app_ui_core.h"
#include "app_ui_input.h"
#include "app_ui_led.h"
#include "app_ui_model.h"
#include "app_ui_panel.h"
#include "test_util.h"

#include <stdarg.h>
#include <stdint.h>

static bool g_write_goldens = false;

/* ── golden framebuffers ──────────────────────────────────────────── */

static void golden(const char *name, const app_ui_fb_t *fb) {
    char path[512];
    snprintf(path, sizeof path, "%s/%s.fb", GOLDEN_DIR, name);

    if (g_write_goldens) {
        FILE *f = fopen(path, "wb");
        CHECK(f != NULL);
        if (f != NULL) {
            CHECK_EQ_INT(fwrite(fb->px, 1, sizeof fb->px, f), sizeof fb->px);
            fclose(f);
            printf("  wrote golden %s\n", path);
        }
        return;
    }

    FILE *f = fopen(path, "rb");
    if (f == NULL) {
        fprintf(stderr, "FAIL missing golden %s — run with --write-goldens\n",
                path);
        CHECK(!"missing golden");
        return;
    }
    uint8_t want[APP_UI_FB_BYTES];
    const size_t n = fread(want, 1, sizeof want, f);
    fclose(f);
    CHECK_EQ_INT(n, sizeof want);
    if (memcmp(want, fb->px, sizeof want) != 0) {
        size_t diff = 0;
        for (size_t i = 0; i < sizeof want; i++) {
            if (want[i] != fb->px[i]) {
                diff++;
            }
        }
        fprintf(stderr, "FAIL golden %s differs in %zu of %zu bytes\n", name,
                diff, sizeof want);
        CHECK(!"golden mismatch");
    } else {
        CHECK(1);
    }
    /* Always emit the rendered buffer next to the test binary so CI can
     * turn it into a PNG artifact whether the comparison passed or not —
     * a failing golden is exactly when you want to look at the picture. */
    char out[512];
    snprintf(out, sizeof out, "%s/%s.fb", RENDER_DIR, name);
    FILE *o = fopen(out, "wb");
    if (o != NULL) {
        (void)fwrite(fb->px, 1, sizeof fb->px, o);
        fclose(o);
    }
}

/* ── F11a.1: primitives ───────────────────────────────────────────── */

static void test_pixels_and_pages(void) {
    app_ui_fb_t fb;
    app_ui_fb_clear(&fb);

    /* The page-ordered layout is load-bearing for the flush path: y=0..7
     * share one byte, y=8 starts the next page. */
    app_ui_set_pixel(&fb, 0, 0, true);
    CHECK_EQ_INT(fb.px[0], 0x01);
    app_ui_set_pixel(&fb, 0, 7, true);
    CHECK_EQ_INT(fb.px[0], 0x81);
    app_ui_set_pixel(&fb, 0, 8, true);
    CHECK_EQ_INT(fb.px[APP_UI_WIDTH], 0x01);
    app_ui_set_pixel(&fb, 127, 63, true);
    CHECK_EQ_INT(fb.px[APP_UI_FB_BYTES - 1], 0x80);

    CHECK(app_ui_get_pixel(&fb, 0, 0));
    app_ui_set_pixel(&fb, 0, 0, false);
    CHECK(!app_ui_get_pixel(&fb, 0, 0));
    CHECK(app_ui_get_pixel(&fb, 0, 7)); /* clearing one bit spares its page */
}

static void test_out_of_bounds_is_a_no_op(void) {
    app_ui_fb_t fb;
    app_ui_fb_clear(&fb);
    app_ui_set_pixel(&fb, -1, 0, true);
    app_ui_set_pixel(&fb, 0, -1, true);
    app_ui_set_pixel(&fb, APP_UI_WIDTH, 0, true);
    app_ui_set_pixel(&fb, 0, APP_UI_HEIGHT, true);
    app_ui_set_pixel(&fb, 9999, 9999, true);
    for (size_t i = 0; i < sizeof fb.px; i++) {
        if (fb.px[i] != 0) {
            CHECK(!"an out-of-bounds pixel touched the buffer");
            return;
        }
    }
    CHECK(1);
    CHECK(!app_ui_get_pixel(&fb, -1, -1));
}

static void test_lines_and_rects(void) {
    app_ui_fb_t fb;
    app_ui_fb_clear(&fb);

    app_ui_draw_hline(&fb, 2, 3, 5, true);
    for (int x = 0; x < 10; x++) {
        CHECK_EQ_INT(app_ui_get_pixel(&fb, x, 3), x >= 2 && x < 7);
    }

    app_ui_fb_clear(&fb);
    app_ui_draw_vline(&fb, 4, 6, 5, true);
    for (int y = 0; y < 14; y++) {
        CHECK_EQ_INT(app_ui_get_pixel(&fb, 4, y), y >= 6 && y < 11);
    }

    /* Outline: border set, interior clear. */
    app_ui_fb_clear(&fb);
    app_ui_draw_rect(&fb, 10, 10, 6, 5, false, true);
    CHECK(app_ui_get_pixel(&fb, 10, 10));
    CHECK(app_ui_get_pixel(&fb, 15, 14));
    CHECK(app_ui_get_pixel(&fb, 12, 10));
    CHECK(!app_ui_get_pixel(&fb, 12, 12));
    CHECK(!app_ui_get_pixel(&fb, 16, 10));

    /* Filled. */
    app_ui_fb_clear(&fb);
    app_ui_draw_rect(&fb, 10, 10, 6, 5, true, true);
    CHECK(app_ui_get_pixel(&fb, 12, 12));
    CHECK(!app_ui_get_pixel(&fb, 10, 15));

    /* A degenerate rect draws nothing rather than wrapping. */
    app_ui_fb_clear(&fb);
    app_ui_draw_rect(&fb, 10, 10, 0, 5, true, true);
    app_ui_draw_rect(&fb, 10, 10, 5, -3, true, true);
    for (size_t i = 0; i < sizeof fb.px; i++) {
        if (fb.px[i] != 0) {
            CHECK(!"a zero/negative rect drew something");
            return;
        }
    }
    CHECK(1);
}

static void test_invert_round_trips(void) {
    app_ui_fb_t fb;
    app_ui_fb_clear(&fb);
    app_ui_draw_text(&fb, 0, 0, "ALARM");
    app_ui_draw_rect(&fb, 3, 20, 40, 12, true, true);
    app_ui_fb_t before = fb;

    app_ui_invert_region(&fb, 0, 0, APP_UI_WIDTH, 8);
    CHECK(memcmp(&before, &fb, sizeof fb) != 0);
    app_ui_invert_region(&fb, 0, 0, APP_UI_WIDTH, 8);
    CHECK(memcmp(&before, &fb, sizeof fb) == 0);

    /* A partial region inverts only itself. */
    app_ui_invert_region(&fb, 10, 2, 4, 3);
    CHECK_EQ_INT(app_ui_get_pixel(&fb, 10, 2), !app_ui_get_pixel(&before, 10, 2));
    CHECK_EQ_INT(app_ui_get_pixel(&fb, 14, 2), app_ui_get_pixel(&before, 14, 2));
    CHECK_EQ_INT(app_ui_get_pixel(&fb, 10, 5), app_ui_get_pixel(&before, 10, 5));

    /* Inverting past the edge clips instead of wrapping into page 0. */
    app_ui_fb_t edge;
    app_ui_fb_clear(&edge);
    app_ui_invert_region(&edge, 120, 60, 40, 40);
    CHECK(app_ui_get_pixel(&edge, 127, 63));
    CHECK(!app_ui_get_pixel(&edge, 0, 0));
}

static void test_text_clipping_is_exact(void) {
    app_ui_fb_t fb;
    app_ui_fb_clear(&fb);

    /* 21 columns exactly: a 21-char string fits, a 22nd character does not. */
    CHECK_EQ_INT(app_ui_draw_text(&fb, 0, 0, "123456789012345678901"), 21);
    CHECK_EQ_INT(app_ui_draw_text(&fb, 0, 1, "1234567890123456789012"), 21);

    /* Starting at the last column draws exactly one character. */
    app_ui_fb_clear(&fb);
    CHECK_EQ_INT(app_ui_draw_text(&fb, APP_UI_COLS - 1, 0, "AB"), 1);
    CHECK(app_ui_get_pixel(&fb, (APP_UI_COLS - 1) * APP_UI_CELL_W + 1, 0) ||
          app_ui_get_pixel(&fb, (APP_UI_COLS - 1) * APP_UI_CELL_W + 2, 0));

    /* Starting past it draws nothing. */
    app_ui_fb_clear(&fb);
    CHECK_EQ_INT(app_ui_draw_text(&fb, APP_UI_COLS, 0, "AB"), 0);

    /* Row 8 is off the panel: nothing, and nothing wraps to row 0. */
    app_ui_fb_clear(&fb);
    CHECK_EQ_INT(app_ui_draw_text(&fb, 0, APP_UI_ROWS, "HELLO"), 0);
    CHECK_EQ_INT(app_ui_draw_text(&fb, 0, -1, "HELLO"), 0);
    for (size_t i = 0; i < sizeof fb.px; i++) {
        if (fb.px[i] != 0) {
            CHECK(!"off-panel text wrote into the buffer");
            return;
        }
    }
    CHECK(1);

    /* Row 7 is the last drawable row. */
    app_ui_fb_clear(&fb);
    CHECK_EQ_INT(app_ui_draw_text(&fb, 0, APP_UI_ROWS - 1, "X"), 1);
    CHECK(fb.px[(APP_UI_PAGES - 1) * APP_UI_WIDTH] != 0);
}

static void test_unprintable_becomes_question_mark(void) {
    app_ui_fb_t a;
    app_ui_fb_t b;
    app_ui_fb_clear(&a);
    app_ui_fb_clear(&b);
    app_ui_draw_char(&a, 0, 0, '\x01');
    app_ui_draw_char(&b, 0, 0, '?');
    CHECK(memcmp(&a, &b, sizeof a) == 0);
}

/* ── F11a.3: the 12x24 font ───────────────────────────────────────── */

static void test_large_font_goldens(void) {
    app_ui_fb_t fb;
    app_ui_fb_clear(&fb);
    /* Every glyph the font declares, on one screen: ten digits over two
     * rows, then the space and the degree sign. */
    app_ui_draw_text_large(&fb, 4, 0, "01234");
    app_ui_draw_text_large(&fb, 4, 24, "56789");
    app_ui_draw_text_large(&fb, 100, 40, " \xC2\xB0");
    golden("font-large-glyphs", &fb);
}

static void test_large_font_metrics(void) {
    CHECK_EQ_INT(app_ui_text_large_width("418302"), 6 * APP_UI_LARGE_W);
    CHECK_EQ_INT(app_ui_text_large_width("418 302"), 7 * APP_UI_LARGE_W);
    /* The degree sign is one glyph however it is spelled. */
    CHECK_EQ_INT(app_ui_text_large_width("\xC2\xB0"), APP_UI_LARGE_W);
    CHECK_EQ_INT(app_ui_text_large_width("\xB0"), APP_UI_LARGE_W);
    /* Bytes with no glyph are skipped, never substituted. */
    CHECK_EQ_INT(app_ui_text_large_width("4A1"), 2 * APP_UI_LARGE_W);
    CHECK_EQ_INT(app_ui_text_large_width(""), 0);
    CHECK_EQ_INT(app_ui_text_large_width(NULL), 0);

    /* A passkey-sized string centres on the 128-wide buffer: 7 glyphs is
     * 84 px, so (128 - 84) / 2 = 22. */
    app_ui_fb_t fb;
    app_ui_fb_clear(&fb);
    CHECK_EQ_INT(app_ui_draw_text_large_centred(&fb, 16, "418 302"), 22);
    /* Wider than the panel clamps to 0 rather than going negative. */
    CHECK_EQ_INT(app_ui_draw_text_large_centred(&fb, 16, "0123456789012"), 0);
}

static void test_large_glyphs_stay_in_their_cell(void) {
    app_ui_fb_t fb;
    app_ui_fb_clear(&fb);
    app_ui_draw_text_large(&fb, 0, 0, "8"); /* the densest glyph */
    /* Column 11 is the sidebearing: two adjacent glyphs never touch. */
    for (int y = 0; y < APP_UI_LARGE_H; y++) {
        CHECK(!app_ui_get_pixel(&fb, 11, y));
    }
    /* Nothing below row 23. */
    for (int x = 0; x < APP_UI_LARGE_W; x++) {
        CHECK(!app_ui_get_pixel(&fb, x, APP_UI_LARGE_H));
    }
}

/* ── F11a.4: the passkey overlay ──────────────────────────────────── */

static app_ui_state_t passkey_state(const char *digits) {
    app_ui_state_t st;
    memset(&st, 0, sizeof st);
    st.overlay = APP_UI_OVERLAY_PASSKEY;
    st.soc_pct = BRIDGE_SOC_UNKNOWN;
    snprintf(st.passkey, sizeof st.passkey, "%s", digits);
    return st;
}

static void test_passkey_overlay_goldens(void) {
    /* The canary pair proves the renderer writes only inside the buffer. */
    struct {
        uint32_t before;
        app_ui_fb_t fb;
        uint32_t after;
    } guard = {0xA5A5A5A5u, {{0}}, 0x5A5A5A5Au};

    const app_ui_state_t mock = passkey_state("418302");
    app_ui_render_overlay_passkey(&mock, &guard.fb);
    CHECK_EQ_INT(guard.before, 0xA5A5A5A5u);
    CHECK_EQ_INT(guard.after, 0x5A5A5A5Au);
    golden("passkey-418302", &guard.fb);

    /* THE PROMISE M3 RECORDED, KEPT. F11a left row 7 blank because the
     * status strip's sources (battery SoC, the alarm glyph) were M5
     * components, and said so in app_ui_core.h so the golden would not be
     * mistaken for drift when it changed. It has changed: the strip is on
     * every page AND every overlay now, so row 7 has ink. */
    int strip_pixels = 0;
    for (int x = 0; x < APP_UI_WIDTH; x++) {
        for (int y = 56; y < 64; y++) {
            if (app_ui_get_pixel(&guard.fb, x, y)) {
                strip_pixels++;
            }
        }
    }
    CHECK(strip_pixels > 0);

    const app_ui_state_t zeros = passkey_state("000000");
    app_ui_render_overlay_passkey(&zeros, &guard.fb);
    golden("passkey-000000", &guard.fb);

    const app_ui_state_t nines = passkey_state("999999");
    app_ui_render_overlay_passkey(&nines, &guard.fb);
    golden("passkey-999999", &guard.fb);
}

static void test_passkey_grouping(void) {
    app_ui_fb_t a;
    app_ui_fb_t b;
    /* "418302" must render identically to a manually grouped "418 302" —
     * that IS the grouping rule, stated as an equality. */
    const app_ui_state_t st = passkey_state("418302");
    app_ui_render_overlay_passkey(&st, &a);

    app_ui_fb_clear(&b);
    app_ui_draw_text(&b, 2, 0, "PAIR WITH PHONE");
    app_ui_draw_text_large_centred(&b, 12, "418 302");
    app_ui_draw_text(&b, 2, 5, "enter this code");
    app_ui_draw_text(&b, 2, 6, "in the app");
    /* F11b.1 put the status strip on every overlay too, so the hand-built
     * comparison has to include it — which is itself the assertion that
     * the overlay is not special-cased out of the strip. */
    app_ui_render_strip(&st, &b);
    CHECK(memcmp(&a, &b, sizeof a) == 0);

    /* All-zero and all-nine group the same way, and differ from each
     * other — the two cases most likely to expose an off-by-one. */
    app_ui_fb_t z;
    app_ui_fb_t n;
    const app_ui_state_t zs = passkey_state("000000");
    const app_ui_state_t ns = passkey_state("999999");
    app_ui_render_overlay_passkey(&zs, &z);
    app_ui_render_overlay_passkey(&ns, &n);
    CHECK(memcmp(&z, &n, sizeof z) != 0);
    CHECK_EQ_INT(app_ui_text_large_width("000 000"),
                 app_ui_text_large_width("999 999"));

    /* A NULL snapshot clears rather than crashing or leaving stale ink. */
    app_ui_fb_t stale;
    app_ui_render_overlay_passkey(&st, &stale);
    app_ui_render_overlay_passkey(NULL, &stale);
    for (size_t i = 0; i < sizeof stale.px; i++) {
        if (stale.px[i] != 0) {
            CHECK(!"NULL state left ink on the glass");
            return;
        }
    }
    CHECK(1);
}

/* ── F11a.5: the panel seam ───────────────────────────────────────── */

#define TRACE_MAX 256

typedef struct {
    char step[TRACE_MAX][24];
    int n;
    int fail_at_bus_create;
    int fail_tx;
    int tx_calls;
} fake_panel_t;

static fake_panel_t g_panel;

static void trace(const char *fmt, ...) {
    if (g_panel.n >= TRACE_MAX) {
        return;
    }
    va_list ap;
    va_start(ap, fmt);
    vsnprintf(g_panel.step[g_panel.n], sizeof g_panel.step[0], fmt, ap);
    va_end(ap);
    g_panel.n++;
}

static int fake_vext(void *ctx, bool on) {
    (void)ctx;
    trace("vext:%s", on ? "on" : "off");
    return 0;
}

static int fake_reset(void *ctx, bool high) {
    (void)ctx;
    trace("rst:%d", high ? 1 : 0);
    return 0;
}

static int fake_bus_create(void *ctx) {
    (void)ctx;
    trace("bus_create");
    return g_panel.fail_at_bus_create ? -1 : 0;
}

static int fake_bus_destroy(void *ctx) {
    (void)ctx;
    trace("bus_destroy");
    return 0;
}

static int fake_tx(void *ctx, const uint8_t *buf, size_t len) {
    (void)ctx;
    g_panel.tx_calls++;
    if (buf[0] == 0x00) {
        trace("cmd:%02X", buf[1]);
    } else {
        trace("data:%u", (unsigned)(len - 1));
    }
    return g_panel.fail_tx ? -1 : 0;
}

static void fake_delay(void *ctx, uint32_t ms) {
    (void)ctx;
    trace("delay:%u", (unsigned)ms);
}

static const app_ui_panel_ops_t k_fake_ops = {
    .vext_power = fake_vext,
    .reset_line = fake_reset,
    .bus_create = fake_bus_create,
    .bus_destroy = fake_bus_destroy,
    .tx = fake_tx,
    .delay_ms = fake_delay,
};

static void panel_reset(void) {
    memset(&g_panel, 0, sizeof g_panel);
    app_ui_panel_init(&k_fake_ops, NULL);
}

static int trace_index(const char *step) {
    for (int i = 0; i < g_panel.n; i++) {
        if (strcmp(g_panel.step[i], step) == 0) {
            return i;
        }
    }
    return -1;
}

static void test_bringup_order(void) {
    panel_reset();
    CHECK_EQ_INT(app_ui_panel_bringup(), 0);

    /* The V1.4 rule, as an assertion: the rail is powered before the bus
     * exists, and no transaction happens before the bus exists. */
    const int vext = trace_index("vext:on");
    const int bus = trace_index("bus_create");
    CHECK(vext >= 0);
    CHECK(bus >= 0);
    CHECK(vext < bus);
    for (int i = 0; i < bus; i++) {
        if (strncmp(g_panel.step[i], "cmd:", 4) == 0 ||
            strncmp(g_panel.step[i], "data:", 5) == 0) {
            CHECK(!"I2C traffic before the bus was created");
            break;
        }
    }

    /* The exact opening sequence, in order. */
    static const char *const expect[] = {
        "vext:on", "delay:100", "rst:0", "delay:10",
        "rst:1",   "delay:50",  "bus_create",
    };
    for (size_t i = 0; i < sizeof expect / sizeof expect[0]; i++) {
        CHECK(i < (size_t)g_panel.n);
        if (i < (size_t)g_panel.n) {
            CHECK(strcmp(g_panel.step[i], expect[i]) == 0);
        }
    }

    /* The exact SSD1306 init command sequence follows. */
    static const uint8_t init_expect[] = {
        0xAE, 0xD5, 0x80, 0xA8, 0x3F, 0xD3, 0x00, 0x40, 0x8D, 0x14, 0x20, 0x00,
        0xA1, 0xC8, 0xDA, 0x12, 0x81, 0xCF, 0xD9, 0xF1, 0xDB, 0x40, 0xA4, 0xA6,
    };
    const int first_cmd = 7;
    for (size_t i = 0; i < sizeof init_expect; i++) {
        char want[24];
        snprintf(want, sizeof want, "cmd:%02X", init_expect[i]);
        CHECK(first_cmd + (int)i < g_panel.n);
        if (first_cmd + (int)i < g_panel.n) {
            CHECK(strcmp(g_panel.step[first_cmd + i], want) == 0);
        }
    }
    /* Bring-up leaves the glass dark: 0xAF is never sent here. The sleep
     * policy (F11b.9) decides when the panel comes on, so bring-up never
     * lights it on its own. */
    CHECK_EQ_INT(trace_index("cmd:AF"), -1);
    CHECK(!app_ui_panel_is_awake());
}

static void test_bringup_failure_leaves_no_half_state(void) {
    panel_reset();
    g_panel.fail_at_bus_create = 1;
    CHECK(app_ui_panel_bringup() != 0);
    /* The rail stays up so a retry does not repeat the settle delay, and
     * no traffic was attempted on a bus that does not exist. */
    CHECK(trace_index("vext:on") >= 0);
    CHECK_EQ_INT(g_panel.tx_calls, 0);
    /* Rendering before a successful bring-up is a no-op, not a crash. */
    const app_ui_state_t st = passkey_state("418302");
    CHECK(!app_ui_panel_render(&st));
    CHECK_EQ_INT(g_panel.tx_calls, 0);
}

static void test_render_only_on_change(void) {
    panel_reset();
    CHECK_EQ_INT(app_ui_panel_bringup(), 0);

    /* F11b.9 — a SLEEPING panel does zero I²C. "The display is off" and
     * "the driver stopped talking to it" are different claims, and only
     * the second one saves the ~10 mA that makes an AP-mode bridge last a
     * cook (07 §7.1, 01 §1.6). */
    const int after_init = g_panel.tx_calls;
    const app_ui_state_t show = passkey_state("418302");
    CHECK(!app_ui_panel_is_awake());
    CHECK(!app_ui_panel_render(&show));
    CHECK_EQ_INT(g_panel.tx_calls, after_init);

    app_ui_panel_set_awake(true);
    const int after_wake = g_panel.tx_calls;
    CHECK(app_ui_panel_render(&show));
    const int after_first = g_panel.tx_calls;
    /* 6 window command bytes + 8 page writes. */
    CHECK_EQ_INT(after_first - after_wake, 6 + APP_UI_PAGES);
    CHECK(app_ui_panel_is_awake());

    /* The reference redrew unconditionally at 1 Hz. We do not: an
     * unchanged snapshot costs zero I²C transactions (07 §7.6). */
    CHECK(!app_ui_panel_render(&show));
    CHECK(!app_ui_panel_render(&show));
    CHECK_EQ_INT(g_panel.tx_calls, after_first);

    /* A different passkey redraws. */
    const app_ui_state_t other = passkey_state("000000");
    CHECK(app_ui_panel_render(&other));
    CHECK(g_panel.tx_calls > after_first);

    /* Bonding ends: the overlay clears and the PAGE takes over — M5's
     * panel is always on, so blanking is now the sleep policy's job and
     * not the passkey's. */
    app_ui_state_t done;
    memset(&done, 0, sizeof done);
    done.soc_pct = BRIDGE_SOC_UNKNOWN;
    CHECK(app_ui_panel_render(&done));
    CHECK(app_ui_panel_is_awake());
    app_ui_panel_set_awake(false);
    CHECK(trace_index("cmd:AE") >= 0);
    const int after_blank = g_panel.tx_calls;
    CHECK(!app_ui_panel_render(&done));
    CHECK_EQ_INT(g_panel.tx_calls, after_blank);

    /* And waking it redraws from scratch rather than trusting whatever
     * was on the glass before the sleep. */
    app_ui_panel_set_awake(true);
    CHECK(app_ui_panel_render(&show));
    CHECK(app_ui_panel_is_awake());
}

static void test_flush_writes_the_whole_panel(void) {
    panel_reset();
    CHECK_EQ_INT(app_ui_panel_bringup(), 0);
    app_ui_panel_set_awake(true);
    const app_ui_state_t show = passkey_state("418302");
    CHECK(app_ui_panel_render(&show));

    /* Horizontal addressing over the full window, then 8 x 128 data
     * bytes — 1024, the whole 1 KB buffer, with no staging copy. */
    CHECK(trace_index("cmd:21") >= 0);
    CHECK(trace_index("cmd:22") >= 0);
    int pages = 0;
    for (int i = 0; i < g_panel.n; i++) {
        if (strcmp(g_panel.step[i], "data:128") == 0) {
            pages++;
        }
    }
    CHECK_EQ_INT(pages, APP_UI_PAGES);
}

/* ══ F11b — the status strip, the five pages, gestures, sleep, LED ══ */

static app_ui_state_t cook_state(void) {
    /* A plausible mid-cook, and the shape most of the goldens vary from. */
    app_ui_state_t st;
    memset(&st, 0, sizeof st);
    st.num_probes = 4;
    st.base_ok = true;
    st.net_mode = APP_UI_NET_STA;
    st.session_active = true;
    st.elapsed_s = 4 * 3600 + 12 * 60 + 30;
    st.soc_pct = 71;
    snprintf(st.probe[0].name, sizeof st.probe[0].name, "Pit");
    st.probe[0].role = BRIDGE_PROBE_ROLE_PIT;
    st.probe[0].temp_f10 = 2430;
    st.probe[0].target_f10 = 2500;
    st.probe[0].has_band = true;
    st.probe[0].band_lo_f10 = 2040;
    st.probe[0].band_hi_f10 = 2500;
    st.probe[0].slope_valid = true;
    st.probe[0].slope_f10_per_hr = -24;
    snprintf(st.probe[1].name, sizeof st.probe[1].name, "Brisket");
    st.probe[1].role = BRIDGE_PROBE_ROLE_FOOD;
    st.probe[1].temp_f10 = 1632;
    st.probe[1].target_f10 = 2030;
    st.probe[1].slope_valid = true;
    st.probe[1].slope_f10_per_hr = 41;
    snprintf(st.probe[2].name, sizeof st.probe[2].name, "Point");
    st.probe[2].role = BRIDGE_PROBE_ROLE_FOOD;
    st.probe[2].temp_f10 = 1594;
    st.probe[2].slope_valid = true;
    st.probe[2].slope_f10_per_hr = 38;
    snprintf(st.probe[3].name, sizeof st.probe[3].name, "Flat");
    st.probe[3].role = BRIDGE_PROBE_ROLE_FOOD;
    st.probe[3].temp_f10 = BRIDGE_TEMP_DETACHED;
    st.session_id = 27;
    snprintf(st.session_name, sizeof st.session_name, "Brisket");
    st.sample_count = 1440;
    st.mark_count = 3;
    st.eta_valid = true;
    st.eta_s = 6 * 3600 + 20 * 60;
    for (int i = 0; i < 48; i++) {
        st.spark[i] = (int16_t)(2400 + (i % 12) * 8 - (i / 12) * 5);
    }
    st.spark_n = 48;
    snprintf(st.ssid, sizeof st.ssid, "Backyard");
    snprintf(st.psk, sizeof st.psk, "Gk7mR2xQpT");
    snprintf(st.ip, sizeof st.ip, "192.168.1.42");
    snprintf(st.host, sizeof st.host, "smokebridge.local");
    st.wifi_rssi = -54;
    st.net_state = APP_UI_NET_UP;
    st.ble_conns = 1;
    st.ble_bonds = 2;
    st.paired = true;
    snprintf(st.device_id, sizeof st.device_id, "|abCDe");
    st.frequency_hz = 910500000u;
    st.lora_rssi = -71;
    st.lora_snr = 9;
    st.last_packet_s = 12;
    st.packets_ok = 4102;
    st.packets_bad = 3;
    st.interval_s10 = 300;
    snprintf(st.fw, sizeof st.fw, "v1.0.0");
    st.uptime_s = 14 * 3600 + 15 * 60 + 30;
    st.storage_total_b = 2490368;
    st.storage_used_b = 214016;
    st.sessions = 12;
    st.heap_free = 172032;
    st.heap_min = 144384;
    st.mv = 3894;
    st.i2c_ok = 1160;
    st.i2c_err = 0;
    return st;
}

/* Is row 7 — the status strip's row — inked at all? */
static bool strip_has_ink(const app_ui_fb_t *fb) {
    for (int x = 0; x < APP_UI_WIDTH; x++) {
        for (int y = 56; y < 64; y++) {
            if (app_ui_get_pixel(fb, x, y)) {
                return true;
            }
        }
    }
    return false;
}

/* Does any cell in the given range render a DIGIT? The all-detached
 * invariant this project has enforced end to end since M0 is not "the
 * slot is empty" — it is "there is no number there". A15.2 asserts the
 * same thing on the phone; this is its 21x8 equivalent. */
static bool cells_contain_a_digit(const app_ui_fb_t *fb, int r0, int r1,
                                  int c0, int c1) {
    for (int row = r0; row <= r1; row++) {
        for (int col = c0; col <= c1; col++) {
            for (char d = '0'; d <= '9'; d++) {
                app_ui_fb_t probe;
                app_ui_fb_clear(&probe);
                app_ui_draw_char(&probe, col, row, d);
                bool same = true;
                for (int dx = 0; dx < APP_UI_CELL_W && same; dx++) {
                    for (int dy = 0; dy < APP_UI_CELL_H; dy++) {
                        const int x = col * APP_UI_CELL_W + dx;
                        const int y = row * APP_UI_CELL_H + dy;
                        if (app_ui_get_pixel(&probe, x, y) !=
                            app_ui_get_pixel(fb, x, y)) {
                            same = false;
                            break;
                        }
                    }
                }
                if (same) {
                    return true;
                }
            }
        }
    }
    return false;
}

static void test_status_strip_shapes(void) {
    app_ui_fb_t fb;
    app_ui_state_t st = cook_state();

    /* Every page and every overlay gets the strip from one call — that is
     * the whole point of F11b.1, and the reason F11a left the row blank
     * rather than inventing it. */
    app_ui_render_page_probes(&st, &fb);
    CHECK(strip_has_ink(&fb));
    golden("strip-sta-cook", &fb);

    st.base_ok = false;
    st.alarm_unacked = true;
    app_ui_render_page_probes(&st, &fb);
    golden("strip-base-lost-alarm", &fb);

    st = cook_state();
    st.net_mode = APP_UI_NET_AP;
    st.ap_client = true;
    st.charging = true;
    app_ui_render_page_probes(&st, &fb);
    golden("strip-ap-charging", &fb);

    /* No session and no battery data: `--:--` and `--%`, never 00:00 and
     * never 0 % (07 §7.1, P3.2). */
    st = cook_state();
    st.session_active = false;
    st.soc_pct = BRIDGE_SOC_UNKNOWN;
    app_ui_render_page_probes(&st, &fb);
    golden("strip-no-session-no-battery", &fb);
}

static void test_page_probes_goldens(void) {
    app_ui_fb_t fb;
    app_ui_state_t st = cook_state();
    app_ui_render_page_probes(&st, &fb);
    golden("page-probes", &fb);

    /* °C is a DISPLAY concern; storage stays canonical °F (04 §4.2). */
    st.celsius = true;
    app_ui_render_page_probes(&st, &fb);
    golden("page-probes-celsius", &fb);

    /* All detached. The one that matters most: the reference's `0.0` is a
     * real trap on a graph and a real confusion on a screen (07 §7.2), so
     * a detached probe's temperature slot has NO DIGIT in it. */
    st = cook_state();
    for (int i = 0; i < 4; i++) {
        st.probe[i].temp_f10 = BRIDGE_TEMP_DETACHED;
        st.probe[i].slope_valid = false;
    }
    app_ui_render_page_probes(&st, &fb);
    golden("page-probes-all-detached", &fb);
    /* NO DIGIT in any temperature slot — not a 0, not a 0.0. The pit's
     * large block (rows 2-4) and the three compact value slots
     * (cols 8-13 of rows 4-6) are the places a number could appear. */
    CHECK(!cells_contain_a_digit(&fb, 2, 3, 0, APP_UI_COLS - 1));
    CHECK(!cells_contain_a_digit(&fb, 4, 6, 8, 13));

    /* No pit role at all: probe 1 gets the large treatment (07 §7.2). */
    st = cook_state();
    for (int i = 0; i < 4; i++) {
        st.probe[i].role = BRIDGE_PROBE_ROLE_FOOD;
    }
    app_ui_render_page_probes(&st, &fb);
    golden("page-probes-no-pit-role", &fb);

    /* A name long enough to need truncating, pinned so the truncation is
     * reviewed rather than discovered in a dark yard. */
    st = cook_state();
    snprintf(st.probe[1].name, sizeof st.probe[1].name, "Chuck roast big");
    app_ui_render_page_probes(&st, &fb);
    golden("page-probes-long-name", &fb);
}

static void test_page_cook_goldens(void) {
    app_ui_fb_t fb;
    app_ui_state_t st = cook_state();
    app_ui_render_page_cook(&st, &fb);
    golden("page-cook", &fb);

    /* Stalled: the ETA is suppressed with the reason, not replaced by a
     * number (09 §9.4). */
    st.stalled = true;
    app_ui_render_page_cook(&st, &fb);
    golden("page-cook-stalled", &fb);

    /* Under 30 minutes of history — the device refuses to guess. */
    st = cook_state();
    st.eta_valid = false;
    app_ui_render_page_cook(&st, &fb);
    golden("page-cook-no-eta", &fb);

    /* A dropout in the ring: the sparkline breaks rather than bridging a
     * gap that did not happen. */
    st = cook_state();
    for (int i = 16; i < 28; i++) {
        st.spark[i] = BRIDGE_TEMP_DETACHED;
    }
    app_ui_render_page_cook(&st, &fb);
    golden("page-cook-gap", &fb);

    st = cook_state();
    st.session_active = false;
    app_ui_render_page_cook(&st, &fb);
    golden("page-cook-no-session", &fb);
}

static void test_page_network_goldens(void) {
    app_ui_fb_t fb;
    app_ui_state_t st = cook_state();

    st.net_mode = APP_UI_NET_AP;
    st.ap_clients = 1;
    app_ui_render_page_network(&st, &fb);
    golden("page-network-ap", &fb);
    /* The AP page exists to put everything needed to join on the glass —
     * no app, no manual, no default password to look up. If the PSK is
     * not there, the page has no reason to exist. */
    app_ui_fb_t psk_only;
    app_ui_fb_clear(&psk_only);
    app_ui_draw_text(&psk_only, 0, 4, "  Gk7mR2xQpT");
    for (int x = 0; x < APP_UI_WIDTH; x++) {
        for (int y = 32; y < 40; y++) {
            if (app_ui_get_pixel(&psk_only, x, y)) {
                CHECK(app_ui_get_pixel(&fb, x, y));
            }
        }
    }

    st = cook_state();
    app_ui_render_page_network(&st, &fb);
    golden("page-network-sta", &fb);

    st.net_state = APP_UI_NET_CONNECTING;
    st.retry_attempt = 3;
    st.retry_in_s = 292;
    app_ui_render_page_network(&st, &fb);
    golden("page-network-connecting", &fb);
}

static void test_page_radio_and_system_goldens(void) {
    app_ui_fb_t fb;
    app_ui_state_t st = cook_state();
    app_ui_render_page_radio(&st, &fb);
    golden("page-radio-paired", &fb);

    st.paired = false;
    app_ui_render_page_radio(&st, &fb);
    golden("page-radio-unpaired", &fb);

    st = cook_state();
    app_ui_render_page_system(&st, &fb);
    golden("page-system", &fb);

    /* No battery data: `n/a`, never `0%` (P3.2, and the M4 header has
     * rendered this correctly since the MVP). */
    st.soc_pct = BRIDGE_SOC_UNKNOWN;
    app_ui_render_page_system(&st, &fb);
    golden("page-system-no-battery", &fb);
}

static void test_overlay_goldens(void) {
    app_ui_fb_t fb;
    app_ui_state_t st = cook_state();

    st.overlay = APP_UI_OVERLAY_ALARM;
    st.alarm_rule = BRIDGE_ALARM_RULE_TARGET_REACHED;
    st.alarm_probe = 2;
    st.alarm_severity = BRIDGE_ALARM_SEVERITY_CRITICAL;
    st.alarm_value_f10 = 2031;
    st.alarm_unacked = true;
    app_ui_render_overlay_alarm(&st, &fb);
    golden("overlay-alarm-target", &fb);
    /* Inverted video on the title bar: most of row 0 is ink. */
    int row0 = 0;
    for (int x = 0; x < APP_UI_WIDTH; x++) {
        for (int y = 0; y < 8; y++) {
            if (app_ui_get_pixel(&fb, x, y)) {
                row0++;
            }
        }
    }
    CHECK(row0 > APP_UI_WIDTH * 4);

    st.alarm_rule = BRIDGE_ALARM_RULE_PIT_CRASH;
    st.alarm_probe = 1;
    st.alarm_value_f10 = 1900;
    app_ui_render_overlay_alarm(&st, &fb);
    golden("overlay-alarm-pit-crash", &fb);

    st = cook_state();
    st.overlay = APP_UI_OVERLAY_CONFIRM;
    snprintf(st.confirm_text, sizeof st.confirm_text, "Switch to hosting?");
    st.confirm_count = 3;
    app_ui_render_overlay_confirm(&st, &fb);
    golden("overlay-confirm-3", &fb);
    st.confirm_count = 1;
    app_ui_render_overlay_confirm(&st, &fb);
    golden("overlay-confirm-1", &fb);

    st = cook_state();
    st.overlay = APP_UI_OVERLAY_SPLASH;
    st.confirm_count = 3;
    app_ui_render_overlay_splash(&st, &fb);
    golden("overlay-splash", &fb);

    st = cook_state();
    st.overlay = APP_UI_OVERLAY_OTA;
    st.ota_pct = 62;
    snprintf(st.ota_from, sizeof st.ota_from, "1.0.0");
    snprintf(st.ota_to, sizeof st.ota_to, "1.1.0");
    app_ui_render_overlay_ota(&st, &fb);
    golden("overlay-ota", &fb);

    /* The power-off hold, armed: confirm_count 0 flips the copy from
     * "release to cancel" to "release to confirm" (07 §7.4). */
    st = cook_state();
    st.overlay = APP_UI_OVERLAY_CONFIRM;
    snprintf(st.confirm_text, sizeof st.confirm_text, "Power off?");
    st.confirm_count = 0;
    app_ui_render_overlay_confirm(&st, &fb);
    golden("overlay-confirm-armed", &fb);
}

static void test_render_dispatch(void) {
    /* One entry point, so "what is on the glass" has one answer. */
    app_ui_fb_t a;
    app_ui_fb_t b;
    app_ui_state_t st = cook_state();
    for (uint8_t page = 0; page < APP_UI_PAGE_COUNT; page++) {
        st.page = page;
        app_ui_render(&st, &a);
        switch (page) {
        case APP_UI_PAGE_COOK:
            app_ui_render_page_cook(&st, &b);
            break;
        case APP_UI_PAGE_NETWORK:
            app_ui_render_page_network(&st, &b);
            break;
        case APP_UI_PAGE_RADIO:
            app_ui_render_page_radio(&st, &b);
            break;
        case APP_UI_PAGE_SYSTEM:
            app_ui_render_page_system(&st, &b);
            break;
        default:
            app_ui_render_page_probes(&st, &b);
            break;
        }
        CHECK_EQ_INT(memcmp(a.px, b.px, sizeof a.px), 0);
    }
    /* An overlay pre-empts whatever page is showing. */
    st.page = APP_UI_PAGE_SYSTEM;
    st.overlay = APP_UI_OVERLAY_ALARM;
    app_ui_render(&st, &a);
    app_ui_render_overlay_alarm(&st, &b);
    CHECK_EQ_INT(memcmp(a.px, b.px, sizeof a.px), 0);

}

/* ── F11b.2 — the sparkline and the progress bar ────────────────────── */

static int ink_columns(const app_ui_fb_t *fb, int x, int w, int y, int h) {
    int n = 0;
    for (int col = x; col < x + w; col++) {
        for (int row = y; row < y + h; row++) {
            if (app_ui_get_pixel(fb, col, row)) {
                n++;
                break;
            }
        }
    }
    return n;
}

static void test_sparkline_shapes(void) {
    app_ui_fb_t fb;
    int16_t vals[64];

    /* A rising ramp ends higher than it starts — asserted in pixels,
     * because "it drew something" is not the claim. */
    app_ui_fb_clear(&fb);
    for (int i = 0; i < 40; i++) {
        vals[i] = (int16_t)(1000 + i * 20);
    }
    app_ui_draw_sparkline(&fb, 0, 0, 40, 16, vals, 40);
    int first_y = -1;
    int last_y = -1;
    for (int y = 0; y < 16; y++) {
        if (app_ui_get_pixel(&fb, 0, y) && first_y < 0) {
            first_y = y;
        }
        if (app_ui_get_pixel(&fb, 39, y)) {
            last_y = y;
        }
    }
    CHECK(first_y > last_y); /* y grows downward */

    /* Flat: a line, not a division by zero. */
    app_ui_fb_clear(&fb);
    for (int i = 0; i < 40; i++) {
        vals[i] = 2000;
    }
    app_ui_draw_sparkline(&fb, 0, 0, 40, 16, vals, 40);
    CHECK_EQ_INT(ink_columns(&fb, 0, 40, 0, 16), 40);

    /* A hole BREAKS the line rather than bridging it or plotting the
     * detached sample at the bottom of the range. */
    app_ui_fb_clear(&fb);
    for (int i = 0; i < 40; i++) {
        vals[i] = (int16_t)(2000 + (i % 5));
    }
    for (int i = 10; i < 20; i++) {
        vals[i] = BRIDGE_TEMP_DETACHED;
    }
    app_ui_draw_sparkline(&fb, 0, 0, 40, 16, vals, 40);
    CHECK(ink_columns(&fb, 0, 40, 0, 16) < 40);
    CHECK(ink_columns(&fb, 10, 10, 0, 16) == 0);

    /* Degenerate inputs draw nothing and crash nothing. */
    app_ui_fb_clear(&fb);
    app_ui_draw_sparkline(&fb, 0, 0, 40, 16, vals, 0);
    app_ui_draw_sparkline(&fb, 0, 0, 0, 16, vals, 40);
    app_ui_draw_sparkline(&fb, 0, 0, 40, 16, NULL, 40);
    CHECK_EQ_INT(ink_columns(&fb, 0, 128, 0, 64), 0);
    vals[0] = 2000;
    app_ui_draw_sparkline(&fb, 0, 0, 40, 16, vals, 1);
    CHECK(ink_columns(&fb, 0, 40, 0, 16) > 0);

    /* All detached: nothing honest to draw. */
    app_ui_fb_clear(&fb);
    for (int i = 0; i < 40; i++) {
        vals[i] = BRIDGE_TEMP_DETACHED;
    }
    app_ui_draw_sparkline(&fb, 0, 0, 40, 16, vals, 40);
    CHECK_EQ_INT(ink_columns(&fb, 0, 40, 0, 16), 0);

    /* More samples than pixels: it BUCKETS, and still ends at the newest
     * reading rather than dropping the tail. */
    app_ui_fb_clear(&fb);
    for (int i = 0; i < 64; i++) {
        vals[i] = (int16_t)(1000 + i * 10);
    }
    app_ui_draw_sparkline(&fb, 0, 0, 21, 16, vals, 64);
    CHECK_EQ_INT(ink_columns(&fb, 0, 21, 0, 16), 21);

    /* Clipping, like every other primitive. */
    app_ui_fb_clear(&fb);
    app_ui_draw_sparkline(&fb, 120, 60, 40, 16, vals, 64);
    CHECK(1);
}

static void test_progress_bar(void) {
    app_ui_fb_t fb;
    app_ui_fb_clear(&fb);
    app_ui_draw_progress(&fb, 0, 0, 20, 8, 0);
    /* At 0 % the frame is drawn and NOTHING is filled — a bar showing a
     * lit pixel at zero is lying about having started. */
    CHECK(!app_ui_get_pixel(&fb, 1, 4));
    CHECK(app_ui_get_pixel(&fb, 0, 0));

    app_ui_fb_clear(&fb);
    app_ui_draw_progress(&fb, 0, 0, 20, 8, 100);
    CHECK(app_ui_get_pixel(&fb, 18, 4));

    app_ui_fb_clear(&fb);
    app_ui_draw_progress(&fb, 0, 0, 20, 8, 50);
    CHECK(app_ui_get_pixel(&fb, 5, 4));
    CHECK(!app_ui_get_pixel(&fb, 17, 4));

    /* Out of range clamps rather than corrupting the buffer. */
    app_ui_draw_progress(&fb, 0, 0, 20, 8, -10);
    app_ui_draw_progress(&fb, 0, 0, 20, 8, 500);
    app_ui_draw_progress(&fb, 0, 0, 1, 1, 50);
    CHECK(1);
}

/* ── F11b.7 — the gesture machine ──────────────────────────────────── */

typedef struct {
    app_ui_input_t_state in;
    uint32_t t;
} btn_t;

static void btn_init(btn_t *b) {
    app_ui_input_reset(&b->in);
    b->t = 0;
}

/* Feed `ms` of a held/released level in 20 ms samples, returning the last
 * gesture that completed. */
static app_ui_gesture_t btn_feed(btn_t *b, bool pressed, uint32_t ms) {
    app_ui_gesture_t last = APP_UI_GESTURE_NONE;
    for (uint32_t i = 0; i < ms; i += APP_UI_SAMPLE_MS) {
        const app_ui_gesture_t g =
            app_ui_input_sample(&b->in, pressed, b->t);
        if (g != APP_UI_GESTURE_NONE) {
            last = g;
        }
        b->t += APP_UI_SAMPLE_MS;
    }
    return last;
}

static void test_gestures(void) {
    btn_t b;

    /* Tap: emitted the moment it is RELEASED. With double-tap gone there is
     * no window to wait out, so view-cycling has no lag. */
    btn_init(&b);
    CHECK_EQ_INT(btn_feed(&b, true, 200), APP_UI_GESTURE_NONE);
    CHECK_EQ_INT(btn_feed(&b, false, 100), APP_UI_GESTURE_TAP);

    /* Two quick taps are just two taps — two views forward, never one
     * special gesture. */
    btn_init(&b);
    (void)btn_feed(&b, true, 200);
    CHECK_EQ_INT(btn_feed(&b, false, 100), APP_UI_GESTURE_TAP);
    (void)btn_feed(&b, true, 200);
    CHECK_EQ_INT(btn_feed(&b, false, 100), APP_UI_GESTURE_TAP);

    /* HOLD (power off) COMMITS ON RELEASE. Reaching the 2 s threshold
     * emits nothing... */
    btn_init(&b);
    CHECK_EQ_INT(btn_feed(&b, true, 3000), APP_UI_GESTURE_NONE);
    /* ...releasing after it is the commit. */
    CHECK_EQ_INT(btn_feed(&b, false, 100), APP_UI_GESTURE_HOLD);

    /* Released EARLY (past tap length, before 2 s): nothing at all — the
     * visible cancel path for power-off. */
    btn_init(&b);
    (void)btn_feed(&b, true, 1000);
    CHECK_EQ_INT(btn_feed(&b, false, 1000), APP_UI_GESTURE_NONE);

    /* A press that never releases is never a gesture. */
    btn_init(&b);
    CHECK_EQ_INT(btn_feed(&b, true, 30000), APP_UI_GESTURE_NONE);

    /* A 25 ms bounce burst debounces to NOTHING: below the 30 ms window,
     * no level change is ever accepted. */
    btn_init(&b);
    for (int i = 0; i < 40; i++) {
        const app_ui_gesture_t g =
            app_ui_input_sample(&b.in, i % 2 == 0, b.t);
        CHECK_EQ_INT(g, APP_UI_GESTURE_NONE);
        b.t += 20;
    }

    /* THE WAKE PRESS IS CONSUMED. Waking a sleeping display never also
     * changes the page — the user always sees the state they left. */
    btn_init(&b);
    app_ui_input_consume_next(&b.in);
    (void)btn_feed(&b, true, 200);
    CHECK_EQ_INT(btn_feed(&b, false, 800), APP_UI_GESTURE_NONE);
    /* The NEXT press is a real one. */
    (void)btn_feed(&b, true, 200);
    CHECK_EQ_INT(btn_feed(&b, false, 100), APP_UI_GESTURE_TAP);

    /* D3's vocabulary; BACK has no gesture on the one-button board. */
    CHECK_EQ_INT(app_ui_input_vocabulary(APP_UI_GESTURE_TAP),
                 APP_UI_INPUT_NEXT);
    CHECK_EQ_INT(app_ui_input_vocabulary(APP_UI_GESTURE_HOLD),
                 APP_UI_INPUT_SELECT);
}

/* ── F11b.8/F11b.9 — the page model and the sleep policy ────────────── */

static app_ui_action_t g_performed[16];
static int g_performed_n;
static int g_power_calls;
static bool g_power_last;

static void mop_perform(void *ctx, app_ui_action_t a) {
    (void)ctx;
    if (g_performed_n < 16) {
        g_performed[g_performed_n++] = a;
    }
}
static void mop_power(void *ctx, bool on) {
    (void)ctx;
    g_power_calls++;
    g_power_last = on;
}
static const app_ui_model_ops_t k_model_ops = {.perform = mop_perform,
                                               .panel_power = mop_power};

typedef struct {
    app_ui_model_t m;
    app_ui_state_t st;
    uint32_t t;
} model_t;

static void model_init(model_t *w) {
    g_performed_n = 0;
    g_power_calls = 0;
    memset(&w->st, 0, sizeof w->st);
    w->st.soc_pct = BRIDGE_SOC_UNKNOWN;
    w->t = 0;
    app_ui_model_init(&w->m, &k_model_ops);
}

static void model_feed(model_t *w, bool pressed, uint32_t ms,
                       uint16_t timeout_s) {
    for (uint32_t i = 0; i < ms; i += APP_UI_SAMPLE_MS) {
        app_ui_model_tick(&w->m, &w->st, pressed, w->t, timeout_s);
        w->t += APP_UI_SAMPLE_MS;
    }
}

static void model_tap(model_t *w) {
    model_feed(w, true, 200, 0);
    model_feed(w, false, 600, 0);
}

static void test_page_navigation_and_actions(void) {
    model_t w;
    model_init(&w);
    /* Page 1 on boot (07 §7.2). */
    CHECK_EQ_INT(app_ui_model_page(&w.m), APP_UI_PAGE_PROBES);

    for (int i = 1; i < APP_UI_PAGE_COUNT; i++) {
        model_tap(&w);
        CHECK_EQ_INT(app_ui_model_page(&w.m), i);
    }
    model_tap(&w); /* wraps */
    CHECK_EQ_INT(app_ui_model_page(&w.m), APP_UI_PAGE_PROBES);

    /* A tap only navigates — it performs no action. Every control moved to
     * the app; the bridge is a passthrough (07 §7.4). */
    CHECK_EQ_INT(g_performed_n, 0);
}

static void test_power_off_and_alarm_display(void) {
    model_t w;

    /* Holding past 2 s arms power-off: the glass names it and counts down,
     * then reads armed (confirm_count 0). Releasing is the commit. */
    model_init(&w);
    model_feed(&w, true, 1000, 0);
    CHECK_EQ_INT(w.st.overlay, APP_UI_OVERLAY_CONFIRM);
    CHECK(w.st.confirm_text[0] != 0);
    CHECK(w.st.confirm_count > 0);       /* still counting down */
    model_feed(&w, true, 1500, 0);       /* now past the 2 s threshold */
    CHECK_EQ_INT(w.st.confirm_count, 0); /* armed: release to confirm */
    model_feed(&w, false, 100, 0);
    CHECK_EQ_INT(g_performed_n, 1);
    CHECK_EQ_INT(g_performed[0], APP_UI_ACTION_POWER_OFF);
    CHECK_EQ_INT(w.st.overlay, APP_UI_OVERLAY_NONE);

    /* Released before the threshold: nothing commits, the overlay clears. */
    model_init(&w);
    model_feed(&w, true, 1000, 0);
    model_feed(&w, false, 200, 0);
    CHECK_EQ_INT(g_performed_n, 0);
    CHECK_EQ_INT(w.st.overlay, APP_UI_OVERLAY_NONE);

    /* A tap only cycles views and commits nothing — the app owns control. */
    model_init(&w);
    model_tap(&w);
    CHECK_EQ_INT(app_ui_model_page(&w.m), APP_UI_PAGE_COOK);
    CHECK_EQ_INT(g_performed_n, 0);

    /* AN ALARM IS DISPLAYED, NEVER SILENCED HERE. It forces view 1; a tap
     * dismisses the overlay and moves on, but performs NO action — the
     * Smoke X receiver or the app silences it. */
    model_init(&w);
    model_tap(&w);
    model_tap(&w);
    CHECK_EQ_INT(app_ui_model_page(&w.m), APP_UI_PAGE_NETWORK);
    app_ui_model_on_alarm(&w.m, &w.st, w.t);
    CHECK_EQ_INT(app_ui_model_page(&w.m), APP_UI_PAGE_PROBES);
    CHECK_EQ_INT(w.st.overlay, APP_UI_OVERLAY_ALARM);
    g_performed_n = 0;
    model_tap(&w);
    CHECK_EQ_INT(g_performed_n, 0); /* nothing was acked */
    CHECK(w.st.overlay != APP_UI_OVERLAY_ALARM);
    CHECK_EQ_INT(app_ui_model_page(&w.m), APP_UI_PAGE_COOK);

    /* And the 60 s revert: the view comes back on its own, and nothing here
     * touches alarm state. Clearing the screen is not dealing with it. */
    model_init(&w);
    app_ui_model_on_alarm(&w.m, &w.st, w.t);
    model_feed(&w, false, APP_UI_ALARM_OVERLAY_MS + 1000, 0);
    CHECK_EQ_INT(w.st.overlay, APP_UI_OVERLAY_NONE);
    CHECK_EQ_INT(g_performed_n, 0);
}

static void test_sleep_and_wake(void) {
    model_t w;
    model_init(&w);
    CHECK(app_ui_model_awake(&w.m));

    /* 60 s of nothing puts the panel out. */
    model_feed(&w, false, 61000, 60);
    CHECK(!app_ui_model_awake(&w.m));
    CHECK(!g_power_last);

    /* A press wakes it, and that press is CONSUMED — no page change. */
    const uint8_t page_before = app_ui_model_page(&w.m);
    model_feed(&w, true, 200, 60);
    model_feed(&w, false, 800, 60);
    CHECK(app_ui_model_awake(&w.m));
    CHECK_EQ_INT(app_ui_model_page(&w.m), page_before);

    /* An alarm wakes it, and the overlay is what appears. */
    model_feed(&w, false, 61000, 60);
    CHECK(!app_ui_model_awake(&w.m));
    app_ui_model_on_alarm(&w.m, &w.st, w.t);
    CHECK(app_ui_model_awake(&w.m));
    CHECK_EQ_INT(w.st.overlay, APP_UI_OVERLAY_ALARM);

    /* Any of 07 §7.1's other wake sources. */
    model_init(&w);
    model_feed(&w, false, 61000, 60);
    CHECK(!app_ui_model_awake(&w.m));
    app_ui_model_wake(&w.m, w.t);
    CHECK(app_ui_model_awake(&w.m));

    /* A timeout of 0 is the documented always-on setting, not a bug. */
    model_init(&w);
    model_feed(&w, false, 600000, 0);
    CHECK(app_ui_model_awake(&w.m));
}

/* ── F11b.10 — the LED ─────────────────────────────────────────────── */

static void test_led_patterns(void) {
    app_ui_led_input_t in;
    memset(&in, 0, sizeof in);
    in.mode = APP_UI_LED_MODE_ALL;

    /* A blink asserted at ONE instant is not a blink: sample across two
     * full periods and require both states. */
    in.alarm_unacked = true;
    int on = 0;
    int off = 0;
    for (uint32_t t = 0; t < 1000; t += 10) {
        if (app_ui_led_duty(&in, t) > 0) {
            on++;
        } else {
            off++;
        }
    }
    CHECK(on > 30 && off > 30);
    CHECK_EQ_INT(app_ui_led_duty(&in, 0), APP_UI_LED_DUTY_MAX);
    CHECK_EQ_INT(app_ui_led_duty(&in, 300), 0);

    /* Precedence: alarm outranks base-lost outranks heartbeat. */
    in.base_lost = true;
    in.packet_flash = true;
    CHECK_EQ_INT(app_ui_led_pattern(&in, 0), APP_UI_LED_ALARM);
    in.alarm_unacked = false;
    CHECK_EQ_INT(app_ui_led_pattern(&in, 0), APP_UI_LED_BASE_LOST);
    in.base_lost = false;
    CHECK_EQ_INT(app_ui_led_pattern(&in, 0), APP_UI_LED_HEARTBEAT);
    in.pairing = true;
    in.base_lost = true;
    CHECK_EQ_INT(app_ui_led_pattern(&in, 0), APP_UI_LED_PAIRING);
    CHECK_EQ_INT(app_ui_led_duty(&in, 0), APP_UI_LED_DUTY_MAX);

    /* base_lost really is a DOUBLE blink: two on-runs per 2 s period. */
    memset(&in, 0, sizeof in);
    in.mode = APP_UI_LED_MODE_ALL;
    in.base_lost = true;
    int runs = 0;
    bool prev = false;
    for (uint32_t t = 0; t < 2000; t += 10) {
        const bool lit = app_ui_led_duty(&in, t) > 0;
        if (lit && !prev) {
            runs++;
        }
        prev = lit;
    }
    CHECK_EQ_INT(runs, 2);

    /* OTA breathes: it takes several distinct duty values. */
    memset(&in, 0, sizeof in);
    in.mode = APP_UI_LED_MODE_ALL;
    in.ota = true;
    int distinct = 0;
    uint8_t seen[8];
    for (int i = 0; i < 8; i++) {
        seen[i] = app_ui_led_duty(&in, (uint32_t)i * 250u);
    }
    for (int i = 1; i < 8; i++) {
        if (seen[i] != seen[i - 1]) {
            distinct++;
        }
    }
    CHECK(distinct >= 5);

    /* identify returns to the previous pattern after 5 s — it does not
     * latch. */
    memset(&in, 0, sizeof in);
    in.mode = APP_UI_LED_MODE_ALL;
    in.base_lost = true;
    in.identify_until_ms = 5000;
    CHECK_EQ_INT(app_ui_led_pattern(&in, 1000), APP_UI_LED_IDENTIFY);
    CHECK_EQ_INT(app_ui_led_pattern(&in, 6000), APP_UI_LED_BASE_LOST);

    /* The DEFAULT is alarms-only: a light blinking all night on a bedside
     * bridge is a reason to unplug it (07 §7.5). */
    memset(&in, 0, sizeof in);
    in.mode = APP_UI_LED_MODE_ALARMS_ONLY;
    in.base_lost = true;
    for (uint32_t t = 0; t < 2000; t += 10) {
        CHECK_EQ_INT(app_ui_led_duty(&in, t), 0);
    }
    in.alarm_unacked = true;
    CHECK_EQ_INT(app_ui_led_duty(&in, 0), APP_UI_LED_DUTY_MAX);

    /* OFF is zero in EVERY state, including alarm. */
    in.mode = APP_UI_LED_MODE_OFF;
    for (uint32_t t = 0; t < 2000; t += 10) {
        CHECK_EQ_INT(app_ui_led_duty(&in, t), 0);
    }

    /* The buzzer mirrors the ALARM pattern only, and is silent unfitted. */
    memset(&in, 0, sizeof in);
    in.alarm_unacked = true;
    CHECK(!app_ui_buzzer_on(&in, 0)); /* buzzer_enabled false */
    in.buzzer_enabled = true;
    CHECK(app_ui_buzzer_on(&in, 0));
    CHECK(!app_ui_buzzer_on(&in, 300));
    in.alarm_unacked = false;
    in.base_lost = true;
    for (uint32_t t = 0; t < 2000; t += 10) {
        CHECK(!app_ui_buzzer_on(&in, t));
    }
}

/* ── F11b.11 — the panel's I²C counters (V3a.1's deferred row) ─────── */

static void test_i2c_counters_count_both_ways(void) {
    panel_reset();
    uint32_t ok = 0;
    uint32_t err = 0;
    app_ui_panel_counts(&ok, &err);
    CHECK_EQ_INT(ok, 0);
    CHECK_EQ_INT(err, 0);

    CHECK_EQ_INT(app_ui_panel_bringup(), 0);
    app_ui_panel_counts(&ok, &err);
    CHECK(ok > 0);
    CHECK_EQ_INT(err, 0);

    app_ui_panel_set_awake(true);
    const app_ui_state_t st = passkey_state("418302");
    CHECK(app_ui_panel_render(&st));
    uint32_t ok2 = 0;
    app_ui_panel_counts(&ok2, &err);
    CHECK(ok2 > ok);
    CHECK_EQ_INT(err, 0);

    /* Errors are counted SEPARATELY, which is the whole point: an error
     * count with no denominator is not a measurement (V3a.1). */
    g_panel.fail_tx = 1;
    const app_ui_state_t other = passkey_state("000000");
    (void)app_ui_panel_render(&other);
    uint32_t err2 = 0;
    app_ui_panel_counts(&ok, &err2);
    CHECK(err2 > 0);
}

/* F17.6 — the small font renders the degree sign as one glyph in one cell, the
 * same rule the large font already followed. Before this every small-font
 * temperature read "163??F": the degree is emitted as UTF-8 0xC2 0xB0 and each
 * byte fell back to '?'. */
static void test_small_font_degree_glyph(void) {
    app_ui_fb_t fb;
    app_ui_fb_clear(&fb);
    /* '1', UTF-8 degree, 'F' — three visible cells. The split literal stops
     * the compiler folding 0xB0 and 'F' into one \x escape. */
    CHECK_EQ_INT(app_ui_draw_text(&fb, 0, 0, "1\xC2\xB0" "F"), 3);
    /* The degree ring sits in cell 1: top row has ink at x = CELL_W+1 and +3,
     * and the ring is hollow at its centre. */
    CHECK(app_ui_get_pixel(&fb, APP_UI_CELL_W + 1, 0));
    CHECK(app_ui_get_pixel(&fb, APP_UI_CELL_W + 3, 0));
    CHECK(!app_ui_get_pixel(&fb, APP_UI_CELL_W + 2, 1));
    /* 'F' lands in cell 2 — proof the degree took ONE cell, not two. Had both
     * UTF-8 bytes drawn '?', the 'F' would be in cell 3 and cell 2 would carry
     * a '?'. */
    bool cell2_ink = false;
    for (int gx = 0; gx < 5; gx++) {
        for (int gy = 0; gy < 7; gy++) {
            if (app_ui_get_pixel(&fb, 2 * APP_UI_CELL_W + gx, gy)) {
                cell2_ink = true;
            }
        }
    }
    CHECK(cell2_ink);
    /* Bare Latin-1 degree also collapses to a single cell. */
    app_ui_fb_clear(&fb);
    CHECK_EQ_INT(app_ui_draw_text(&fb, 0, 0, "9\xB0"), 2);
}

int main(int argc, char **argv) {
    g_write_goldens = argc > 1 && strcmp(argv[1], "--write-goldens") == 0;

    test_small_font_degree_glyph();

    test_pixels_and_pages();
    test_out_of_bounds_is_a_no_op();
    test_lines_and_rects();
    test_invert_round_trips();
    test_text_clipping_is_exact();
    test_unprintable_becomes_question_mark();
    test_large_font_goldens();
    test_large_font_metrics();
    test_large_glyphs_stay_in_their_cell();
    test_passkey_overlay_goldens();
    test_passkey_grouping();
    test_bringup_order();
    test_bringup_failure_leaves_no_half_state();
    test_render_only_on_change();
    test_flush_writes_the_whole_panel();
    test_status_strip_shapes();
    test_page_probes_goldens();
    test_page_cook_goldens();
    test_page_network_goldens();
    test_page_radio_and_system_goldens();
    test_overlay_goldens();
    test_render_dispatch();
    test_sparkline_shapes();
    test_progress_bar();
    test_gestures();
    test_page_navigation_and_actions();
    test_power_off_and_alarm_display();
    test_sleep_and_wake();
    test_led_patterns();
    test_i2c_counters_count_both_ways();
    return test_summary("test_app_ui");
}
