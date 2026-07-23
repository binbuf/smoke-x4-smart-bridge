/* app_ui_core — the framebuffer, fonts, and overlay renderers (F11a.1,
 * F11a.3, F11a.4; design 07 §7.1, §7.3, §7.6).
 *
 * Pure C11: no ESP-IDF headers, no I²C, no globals that a test cannot
 * reach. The framebuffer is passed in, renderers are pure functions of a
 * snapshot struct, and every pixel decision is assertable on the host and
 * reviewable as a PNG (F11a.2). The thin panel half lives in
 * app_ui_panel.h; the ESP-IDF glue in app_ui.h.
 *
 * M3 SCOPE. F11 splits (see docs/tasks/M3-ble-and-provisioning.md): this
 * is only what F10 needs to bond — the buffer, the two fonts, and the
 * passkey overlay. The five pages, the gesture machine, the sparkline,
 * draw_bitmap/draw_progress, and the sleep policy are F11b in M5. The
 * panel is dark at all other times, which is honest scope, not a stub.
 */
#ifndef APP_UI_CORE_H
#define APP_UI_CORE_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/* ── Geometry (07 §7.1) ───────────────────────────────────────────── */

#define APP_UI_WIDTH 128
#define APP_UI_HEIGHT 64
#define APP_UI_PAGES (APP_UI_HEIGHT / 8)
/* The reference's 1 KB page-ordered buffer, kept deliberately (07 §7.6):
 * byte (page * 128 + x) holds the eight vertical pixels y = page*8 + bit. */
#define APP_UI_FB_BYTES (APP_UI_WIDTH * APP_UI_PAGES)

/* Small font: 5x7 glyphs on a 6x8 cell → exactly 21 columns x 8 rows. */
#define APP_UI_CELL_W 6
#define APP_UI_CELL_H 8
#define APP_UI_COLS (APP_UI_WIDTH / APP_UI_CELL_W)  /* 21 */
#define APP_UI_ROWS (APP_UI_HEIGHT / APP_UI_CELL_H) /* 8 */

/* Large font: 12x24, digits + space + degree (07 §7.1). */
#define APP_UI_LARGE_W 12
#define APP_UI_LARGE_H 24
#define APP_UI_LARGE_GLYPHS 12
#define APP_UI_LARGE_BYTES (APP_UI_LARGE_W * (APP_UI_LARGE_H / 8)) /* 36 */

typedef struct {
    uint8_t px[APP_UI_FB_BYTES];
} app_ui_fb_t;

/* ── Primitives (F11a.1) ──────────────────────────────────────────────
 * Every one of these clips silently: an out-of-bounds coordinate draws
 * nothing rather than corrupting a neighbouring page. */

void app_ui_fb_clear(app_ui_fb_t *fb);
void app_ui_set_pixel(app_ui_fb_t *fb, int x, int y, bool on);
bool app_ui_get_pixel(const app_ui_fb_t *fb, int x, int y);
void app_ui_draw_hline(app_ui_fb_t *fb, int x, int y, int w, bool on);
void app_ui_draw_vline(app_ui_fb_t *fb, int x, int y, int h, bool on);
/* filled=false draws a 1 px outline. */
void app_ui_draw_rect(app_ui_fb_t *fb, int x, int y, int w, int h, bool filled,
                      bool on);
/* XOR a rectangle — applying it twice restores the original buffer, which
 * is what makes the M5 alarm overlay's inverted video cheap. */
void app_ui_invert_region(app_ui_fb_t *fb, int x, int y, int w, int h);

/* ── Small-font text (F11a.1) ─────────────────────────────────────────
 * Addressed in CELLS, not pixels: (col, row) with col < 21, row < 8.
 * Characters outside 0x20..0x7E render as '?' (the reference's rule). */

void app_ui_draw_char(app_ui_fb_t *fb, int col, int row, char c);
/* Draws until the string ends or column 21 is reached; returns how many
 * characters were actually drawn, so clipping is observable, not silent. */
int app_ui_draw_text(app_ui_fb_t *fb, int col, int row, const char *s);
/* Centres `s` on the 21-column grid, left-biased on an odd remainder. */
int app_ui_draw_text_centred(app_ui_fb_t *fb, int row, const char *s);

/* ── Large-font text (F11a.3) ─────────────────────────────────────────
 * Addressed in PIXELS: the 12x24 cell is not row-aligned in general.
 * Accepts '0'-'9', ' ', and the degree sign as either a bare 0xB0 or the
 * UTF-8 pair 0xC2 0xB0 — so a C string literal "243°" just works.
 * Any other byte is skipped, never substituted: a garbled temperature is
 * worse than a short one. */

/* Pixel width `s` will occupy, before any clipping. */
int app_ui_text_large_width(const char *s);
int app_ui_draw_text_large(app_ui_fb_t *fb, int x, int y, const char *s);
/* Horizontally centres on the 128 px buffer; returns the x it chose. */
int app_ui_draw_text_large_centred(app_ui_fb_t *fb, int y, const char *s);

/* Font tables, exposed so the PNG harness and the goldens can reach them. */
extern const uint8_t app_ui_font5x7[95 * 5];
extern const uint8_t app_ui_font12x24[APP_UI_LARGE_GLYPHS][APP_UI_LARGE_BYTES];

/* ── Render snapshot (07 §7.6) ────────────────────────────────────────
 * Renderers are pure functions of this struct. It grows in F11b (M5) with
 * the probe/network/session fields the five pages need; in M3 it carries
 * exactly what the passkey overlay reads. */

#define APP_UI_PASSKEY_DIGITS 6

typedef struct {
    /* True while F10.5 has a passkey outstanding. */
    bool passkey_active;
    /* Six ASCII digits, NUL-terminated. Zero-padded by the producer:
     * a passkey of 418302 is "418302", and of 302 is "000302". */
    char passkey[APP_UI_PASSKEY_DIGITS + 1];
} app_ui_state_t;

/* ── Overlays (F11a.4, 07 §7.3) ───────────────────────────────────── */

/* Renders the §7.3 PAIR WITH PHONE overlay into `fb`, clearing it first.
 * Touches nothing outside the buffer and reads nothing outside `st`.
 *
 * DECIDED DEVIATION FROM §7.3, so the golden is not mistaken for drift:
 * row 7 stays blank in M3. The mock puts the status strip there, but the
 * strip's sources (battery SoC, alarm glyph) are M5 components; F11b adds
 * the strip to every page and overlay in one change. */
void app_ui_render_overlay_passkey(const app_ui_state_t *st, app_ui_fb_t *fb);

#ifdef __cplusplus
}
#endif

#endif /* APP_UI_CORE_H */
