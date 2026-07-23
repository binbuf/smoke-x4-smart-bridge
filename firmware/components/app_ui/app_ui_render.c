/* app_ui_render.c — overlay renderers (F11a.4; design 07 §7.3,
 * 05 §5.6).
 *
 * Pure functions of the snapshot struct (07 §7.6). No clock, no I²C, no
 * event bus: given the same app_ui_state_t they produce the same 1024
 * bytes, which is what lets CI review them as pictures.
 */
#include "app_ui_core.h"

#include <string.h>

/* §7.3's mock, transcribed:
 *
 *   ┌─────────────────────┐
 *   │  PAIR WITH PHONE    │  row 0, small font
 *   │                     │  row 1
 *   │      418 302        │  rows 2-4, large font, group gap
 *   │                     │
 *   │  enter this code    │  row 5
 *   │  in the app         │  row 6
 *   │●sta  04:12  71%     │  row 7 — BLANK in M3, see the header
 *   └─────────────────────┘
 *
 * The three text lines sit at the mock's own left margin (column 2); the
 * digits are centred, because at 12 px a cell grid would misplace them.
 */
#define PASSKEY_TEXT_COL 2
#define PASSKEY_TITLE_ROW 0
#define PASSKEY_HINT_ROW_1 5
#define PASSKEY_HINT_ROW_2 6
/* The 24 px digit block is centred in the 32 px gap between the title row
 * and the hints (y 8..39): 4 px of air above and below. Dropping it on
 * row 2 instead gives an 8/0 split, which puts the digits hard against
 * "enter this code" — reviewed as a PNG, which is the point of F11a.2. */
#define PASSKEY_DIGITS_Y 12

void app_ui_render_overlay_passkey(const app_ui_state_t *st, app_ui_fb_t *fb) {
    app_ui_fb_clear(fb);
    if (st == NULL) {
        return;
    }

    app_ui_draw_text(fb, PASSKEY_TEXT_COL, PASSKEY_TITLE_ROW,
                     "PAIR WITH PHONE");

    /* "418302" renders as "418 302": one grouped space, so six digits are
     * read as two triplets rather than a number to be misremembered. The
     * separator is a real space glyph, so the width maths stays honest. */
    char grouped[APP_UI_PASSKEY_DIGITS + 2];
    size_t out = 0;
    for (size_t i = 0; i < APP_UI_PASSKEY_DIGITS; i++) {
        const char c = st->passkey[i];
        if (c == '\0') {
            break;
        }
        if (i == 3) {
            grouped[out++] = ' ';
        }
        grouped[out++] = c;
    }
    grouped[out] = '\0';
    (void)app_ui_draw_text_large_centred(fb, PASSKEY_DIGITS_Y, grouped);

    app_ui_draw_text(fb, PASSKEY_TEXT_COL, PASSKEY_HINT_ROW_1,
                     "enter this code");
    app_ui_draw_text(fb, PASSKEY_TEXT_COL, PASSKEY_HINT_ROW_2, "in the app");
}
