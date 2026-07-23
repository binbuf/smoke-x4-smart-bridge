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
    app_ui_state_t st = {0};
    st.passkey_active = true;
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

    /* Row 7 is deliberately blank in M3 (the status strip is F11b/M5).
     * Asserted here so the golden cannot be mistaken for drift. */
    for (int x = 0; x < APP_UI_WIDTH; x++) {
        for (int y = 56; y < 64; y++) {
            if (app_ui_get_pixel(&guard.fb, x, y)) {
                CHECK(!"row 7 must stay blank in M3");
                x = APP_UI_WIDTH;
                break;
            }
        }
    }
    CHECK(1);

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
    return 0;
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
    /* Bring-up leaves the glass dark: 0xAF is never sent here. M3's panel
     * is off until there is a passkey to show. */
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
    const int after_init = g_panel.tx_calls;

    const app_ui_state_t show = passkey_state("418302");
    CHECK(app_ui_panel_render(&show));
    const int after_first = g_panel.tx_calls;
    /* 6 window command bytes + 8 page writes + the display-on command. */
    CHECK_EQ_INT(after_first - after_init, 6 + APP_UI_PAGES + 1);
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

    /* Bonding ends: the panel is blanked so the code does not sit on the
     * glass for anyone walking past. */
    const app_ui_state_t done = {0};
    CHECK(app_ui_panel_render(&done));
    CHECK(!app_ui_panel_is_awake());
    CHECK(trace_index("cmd:AE") >= 0);
    const int after_blank = g_panel.tx_calls;
    CHECK(!app_ui_panel_render(&done));
    CHECK_EQ_INT(g_panel.tx_calls, after_blank);

    /* And a new pairing wakes it again. */
    CHECK(app_ui_panel_render(&show));
    CHECK(app_ui_panel_is_awake());
}

static void test_flush_writes_the_whole_panel(void) {
    panel_reset();
    CHECK_EQ_INT(app_ui_panel_bringup(), 0);
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

int main(int argc, char **argv) {
    g_write_goldens = argc > 1 && strcmp(argv[1], "--write-goldens") == 0;

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
    return test_summary("test_app_ui");
}
