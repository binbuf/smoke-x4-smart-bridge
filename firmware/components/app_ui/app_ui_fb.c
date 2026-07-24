/* app_ui_fb.c — framebuffer and drawing primitives (F11a.1, 07 §7.1/§7.6).
 *
 * The page-ordered 1 KB buffer and the 5x7 draw loop come from the
 * reference's main/app_display.c (MIT, see docs/reference/PROVENANCE.md);
 * what is new here is that everything clips, everything is a pure function
 * of an explicitly-passed buffer, and text is addressed in cells so the
 * 21x8 grid is a type-level fact rather than a convention.
 */
#include "app_ui_core.h"

#include <stdint.h>
#include <string.h>

void app_ui_fb_clear(app_ui_fb_t *fb) { memset(fb->px, 0, sizeof fb->px); }

static bool in_bounds(int x, int y) {
    return x >= 0 && x < APP_UI_WIDTH && y >= 0 && y < APP_UI_HEIGHT;
}

void app_ui_set_pixel(app_ui_fb_t *fb, int x, int y, bool on) {
    if (!in_bounds(x, y)) {
        return;
    }
    const size_t i = (size_t)(y / 8) * APP_UI_WIDTH + (size_t)x;
    const uint8_t mask = (uint8_t)(1u << (y % 8));
    if (on) {
        fb->px[i] |= mask;
    } else {
        fb->px[i] = (uint8_t)(fb->px[i] & ~mask);
    }
}

bool app_ui_get_pixel(const app_ui_fb_t *fb, int x, int y) {
    if (!in_bounds(x, y)) {
        return false;
    }
    const size_t i = (size_t)(y / 8) * APP_UI_WIDTH + (size_t)x;
    return (fb->px[i] & (uint8_t)(1u << (y % 8))) != 0;
}

void app_ui_draw_hline(app_ui_fb_t *fb, int x, int y, int w, bool on) {
    for (int i = 0; i < w; i++) {
        app_ui_set_pixel(fb, x + i, y, on);
    }
}

void app_ui_draw_vline(app_ui_fb_t *fb, int x, int y, int h, bool on) {
    for (int i = 0; i < h; i++) {
        app_ui_set_pixel(fb, x, y + i, on);
    }
}

void app_ui_draw_rect(app_ui_fb_t *fb, int x, int y, int w, int h, bool filled,
                      bool on) {
    if (w <= 0 || h <= 0) {
        return;
    }
    if (filled) {
        for (int row = 0; row < h; row++) {
            app_ui_draw_hline(fb, x, y + row, w, on);
        }
        return;
    }
    app_ui_draw_hline(fb, x, y, w, on);
    app_ui_draw_hline(fb, x, y + h - 1, w, on);
    app_ui_draw_vline(fb, x, y, h, on);
    app_ui_draw_vline(fb, x + w - 1, y, h, on);
}

void app_ui_invert_region(app_ui_fb_t *fb, int x, int y, int w, int h) {
    for (int row = 0; row < h; row++) {
        for (int col = 0; col < w; col++) {
            const int px = x + col;
            const int py = y + row;
            if (in_bounds(px, py)) {
                app_ui_set_pixel(fb, px, py, !app_ui_get_pixel(fb, px, py));
            }
        }
    }
}

/* ── Small font ───────────────────────────────────────────────────── */

void app_ui_draw_char(app_ui_fb_t *fb, int col, int row, char c) {
    if (col < 0 || col >= APP_UI_COLS || row < 0 || row >= APP_UI_ROWS) {
        return;
    }
    unsigned char ch = (unsigned char)c;
    if (ch < 0x20 || ch > 0x7E) {
        ch = (unsigned char)'?';
    }
    const uint8_t *glyph = &app_ui_font5x7[(size_t)(ch - 0x20) * 5];
    const int x0 = col * APP_UI_CELL_W;
    const int y0 = row * APP_UI_CELL_H;
    for (int gx = 0; gx < 5; gx++) {
        const uint8_t bits = glyph[gx];
        for (int gy = 0; gy < 7; gy++) {
            if ((bits >> gy) & 1u) {
                app_ui_set_pixel(fb, x0 + gx, y0 + gy, true);
            }
        }
    }
    /* Column 5 of the cell and row 7 are the inter-glyph gap: left clear. */
}

int app_ui_draw_text(app_ui_fb_t *fb, int col, int row, const char *s) {
    if (s == NULL || row < 0 || row >= APP_UI_ROWS) {
        return 0;
    }
    int drawn = 0;
    for (int c = col; *s != '\0'; s++, c++) {
        if (c < 0) {
            continue; /* scrolled off the left: consumed, not drawn */
        }
        if (c >= APP_UI_COLS) {
            break; /* clipped at column 21, exactly */
        }
        app_ui_draw_char(fb, c, row, *s);
        drawn++;
    }
    return drawn;
}

int app_ui_draw_text_centred(app_ui_fb_t *fb, int row, const char *s) {
    if (s == NULL) {
        return 0;
    }
    const int len = (int)strlen(s);
    int col = (APP_UI_COLS - len) / 2;
    if (col < 0) {
        col = 0;
    }
    return app_ui_draw_text(fb, col, row, s);
}

/* ── Large font ───────────────────────────────────────────────────────
 * Glyph indices: 0-9 are the digits, 10 is space, 11 is the degree sign. */

#define LARGE_SPACE 10
#define LARGE_DEGREE 11

/* Returns the glyph index for the codepoint starting at *s and advances
 * *s past it, or -1 for a byte with no glyph (advanced by one). */
static int large_next(const char **s) {
    const unsigned char c = (unsigned char)**s;
    if (c >= '0' && c <= '9') {
        (*s)++;
        return c - '0';
    }
    if (c == ' ') {
        (*s)++;
        return LARGE_SPACE;
    }
    if (c == 0xB0) { /* bare Latin-1 degree */
        (*s)++;
        return LARGE_DEGREE;
    }
    if (c == 0xC2 && (unsigned char)(*s)[1] == 0xB0) { /* UTF-8 degree */
        *s += 2;
        return LARGE_DEGREE;
    }
    (*s)++;
    return -1;
}

int app_ui_text_large_width(const char *s) {
    if (s == NULL) {
        return 0;
    }
    int w = 0;
    while (*s != '\0') {
        if (large_next(&s) >= 0) {
            w += APP_UI_LARGE_W;
        }
    }
    return w;
}

int app_ui_draw_text_large(app_ui_fb_t *fb, int x, int y, const char *s) {
    if (s == NULL) {
        return 0;
    }
    const int x_start = x;
    while (*s != '\0') {
        const int g = large_next(&s);
        if (g < 0) {
            continue;
        }
        const uint8_t *cols = app_ui_font12x24[g];
        for (int gx = 0; gx < APP_UI_LARGE_W; gx++) {
            for (int band = 0; band < APP_UI_LARGE_H / 8; band++) {
                const uint8_t bits = cols[gx * (APP_UI_LARGE_H / 8) + band];
                for (int b = 0; b < 8; b++) {
                    if ((bits >> b) & 1u) {
                        app_ui_set_pixel(fb, x + gx, y + band * 8 + b, true);
                    }
                }
            }
        }
        x += APP_UI_LARGE_W;
    }
    return x - x_start;
}

int app_ui_draw_text_large_centred(app_ui_fb_t *fb, int y, const char *s) {
    int x = (APP_UI_WIDTH - app_ui_text_large_width(s)) / 2;
    if (x < 0) {
        x = 0;
    }
    (void)app_ui_draw_text_large(fb, x, y, s);
    return x;
}

/* ── F11b.2 — the two primitives 07 §7.6 names and F11a did not build ── */

void app_ui_draw_sparkline(app_ui_fb_t *fb, int x, int y, int w, int h,
                           const int16_t *vals, int n) {
    if (fb == NULL || vals == NULL || n <= 0 || w <= 0 || h <= 0) {
        return;
    }
    /* Auto-scale to the series' own range, skipping detached samples —
     * plotting a detached probe at the bottom of the range would draw a
     * cliff that never happened, which is the graph version of the `0.0`
     * trap 07 §7.2 spends a paragraph on. */
    int32_t lo = INT32_MAX;
    int32_t hi = INT32_MIN;
    int valid = 0;
    for (int i = 0; i < n; i++) {
        if (vals[i] == BRIDGE_TEMP_DETACHED || vals[i] == BRIDGE_TEMP_INVALID) {
            continue;
        }
        if (vals[i] < lo) {
            lo = vals[i];
        }
        if (vals[i] > hi) {
            hi = vals[i];
        }
        valid++;
    }
    if (valid == 0) {
        return; /* nothing honest to draw */
    }
    if (hi == lo) {
        /* A flat series is a flat line, not a division by zero. */
        app_ui_draw_hline(fb, x, y + h / 2, w, true);
        return;
    }

    int prev_px = -1;
    int prev_py = -1;
    for (int col = 0; col < w; col++) {
        /* Bucket rather than drop the tail: 240 ring samples into 21
         * columns must still end at the newest reading. */
        const int first = (int)(((int64_t)col * n) / w);
        int last = (int)(((int64_t)(col + 1) * n) / w);
        if (last <= first) {
            last = first + 1;
        }
        int32_t sum = 0;
        int cnt = 0;
        for (int i = first; i < last && i < n; i++) {
            if (vals[i] == BRIDGE_TEMP_DETACHED ||
                vals[i] == BRIDGE_TEMP_INVALID) {
                continue;
            }
            sum += vals[i];
            cnt++;
        }
        if (cnt == 0) {
            prev_px = -1; /* a hole breaks the line rather than bridging it */
            continue;
        }
        const int32_t avg = sum / cnt;
        const int py =
            y + h - 1 - (int)(((avg - lo) * (h - 1)) / (hi - lo));
        const int px = x + col;
        if (prev_px >= 0) {
            /* Join to the previous column so a steep move is a line, not
             * two disconnected dots on a 16 px tall graph. */
            const int step = py > prev_py ? 1 : -1;
            for (int yy = prev_py; yy != py; yy += step) {
                app_ui_set_pixel(fb, px, yy, true);
            }
        }
        app_ui_set_pixel(fb, px, py, true);
        prev_px = px;
        prev_py = py;
    }
}

void app_ui_draw_progress(app_ui_fb_t *fb, int x, int y, int w, int h,
                          int pct) {
    if (fb == NULL || w <= 2 || h <= 2) {
        return;
    }
    if (pct < 0) {
        pct = 0;
    }
    if (pct > 100) {
        pct = 100;
    }
    app_ui_draw_rect(fb, x, y, w, h, false, true);
    const int inner = w - 2;
    /* Round down: a bar that shows a filled pixel at 0 % is lying about
     * having started. */
    const int fill = (inner * pct) / 100;
    if (fill > 0) {
        app_ui_draw_rect(fb, x + 1, y + 1, fill, h - 2, true, true);
    }
}
