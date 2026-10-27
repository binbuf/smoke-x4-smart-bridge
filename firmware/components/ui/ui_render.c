/*
 * ui_render.c - pure-C 128x64 page renderer (design 07 sections 7.1-7.3/7.6).
 *
 * The framebuffer is page ordered, exactly as the SSD1306 stores it. Every
 * renderer writes only this structure, so the same code runs on the host and
 * on the panel; the firmware layer owns the I2C transfer.
 *
 * The 5x7 body face is the classic fixed-space bitmap font (the same glyphs
 * used by Adafruit_GFX, BSD licensed); the OLED renders it in a 6x8 cell.
 * The 12x24 numeric face is drawn from seven segments and is used only for
 * the pairing passkey.
 */
#include "ui_render.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* Internal glyph bytes for the two 5x7 status dots. */
#define GLYPH_DOT_FILLED ((unsigned char)0x01)
#define GLYPH_DOT_HOLLOW ((unsigned char)0x02)
/* UTF-8 continuation bytes are decoded in text_glyph(); these are the two
 * custom 5-column glyphs outside ASCII. */
#define GLYPH_DEGREE ((unsigned char)0x03)
#define GLYPH_EM_DASH ((unsigned char)0x04)

static const uint8_t s_font5x7[95][5] = {
    {0x00, 0x00, 0x00, 0x00, 0x00}, /* 0x20   */
    {0x00, 0x00, 0x5F, 0x00, 0x00}, /* 0x21 ! */
    {0x00, 0x07, 0x00, 0x07, 0x00}, /* 0x22 " */
    {0x14, 0x7F, 0x14, 0x7F, 0x14}, /* 0x23 # */
    {0x24, 0x2A, 0x7F, 0x2A, 0x12}, /* 0x24 $ */
    {0x23, 0x13, 0x08, 0x64, 0x62}, /* 0x25 % */
    {0x36, 0x49, 0x56, 0x20, 0x50}, /* 0x26 & */
    {0x00, 0x08, 0x07, 0x03, 0x00}, /* 0x27 ' */
    {0x00, 0x1C, 0x22, 0x41, 0x00}, /* 0x28 ( */
    {0x00, 0x41, 0x22, 0x1C, 0x00}, /* 0x29 ) */
    {0x2A, 0x1C, 0x7F, 0x1C, 0x2A}, /* 0x2A * */
    {0x08, 0x08, 0x3E, 0x08, 0x08}, /* 0x2B + */
    {0x00, 0x80, 0x70, 0x30, 0x00}, /* 0x2C , */
    {0x08, 0x08, 0x08, 0x08, 0x08}, /* 0x2D - */
    {0x00, 0x00, 0x60, 0x60, 0x00}, /* 0x2E . */
    {0x20, 0x10, 0x08, 0x04, 0x02}, /* 0x2F / */
    {0x3E, 0x51, 0x49, 0x45, 0x3E}, /* 0x30 0 */
    {0x00, 0x42, 0x7F, 0x40, 0x00}, /* 0x31 1 */
    {0x72, 0x49, 0x49, 0x49, 0x46}, /* 0x32 2 */
    {0x21, 0x41, 0x49, 0x4D, 0x33}, /* 0x33 3 */
    {0x18, 0x14, 0x12, 0x7F, 0x10}, /* 0x34 4 */
    {0x27, 0x45, 0x45, 0x45, 0x39}, /* 0x35 5 */
    {0x3C, 0x4A, 0x49, 0x49, 0x31}, /* 0x36 6 */
    {0x41, 0x21, 0x11, 0x09, 0x07}, /* 0x37 7 */
    {0x36, 0x49, 0x49, 0x49, 0x36}, /* 0x38 8 */
    {0x46, 0x49, 0x49, 0x29, 0x1E}, /* 0x39 9 */
    {0x00, 0x00, 0x14, 0x00, 0x00}, /* 0x3A : */
    {0x00, 0x40, 0x34, 0x00, 0x00}, /* 0x3B ; */
    {0x00, 0x08, 0x14, 0x22, 0x41}, /* 0x3C < */
    {0x14, 0x14, 0x14, 0x14, 0x14}, /* 0x3D = */
    {0x00, 0x41, 0x22, 0x14, 0x08}, /* 0x3E > */
    {0x02, 0x01, 0x59, 0x09, 0x06}, /* 0x3F ? */
    {0x3E, 0x41, 0x5D, 0x59, 0x4E}, /* 0x40 @ */
    {0x7C, 0x12, 0x11, 0x12, 0x7C}, /* 0x41 A */
    {0x7F, 0x49, 0x49, 0x49, 0x36}, /* 0x42 B */
    {0x3E, 0x41, 0x41, 0x41, 0x22}, /* 0x43 C */
    {0x7F, 0x41, 0x41, 0x41, 0x3E}, /* 0x44 D */
    {0x7F, 0x49, 0x49, 0x49, 0x41}, /* 0x45 E */
    {0x7F, 0x09, 0x09, 0x09, 0x01}, /* 0x46 F */
    {0x3E, 0x41, 0x41, 0x51, 0x73}, /* 0x47 G */
    {0x7F, 0x08, 0x08, 0x08, 0x7F}, /* 0x48 H */
    {0x00, 0x41, 0x7F, 0x41, 0x00}, /* 0x49 I */
    {0x20, 0x40, 0x41, 0x3F, 0x01}, /* 0x4A J */
    {0x7F, 0x08, 0x14, 0x22, 0x41}, /* 0x4B K */
    {0x7F, 0x40, 0x40, 0x40, 0x40}, /* 0x4C L */
    {0x7F, 0x02, 0x1C, 0x02, 0x7F}, /* 0x4D M */
    {0x7F, 0x04, 0x08, 0x10, 0x7F}, /* 0x4E N */
    {0x3E, 0x41, 0x41, 0x41, 0x3E}, /* 0x4F O */
    {0x7F, 0x09, 0x09, 0x09, 0x06}, /* 0x50 P */
    {0x3E, 0x41, 0x51, 0x21, 0x5E}, /* 0x51 Q */
    {0x7F, 0x09, 0x19, 0x29, 0x46}, /* 0x52 R */
    {0x26, 0x49, 0x49, 0x49, 0x32}, /* 0x53 S */
    {0x03, 0x01, 0x7F, 0x01, 0x03}, /* 0x54 T */
    {0x3F, 0x40, 0x40, 0x40, 0x3F}, /* 0x55 U */
    {0x1F, 0x20, 0x40, 0x20, 0x1F}, /* 0x56 V */
    {0x3F, 0x40, 0x38, 0x40, 0x3F}, /* 0x57 W */
    {0x63, 0x14, 0x08, 0x14, 0x63}, /* 0x58 X */
    {0x03, 0x04, 0x78, 0x04, 0x03}, /* 0x59 Y */
    {0x61, 0x59, 0x49, 0x4D, 0x43}, /* 0x5A Z */
    {0x00, 0x7F, 0x41, 0x41, 0x41}, /* 0x5B [ */
    {0x02, 0x04, 0x08, 0x10, 0x20}, /* 0x5C backslash */
    {0x00, 0x41, 0x41, 0x41, 0x7F}, /* 0x5D ] */
    {0x04, 0x02, 0x01, 0x02, 0x04}, /* 0x5E ^ */
    {0x40, 0x40, 0x40, 0x40, 0x40}, /* 0x5F _ */
    {0x00, 0x03, 0x07, 0x08, 0x00}, /* 0x60 ` */
    {0x20, 0x54, 0x54, 0x78, 0x40}, /* 0x61 a */
    {0x7F, 0x28, 0x44, 0x44, 0x38}, /* 0x62 b */
    {0x38, 0x44, 0x44, 0x44, 0x28}, /* 0x63 c */
    {0x38, 0x44, 0x44, 0x28, 0x7F}, /* 0x64 d */
    {0x38, 0x54, 0x54, 0x54, 0x18}, /* 0x65 e */
    {0x00, 0x08, 0x7E, 0x09, 0x02}, /* 0x66 f */
    {0x18, 0xA4, 0xA4, 0x9C, 0x78}, /* 0x67 g */
    {0x7F, 0x08, 0x04, 0x04, 0x78}, /* 0x68 h */
    {0x00, 0x44, 0x7D, 0x40, 0x00}, /* 0x69 i */
    {0x20, 0x40, 0x40, 0x3D, 0x00}, /* 0x6A j */
    {0x7F, 0x10, 0x28, 0x44, 0x00}, /* 0x6B k */
    {0x00, 0x41, 0x7F, 0x40, 0x00}, /* 0x6C l */
    {0x7C, 0x04, 0x78, 0x04, 0x78}, /* 0x6D m */
    {0x7C, 0x08, 0x04, 0x04, 0x78}, /* 0x6E n */
    {0x38, 0x44, 0x44, 0x44, 0x38}, /* 0x6F o */
    {0xFC, 0x18, 0x24, 0x24, 0x18}, /* 0x70 p */
    {0x18, 0x24, 0x24, 0x18, 0xFC}, /* 0x71 q */
    {0x7C, 0x08, 0x04, 0x04, 0x08}, /* 0x72 r */
    {0x48, 0x54, 0x54, 0x54, 0x24}, /* 0x73 s */
    {0x04, 0x04, 0x3F, 0x44, 0x24}, /* 0x74 t */
    {0x3C, 0x40, 0x40, 0x20, 0x7C}, /* 0x75 u */
    {0x1C, 0x20, 0x40, 0x20, 0x1C}, /* 0x76 v */
    {0x3C, 0x40, 0x30, 0x40, 0x3C}, /* 0x77 w */
    {0x44, 0x28, 0x10, 0x28, 0x44}, /* 0x78 x */
    {0x4C, 0x90, 0x90, 0x90, 0x7C}, /* 0x79 y */
    {0x44, 0x64, 0x54, 0x4C, 0x44}, /* 0x7A z */
    {0x00, 0x08, 0x36, 0x41, 0x00}, /* 0x7B { */
    {0x00, 0x00, 0x77, 0x00, 0x00}, /* 0x7C | */
    {0x00, 0x41, 0x36, 0x08, 0x00}, /* 0x7D } */
    {0x02, 0x01, 0x02, 0x04, 0x02}, /* 0x7E ~ */
};

static const char s_degree[] = UI_STR_DEGREE;
static const char s_em_dash[] = UI_STR_EM_DASH;

static const uint8_t *font_glyph(unsigned char code) {
    if (code >= 0x20u && code <= 0x7Eu) {
        return s_font5x7[code - 0x20u];
    }
    static const uint8_t degree[5] = {0x06, 0x09, 0x09, 0x06, 0x00};
    static const uint8_t em_dash[5] = {0x18, 0x18, 0x18, 0x18, 0x18};
    static const uint8_t filled[5] = {0x00, 0x0E, 0x1F, 0x0E, 0x00};
    static const uint8_t hollow[5] = {0x00, 0x0E, 0x11, 0x0E, 0x00};
    switch (code) {
        case GLYPH_DEGREE: return degree;
        case GLYPH_EM_DASH: return em_dash;
        case GLYPH_DOT_FILLED: return filled;
        case GLYPH_DOT_HOLLOW: return hollow;
        default: return s_font5x7[0]; /* '?' would be better, but invisible */
    }
}

void ui_fb_clear(ui_framebuffer_t *fb) { memset(fb, 0, sizeof(*fb)); }

void ui_fb_set_pixel(ui_framebuffer_t *fb, int x, int y, bool on) {
    if (x < 0 || y < 0 || x >= (int)UI_FB_WIDTH || y >= (int)UI_FB_HEIGHT) {
        return;
    }
    uint8_t mask = (uint8_t)(1u << (y & 7));
    uint8_t *cell = &fb->page[y >> 3][x];
    if (on) {
        *cell |= mask;
    } else {
        *cell &= (uint8_t)~mask;
    }
}

bool ui_fb_get_pixel(const ui_framebuffer_t *fb, int x, int y) {
    if (x < 0 || y < 0 || x >= (int)UI_FB_WIDTH || y >= (int)UI_FB_HEIGHT) {
        return false;
    }
    return (fb->page[y >> 3][x] & (uint8_t)(1u << (y & 7))) != 0;
}

/* Decode one glyph; returns the number of source bytes consumed. */
static size_t text_glyph(const unsigned char *s, uint8_t out[5]) {
    unsigned char code = s[0];
    if (code == 0xC2u && s[1] == 0xB0u) {
        code = GLYPH_DEGREE;
        memcpy(out, font_glyph(code), 5);
        return 2;
    }
    if (code == 0xE2u && s[1] == 0x80u && s[2] == 0x94u) {
        code = GLYPH_EM_DASH;
        memcpy(out, font_glyph(code), 5);
        return 3;
    }
    if (code != GLYPH_DOT_FILLED && code != GLYPH_DOT_HOLLOW &&
        (code < 0x20u || code > 0x7Eu)) {
        code = '?';
    }
    memcpy(out, font_glyph(code), 5);
    return 1;
}

static size_t text_columns(const char *text) {
    size_t n = 0;
    const unsigned char *s = (const unsigned char *)text;
    while (*s != 0 && n < 64u) {
        size_t used = text_glyph(s, (uint8_t[5]){0});
        s += used;
        n++;
    }
    return n;
}

static void draw_glyph(ui_framebuffer_t *fb, int x, int y,
                       const uint8_t glyph[5], int scale) {
    for (int col = 0; col < 5; col++) {
        uint8_t bits = glyph[col];
        for (int row = 0; row < 8; row++) {
            if ((bits & (uint8_t)(1u << row)) == 0) {
                continue;
            }
            for (int dy = 0; dy < scale; dy++) {
                for (int dx = 0; dx < scale; dx++) {
                    ui_fb_set_pixel(fb, x + col * scale + dx,
                                    y + row * scale + dy, true);
                }
            }
        }
    }
}

static void text_px_scaled(ui_framebuffer_t *fb, int x, int y,
                           const char *text, int scale) {
    const unsigned char *s = (const unsigned char *)text;
    int cx = x;
    while (*s != 0) {
        uint8_t glyph[5];
        size_t used = text_glyph(s, glyph);
        draw_glyph(fb, cx, y, glyph, scale);
        cx += 6 * scale;
        s += used;
    }
}

void ui_fb_text_px(ui_framebuffer_t *fb, int x, int y, const char *text) {
    text_px_scaled(fb, x, y, text, 1);
}

void ui_fb_text_row(ui_framebuffer_t *fb, uint8_t row, const char *text) {
    if (row >= UI_TEXT_ROWS) {
        return;
    }
    ui_fb_text_px(fb, 0, (int)row * UI_TEXT_ROW_HEIGHT, text);
}

void ui_fb_text_center_px(ui_framebuffer_t *fb, int y, const char *text) {
    size_t cols = text_columns(text);
    int left_col = (int)(UI_TEXT_COLS - (cols > UI_TEXT_COLS ? UI_TEXT_COLS : cols)) / 2;
    ui_fb_text_px(fb, left_col * (int)UI_TEXT_ADVANCE, y, text);
}

void ui_fb_row_lr(ui_framebuffer_t *fb, uint8_t row, const char *left,
                  const char *right) {
    if (row >= UI_TEXT_ROWS) {
        return;
    }
    int y = (int)row * UI_TEXT_ROW_HEIGHT;
    ui_fb_text_px(fb, 0, y, left);
    size_t cols = text_columns(right);
    int left_col = (int)(UI_TEXT_COLS - (cols > UI_TEXT_COLS ? UI_TEXT_COLS : cols));
    ui_fb_text_px(fb, left_col * (int)UI_TEXT_ADVANCE, y, right);
}

/* ---- 12x24 seven-segment numeric face (passkey) ------------------------- */

static void seg_rect(ui_framebuffer_t *fb, int x, int y, int w, int h) {
    for (int yy = y; yy < y + h; yy++) {
        for (int xx = x; xx < x + w; xx++) {
            ui_fb_set_pixel(fb, xx, yy, true);
        }
    }
}

static void digit_12x24(ui_framebuffer_t *fb, int x, int y, char digit) {
    bool a = false, b = false, c = false, d = false, e = false, f = false,
         g = false;
    switch (digit) {
        case '0': a = b = c = d = e = f = true; break;
        case '1': b = c = true; break;
        case '2': a = b = d = e = g = true; break;
        case '3': a = b = c = d = g = true; break;
        case '4': b = c = f = g = true; break;
        case '5': a = c = d = f = g = true; break;
        case '6': a = c = d = e = f = g = true; break;
        case '7': a = b = c = true; break;
        case '8': a = b = c = d = e = f = g = true; break;
        case '9': a = b = c = d = f = g = true; break;
        default: break;
    }
    /* 3 px thick segments in a 12x24 box. */
    if (a) seg_rect(fb, x + 2, y, 8, 3);
    if (g) seg_rect(fb, x + 2, y + 10, 8, 3);
    if (d) seg_rect(fb, x + 2, y + 21, 8, 3);
    if (f) seg_rect(fb, x, y + 2, 3, 9);
    if (b) seg_rect(fb, x + 9, y + 2, 3, 9);
    if (e) seg_rect(fb, x, y + 12, 3, 9);
    if (c) seg_rect(fb, x + 9, y + 12, 3, 9);
}

static int passkey_width(const char *digits) {
    int width = 0;
    for (const char *p = digits; *p != 0; p++) {
        width += (*p == ' ') ? 9 : 15;
    }
    return width > 0 ? width - 3 : 0;
}

void ui_fb_passkey(ui_framebuffer_t *fb, int y, const char *digits) {
    int width = passkey_width(digits);
    int x = ((int)UI_FB_WIDTH - width) / 2;
    if (x < 0) {
        x = 0;
    }
    for (const char *p = digits; *p != 0; p++) {
        if (*p >= '0' && *p <= '9') {
            digit_12x24(fb, x, y, *p);
        }
        x += (*p == ' ') ? 9 : 15;
    }
}

/* ---- formatting helpers ------------------------------------------------- */

static void format_temp(int16_t temp_f10, char *out, size_t out_size) {
    if (temp_f10 == INT16_MIN) {
        snprintf(out, out_size, "---");
        return;
    }
    if (temp_f10 == (int16_t)(INT16_MIN + 1)) {
        snprintf(out, out_size, "ERR");
        return;
    }
    int32_t value = temp_f10;
    const char *sign = value < 0 ? "-" : "";
    uint32_t abs_value = (uint32_t)(value < 0 ? -value : value);
    snprintf(out, out_size, "%s%lu.%lu%sF", sign,
             (unsigned long)(abs_value / 10u), (unsigned long)(abs_value % 10u),
             s_degree);
}

static void format_probe(uint8_t attached, int16_t temp_f10, char *out,
                         size_t out_size) {
    if (!attached) {
        snprintf(out, out_size, "---");
        return;
    }
    format_temp(temp_f10, out, out_size);
}

static void format_count(uint32_t count, char *out, size_t out_size) {
    char digits[16];
    snprintf(digits, sizeof(digits), "%lu", (unsigned long)count);
    size_t n = strlen(digits);
    size_t out_i = 0;
    for (size_t i = 0; i < n && out_i + 2u < out_size; i++) {
        if (i > 0 && (n - i) % 3u == 0) {
            out[out_i++] = ',';
        }
        out[out_i++] = digits[i];
    }
    out[out_i] = '\0';
}

static void format_uptime(uint32_t seconds, char *out, size_t out_size) {
    uint32_t hours = seconds / 3600u;
    uint32_t minutes = (seconds / 60u) % 60u;
    uint32_t secs = seconds % 60u;
    snprintf(out, out_size, "%lu:%02lu:%02lu", (unsigned long)hours,
             (unsigned long)minutes, (unsigned long)secs);
}

static void format_frequency(uint32_t hz, char *out, size_t out_size) {
    if (hz == 0) {
        snprintf(out, out_size, "---");
        return;
    }
    uint32_t mhz10 = hz / 100000u; /* 918500000 Hz -> 9185 */
    snprintf(out, out_size, "%lu.%lu MHz", (unsigned long)(mhz10 / 10u),
             (unsigned long)(mhz10 % 10u));
}

static void format_battery(const ui_snapshot_t *snapshot, char *out,
                           size_t out_size) {
    char volts[12];
    if (snapshot->battery_mv == 0) {
        volts[0] = '\0';
    } else {
        snprintf(volts, sizeof(volts), "%u.%02uV",
                 (unsigned)(snapshot->battery_mv / 1000u),
                 (unsigned)(snapshot->battery_mv % 1000u / 10u));
    }
    if (snapshot->battery_pct == UI_BATTERY_UNKNOWN) {
        if (volts[0] == '\0') {
            snprintf(out, out_size, "%s", s_em_dash);
        } else {
            snprintf(out, out_size, "%s  %s", volts, s_em_dash);
        }
    } else if (volts[0] == '\0') {
        snprintf(out, out_size, "%u%%", (unsigned)snapshot->battery_pct);
    } else {
        snprintf(out, out_size, "%s  %u%%", volts,
                 (unsigned)snapshot->battery_pct);
    }
}

/* ---- pages -------------------------------------------------------------- */

static void render_probes(ui_framebuffer_t *fb,
                          const ui_snapshot_t *snapshot) {
    char value[16];
    for (unsigned i = 0; i < 4u; i++) {
        char label[3] = {'P', (char)('1' + i), '\0'};
        format_probe((snapshot->attached_mask >> i) & 1u,
                     snapshot->temp_f10[i], value, sizeof(value));
        ui_fb_row_lr(fb, (uint8_t)i, label, value);
    }

    char strip[24];
    snprintf(strip, sizeof(strip), "App %c X4 %c",
             snapshot->app_connected ? GLYPH_DOT_FILLED : GLYPH_DOT_HOLLOW,
             (snapshot->x4_age_s <= UI_LIVE_TIMEOUT_S) ? GLYPH_DOT_FILLED
                                                       : GLYPH_DOT_HOLLOW);
    char right[12];
    /* Small blinking "BT" while the bridge is advertising and no phone is
     * connected, so the OLED says it is looking even on an idle page. */
    const char *bt =
        (snapshot->ble_advertising && snapshot->ble_blink_on) ? " BT" : "";
    if (snapshot->battery_pct == UI_BATTERY_UNKNOWN) {
        snprintf(right, sizeof(right), "%s%s%s", s_em_dash, bt,
                 snapshot->storage_ok ? "" : " !");
    } else {
        snprintf(right, sizeof(right), "%u%%%s%s",
                 (unsigned)snapshot->battery_pct, bt,
                 snapshot->storage_ok ? "" : " !");
    }
    ui_fb_row_lr(fb, 7, strip, right);
}

static void render_connection(ui_framebuffer_t *fb,
                              const ui_snapshot_t *snapshot) {
    char value[24];
    if (!snapshot->smoke_paired) {
        ui_fb_text_row(fb, 0, "X4    not paired");
        ui_fb_text_row(fb, 1, "Scanning 915/920 MHz");
        ui_fb_text_row(fb, 3, "Put the Smoke X4 in");
        ui_fb_text_row(fb, 4, "SYNC, then hold its");
        ui_fb_text_row(fb, 5, "button until it beeps");
        return;
    }

    ui_fb_row_lr(fb, 0, "App",
                 snapshot->app_connected ? "connected" : "ready to pair");
    snprintf(value, sizeof(value), "%.20s", snapshot->name);
    ui_fb_row_lr(fb, 1, "Name", value);
    snprintf(value, sizeof(value), "%u/%u", (unsigned)snapshot->phones_paired,
             (unsigned)(snapshot->phones_max == 0 ? UI_PHONES_MAX
                                                  : snapshot->phones_max));
    ui_fb_row_lr(fb, 2, "Phones paired", value);

    if (snapshot->x4_age_s <= UI_LIVE_TIMEOUT_S) {
        snprintf(value, sizeof(value), "paired");
    } else {
        unsigned minutes = snapshot->x4_age_s / 60u;
        if (minutes == 0) {
            minutes = 1;
        }
        snprintf(value, sizeof(value), "no data %um", minutes);
    }
    ui_fb_row_lr(fb, 4, "X4", value);

    format_frequency(snapshot->frequency_hz, value, sizeof(value));
    ui_fb_row_lr(fb, 5, "Radio", value);

    if (snapshot->x4_age_s < 100u) {
        snprintf(value, sizeof(value), "%d  last %us", (int)snapshot->rssi,
                 (unsigned)snapshot->x4_age_s);
    } else if (snapshot->x4_age_s < 3600u) {
        snprintf(value, sizeof(value), "%d  last %um", (int)snapshot->rssi,
                 (unsigned)(snapshot->x4_age_s / 60u));
    } else {
        snprintf(value, sizeof(value), "%d  last %uh", (int)snapshot->rssi,
                 (unsigned)(snapshot->x4_age_s / 3600u));
    }
    ui_fb_row_lr(fb, 6, "Signal", value);
}

static void render_billows(ui_framebuffer_t *fb,
                           const ui_snapshot_t *snapshot) {
    char value[16];
    ui_fb_row_lr(fb, 0, "BILLOWS",
                 snapshot->billows_detected ? "DETECTED" : "NOT DETECTED");

    if (snapshot->billows_target_valid) {
        format_temp(snapshot->billows_target_f10, value, sizeof(value));
    } else {
        snprintf(value, sizeof(value), "%s", s_em_dash);
    }
    ui_fb_row_lr(fb, 1, "SET", value);

    format_probe((snapshot->attached_mask >> 3) & 1u, snapshot->temp_f10[3],
                 value, sizeof(value));
    ui_fb_row_lr(fb, 2, "P4", value);

    ui_fb_text_row(fb, 5, "Set on the Smoke X4");
}

static void render_bridge(ui_framebuffer_t *fb,
                          const ui_snapshot_t *snapshot) {
    char value[24];
    snprintf(value, sizeof(value), "v%.10s", snapshot->version);
    ui_fb_row_lr(fb, 0, "BRIDGE", value);

    format_battery(snapshot, value, sizeof(value));
    ui_fb_row_lr(fb, 1, "Battery", value);

    if (snapshot->log_days_left_x10 == UI_DAYS_UNKNOWN) {
        snprintf(value, sizeof(value), "%s", s_em_dash);
    } else {
        snprintf(value, sizeof(value), "%lu.%lu days left",
                 (unsigned long)(snapshot->log_days_left_x10 / 10u),
                 (unsigned long)(snapshot->log_days_left_x10 % 10u));
    }
    ui_fb_row_lr(fb, 2, "Log", value);

    format_count(snapshot->readings_count, value, sizeof(value));
    ui_fb_row_lr(fb, 3, "Readings", value);

    format_uptime(snapshot->uptime_s, value, sizeof(value));
    ui_fb_row_lr(fb, 4, "Uptime", value);

    if (snapshot->mem_free_kb == 0 && snapshot->mem_low_kb == 0) {
        snprintf(value, sizeof(value), "%s", s_em_dash);
    } else {
        snprintf(value, sizeof(value), "%luk/%luk",
                 (unsigned long)snapshot->mem_free_kb,
                 (unsigned long)snapshot->mem_low_kb);
    }
    ui_fb_row_lr(fb, 5, "Memory", value);
}

void ui_render_page(ui_framebuffer_t *fb, ui_page_t page,
                    const ui_snapshot_t *snapshot) {
    ui_fb_clear(fb);
    switch (page) {
        case UI_PAGE_PROBES:
            render_probes(fb, snapshot);
            break;
        case UI_PAGE_CONNECTION:
            render_connection(fb, snapshot);
            break;
        case UI_PAGE_BILLOWS:
            render_billows(fb, snapshot);
            break;
        case UI_PAGE_BRIDGE:
            render_bridge(fb, snapshot);
            break;
        default:
            render_probes(fb, snapshot);
            break;
    }
}

/* ---- overlays ----------------------------------------------------------- */

static void render_passkey(ui_framebuffer_t *fb,
                           const ui_snapshot_t *snapshot) {
    char grouped[8];
    size_t n = strlen(snapshot->passkey);
    if (n >= 6u) {
        snprintf(grouped, sizeof(grouped), "%.3s %.3s", snapshot->passkey,
                 snapshot->passkey + 3);
    } else {
        snprintf(grouped, sizeof(grouped), "%s", snapshot->passkey);
    }
    ui_fb_text_center_px(fb, 0, "PAIR WITH PHONE");
    ui_fb_passkey(fb, 16, grouped);
    ui_fb_text_center_px(fb, 48, "enter this code");
    ui_fb_text_center_px(fb, 56, "on your phone");
}

static void render_power_off(ui_framebuffer_t *fb,
                             const ui_snapshot_t *snapshot) {
    char line[24];
    ui_fb_text_center_px(fb, 8, "POWER OFF");
    if (snapshot->power_countdown_s == 0) {
        ui_fb_text_center_px(fb, 24, "release to confirm");
    } else {
        snprintf(line, sizeof(line), "keep holding  %u",
                 (unsigned)snapshot->power_countdown_s);
        ui_fb_text_center_px(fb, 24, line);
    }
    ui_fb_text_center_px(fb, 48, "release to cancel");
}

static void render_storage_failure(ui_framebuffer_t *fb) {
    ui_fb_text_center_px(fb, 8, "STORAGE UNAVAILABLE");
    ui_fb_text_center_px(fb, 24, "live readings only");
    ui_fb_text_center_px(fb, 32, "this session will");
    ui_fb_text_center_px(fb, 40, "not be recorded");
}

static void render_progress(ui_framebuffer_t *fb, const char *title) {
    ui_fb_text_center_px(fb, 16, title);
    ui_fb_text_center_px(fb, 40, "do not power off");
}

static void render_boot(ui_framebuffer_t *fb,
                        const ui_snapshot_t *snapshot) {
    char version[16];
    snprintf(version, sizeof(version), "v%.10s", snapshot->version);
    ui_fb_text_center_px(fb, 8, "SMOKE X4 BRIDGE");
    ui_fb_text_center_px(fb, 16, version);
    ui_fb_text_center_px(fb, 32, "Attach antenna before");
    ui_fb_text_center_px(fb, 40, "power");
}

static void render_off(ui_framebuffer_t *fb) {
    text_px_scaled(fb, 38, 20, "OFF", 3);
}

void ui_render_overlay(ui_framebuffer_t *fb, ui_overlay_t overlay,
                       const ui_snapshot_t *snapshot) {
    ui_fb_clear(fb);
    switch (overlay) {
        case UI_OVERLAY_BOOT:
            render_boot(fb, snapshot);
            break;
        case UI_OVERLAY_STORAGE_FAILURE:
            render_storage_failure(fb);
            break;
        case UI_OVERLAY_POWER_OFF:
            render_power_off(fb, snapshot);
            break;
        case UI_OVERLAY_PASSKEY:
            render_passkey(fb, snapshot);
            break;
        case UI_OVERLAY_CLEARING_LOG:
            render_progress(fb, "CLEARING LOG.");
            break;
        case UI_OVERLAY_RESETTING:
            render_progress(fb, "RESETTING.");
            break;
        case UI_OVERLAY_OFF:
            render_off(fb);
            break;
        case UI_OVERLAY_NONE:
        default:
            break;
    }
}

ui_overlay_t ui_effective_overlay(const ui_snapshot_t *snapshot) {
    if ((snapshot->overlay_mask & UI_OVERLAY_MASK_OFF) != 0) {
        return UI_OVERLAY_OFF;
    }
    if ((snapshot->overlay_mask & UI_OVERLAY_MASK_RESETTING) != 0) {
        return UI_OVERLAY_RESETTING;
    }
    if ((snapshot->overlay_mask & UI_OVERLAY_MASK_CLEARING_LOG) != 0) {
        return UI_OVERLAY_CLEARING_LOG;
    }
    if ((snapshot->overlay_mask & UI_OVERLAY_MASK_PASSKEY) != 0) {
        return UI_OVERLAY_PASSKEY;
    }
    if ((snapshot->overlay_mask & UI_OVERLAY_MASK_POWER_OFF) != 0) {
        return UI_OVERLAY_POWER_OFF;
    }
    if ((snapshot->overlay_mask & UI_OVERLAY_MASK_STORAGE_FAILURE) != 0) {
        return UI_OVERLAY_STORAGE_FAILURE;
    }
    if ((snapshot->overlay_mask & UI_OVERLAY_MASK_BOOT) != 0) {
        return UI_OVERLAY_BOOT;
    }
    return UI_OVERLAY_NONE;
}

void ui_render(ui_framebuffer_t *fb, ui_page_t page,
               const ui_snapshot_t *snapshot) {
    ui_overlay_t overlay = ui_effective_overlay(snapshot);
    if (overlay != UI_OVERLAY_NONE) {
        ui_render_overlay(fb, overlay, snapshot);
    } else {
        ui_render_page(fb, page, snapshot);
    }
}

void ui_snapshot_init(ui_snapshot_t *snapshot) {
    memset(snapshot, 0, sizeof(*snapshot));
    for (unsigned i = 0; i < 4u; i++) {
        snapshot->temp_f10[i] = INT16_MIN;
    }
    snapshot->battery_pct = UI_BATTERY_UNKNOWN;
    snapshot->phones_max = UI_PHONES_MAX;
    snapshot->log_days_left_x10 = UI_DAYS_UNKNOWN;
    snapshot->storage_ok = true;
    snprintf(snapshot->version, sizeof(snapshot->version), "%s", UI_VERSION);
}

/* ---- host/bench text extraction ----------------------------------------- */

static const char *glyph_to_utf8(const uint8_t glyph[5]) {
    static const struct {
        uint8_t code;
        const char *text;
    } custom[] = {
        {GLYPH_DOT_FILLED, "*"},
        {GLYPH_DOT_HOLLOW, "o"},
        {GLYPH_DEGREE, UI_STR_DEGREE},
        {GLYPH_EM_DASH, UI_STR_EM_DASH},
    };
    for (size_t i = 0; i < sizeof(custom) / sizeof(custom[0]); i++) {
        if (memcmp(glyph, font_glyph(custom[i].code), 5) == 0) {
            return custom[i].text;
        }
    }
    for (unsigned code = 0x20u; code <= 0x7Eu; code++) {
        if (memcmp(glyph, s_font5x7[code - 0x20u], 5) == 0) {
            static char one[2];
            one[0] = (char)code;
            one[1] = '\0';
            return one;
        }
    }
    return "?";
}

bool ui_fb_extract_row(const ui_framebuffer_t *fb, uint8_t row, char *out,
                       size_t out_size) {
    if (row >= UI_TEXT_ROWS || out == NULL || out_size == 0) {
        return false;
    }
    size_t used = 0;
    out[0] = '\0';
    for (unsigned col = 0; col < UI_TEXT_COLS; col++) {
        uint8_t glyph[5];
        for (unsigned c = 0; c < 5u; c++) {
            uint8_t bits = 0;
            for (unsigned bit = 0; bit < 8u; bit++) {
                int x = (int)(col * UI_TEXT_ADVANCE + c);
                int y = (int)(row * UI_TEXT_ROW_HEIGHT + bit);
                if (ui_fb_get_pixel(fb, x, y)) {
                    bits |= (uint8_t)(1u << bit);
                }
            }
            glyph[c] = bits;
        }
        const char *text = glyph_to_utf8(glyph);
        size_t text_len = strlen(text);
        if (used + text_len + 1u > out_size) {
            return false;
        }
        memcpy(out + used, text, text_len);
        used += text_len;
    }
    out[used] = '\0';
    return true;
}
