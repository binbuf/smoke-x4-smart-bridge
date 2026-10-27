/*
 * ui_render.h - pure-C page and overlay renderer for the 128x64 SSD1306
 * (design 07 sections 7.1-7.3 and 7.6, design 13 section 13.4).
 *
 * A renderer is a pure function of `ui_snapshot_t`: it never touches hardware,
 * the clock or NVS. The firmware builds one snapshot and copies the resulting
 * 1 KB page-ordered framebuffer to the panel. Host tests exercise the same
 * functions and compare the framebuffer bytes against committed goldens.
 */
#ifndef SX4_UI_RENDER_H
#define SX4_UI_RENDER_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#define UI_FB_WIDTH 128u
#define UI_FB_HEIGHT 64u
#define UI_FB_PAGES 8u
#define UI_FB_SIZE (UI_FB_WIDTH * UI_FB_PAGES) /* 1024 bytes */

/* 5x7 body face in a 6x8 cell: 21 columns x 8 rows. */
#define UI_TEXT_COLS 21u
#define UI_TEXT_ROWS 8u
#define UI_TEXT_ADVANCE 6u
#define UI_TEXT_ROW_HEIGHT 8u

#define UI_VERSION "0.1.0"
#define UI_BATTERY_UNKNOWN 255u
#define UI_DAYS_UNKNOWN 0xFFFFu
#define UI_PHONES_MAX 4u
#define UI_LIVE_TIMEOUT_S 90u

/* UTF-8 strings for the two non-ASCII glyphs the OLED copy uses. */
#define UI_STR_DEGREE "\xC2\xB0"
#define UI_STR_EM_DASH "\xE2\x80\x94"

/*
 * Page-ordered framebuffer: page 0 holds display rows 0-7, page 1 rows 8-15,
 * and so on. Byte N of a page is column N. This is exactly the SSD1306 GDDRAM
 * order, so a flush is eight contiguous 128-byte writes.
 */
typedef struct {
    uint8_t page[UI_FB_PAGES][UI_FB_WIDTH];
} ui_framebuffer_t;

typedef enum {
    UI_PAGE_PROBES = 0,
    UI_PAGE_CONNECTION,
    UI_PAGE_BILLOWS,
    UI_PAGE_BRIDGE,
    UI_PAGE_COUNT
} ui_page_t;

/* Overlay identifiers, lowest priority first. */
typedef enum {
    UI_OVERLAY_NONE = 0,
    UI_OVERLAY_BOOT,
    UI_OVERLAY_STORAGE_FAILURE,
    UI_OVERLAY_POWER_OFF,
    UI_OVERLAY_PASSKEY,
    UI_OVERLAY_CLEARING_LOG,
    UI_OVERLAY_RESETTING,
    UI_OVERLAY_OFF,
} ui_overlay_t;

#define UI_OVERLAY_MASK_BOOT (1u << 0)
#define UI_OVERLAY_MASK_STORAGE_FAILURE (1u << 1)
#define UI_OVERLAY_MASK_POWER_OFF (1u << 2)
#define UI_OVERLAY_MASK_PASSKEY (1u << 3)
#define UI_OVERLAY_MASK_CLEARING_LOG (1u << 4)
#define UI_OVERLAY_MASK_RESETTING (1u << 5)
#define UI_OVERLAY_MASK_OFF (1u << 6)

/*
 * Everything a page may display. The firmware fills this from bridge_state,
 * bridge_config, sample_log and (later) the BLE service; host tests fill it
 * directly. Unknown values have explicit sentinels instead of zero:
 *   - a detached probe is attached_mask bit 0 and SX4_TEMP_DETACHED;
 *   - an attached but invalid probe is SX4_TEMP_INVALID;
 *   - unknown battery percent is UI_BATTERY_UNKNOWN;
 *   - unknown values are never rendered as 0.0 or 0%.
 */
typedef struct {
    uint32_t seq;

    /* Probes page. */
    uint8_t attached_mask; /* bit 0..3 */
    int16_t temp_f10[4];   /* canonical Fahrenheit tenths, or a sentinel */
    bool app_connected;    /* false = advertising */
    bool storage_ok;
    uint8_t battery_pct;   /* UI_BATTERY_UNKNOWN when unknown */
    uint16_t battery_mv;

    /* Connection page. */
    char name[24];
    uint8_t phones_paired;
    uint8_t phones_max;
    bool smoke_paired;
    uint16_t x4_age_s;
    int8_t rssi;
    uint32_t frequency_hz;

    /* Billows page. */
    bool billows_detected;
    bool billows_target_valid;
    int16_t billows_target_f10;

    /* Bridge page. */
    char version[12];
    uint16_t log_days_left_x10; /* 124 = 12.4 days; UI_DAYS_UNKNOWN */
    uint32_t readings_count;
    uint32_t uptime_s;
    uint32_t mem_free_kb;
    uint32_t mem_low_kb;

    /* Overlays. */
    uint8_t overlay_mask;      /* UI_OVERLAY_* bits */
    char passkey[7];           /* six ASCII digits, NUL terminated */
    uint8_t power_countdown_s; /* > 0: keep holding; 0: release to confirm */
} ui_snapshot_t;

/* Fill every field with its "unknown / absent" value. */
void ui_snapshot_init(ui_snapshot_t *snapshot);

/* Highest-priority active overlay; UI_OVERLAY_NONE when none is set. */
ui_overlay_t ui_effective_overlay(const ui_snapshot_t *snapshot);

/* Render the effective overlay (or the requested page when none is active). */
void ui_render(ui_framebuffer_t *fb, ui_page_t page,
               const ui_snapshot_t *snapshot);
void ui_render_page(ui_framebuffer_t *fb, ui_page_t page,
                    const ui_snapshot_t *snapshot);
void ui_render_overlay(ui_framebuffer_t *fb, ui_overlay_t overlay,
                       const ui_snapshot_t *snapshot);

/* Primitive drawing helpers (also used by the host tests/tooling). */
void ui_fb_clear(ui_framebuffer_t *fb);
void ui_fb_set_pixel(ui_framebuffer_t *fb, int x, int y, bool on);
bool ui_fb_get_pixel(const ui_framebuffer_t *fb, int x, int y);
void ui_fb_text_row(ui_framebuffer_t *fb, uint8_t row, const char *text);
void ui_fb_text_px(ui_framebuffer_t *fb, int x, int y, const char *text);
void ui_fb_text_center_px(ui_framebuffer_t *fb, int y, const char *text);
void ui_fb_row_lr(ui_framebuffer_t *fb, uint8_t row, const char *left,
                  const char *right);
/* Six-digit passkey in the 12x24 numeric face, centered on `y`. */
void ui_fb_passkey(ui_framebuffer_t *fb, int y, const char *digits);

/*
 * Test/bench seam: decode one 6x8 text row back to UTF-8. Unknown glyphs become
 * '?'. The dot glyphs decode as '*' (filled) and 'o' (hollow). The returned
 * string always represents all 21 cells, including trailing spaces.
 */
bool ui_fb_extract_row(const ui_framebuffer_t *fb, uint8_t row, char *out,
                       size_t out_size);

#ifdef __cplusplus
}
#endif

#endif /* SX4_UI_RENDER_H */
