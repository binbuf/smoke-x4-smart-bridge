/* app_ui_core — the framebuffer, fonts, pages, and overlays (F11a.1,
 * F11a.3, F11a.4, F11b.1–F11b.6; design 07).
 *
 * Pure C11: no ESP-IDF headers, no I²C, no globals that a test cannot
 * reach. The framebuffer is passed in, renderers are pure functions of a
 * snapshot struct, and every pixel decision is assertable on the host and
 * reviewable as a PNG (F11a.2). The thin panel half lives in
 * app_ui_panel.h; the gesture machine in app_ui_input.h; the page and
 * action model in app_ui_model.h; the ESP-IDF glue in app_ui.h.
 *
 * M5 COMPLETES F11. M3 shipped only what F10 needed to bond — the buffer,
 * the two fonts, and the passkey overlay — and left row 7 blank with a
 * recorded promise to fill it here. F11b keeps that promise: the status
 * strip is on every page and every overlay, the five pages exist, the
 * sparkline is drawn from the RAM ring, and the panel sleeps.
 *
 * 21 COLUMNS IS NOT MANY. `NETWORK   connecting` is 20 of them. Every
 * renderer below truncates deliberately and its golden pins the
 * truncation, because the alternative is discovering it on a panel in a
 * dark yard — which is what A15.5-1 already cost the app side once.
 */
#ifndef APP_UI_CORE_H
#define APP_UI_CORE_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#include "record_gen.h" /* TEMP_/SOC_ sentinels, alarm + role enums */

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

/* Row 7 is reserved on EVERY page and overlay for the status strip. */
#define APP_UI_STRIP_ROW 7

/* Large font: 12x24, digits + space + degree (07 §7.1). */
#define APP_UI_LARGE_W 12
#define APP_UI_LARGE_H 24
#define APP_UI_LARGE_GLYPHS 12
#define APP_UI_LARGE_BYTES (APP_UI_LARGE_W * (APP_UI_LARGE_H / 8)) /* 36 */

typedef struct {
    uint8_t px[APP_UI_FB_BYTES];
} app_ui_fb_t;

/* ── Primitives (F11a.1, F11b.2) ──────────────────────────────────────
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

/* F11b.2 — the two primitives 07 §7.6 names and F11a did not build.
 *
 * The sparkline auto-scales to its own min/max, draws a flat line rather
 * than dividing by zero when they are equal, SKIPS detached samples
 * instead of plotting them at the bottom of the range, and buckets when
 * there are more samples than pixels rather than dropping the tail. */
void app_ui_draw_sparkline(app_ui_fb_t *fb, int x, int y, int w, int h,
                           const int16_t *vals, int n);
void app_ui_draw_progress(app_ui_fb_t *fb, int x, int y, int w, int h,
                          int pct);

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
 * Renderers are pure functions of this struct, and it is POD and
 * COMPARABLE on purpose: app_ui_panel_render()'s "push only if changed"
 * contract is a memcmp, and the whole render-only-when-dirty policy rests
 * on equal state meaning identical pixels. Producers must memset it
 * before filling, so padding bytes never make two equal states differ. */

#define APP_UI_PASSKEY_DIGITS 6
#define APP_UI_NAME_LEN 16
#define APP_UI_SPARK_MAX 64

typedef enum {
    APP_UI_PAGE_PROBES = 0, /* the default (07 §7.2) */
    APP_UI_PAGE_TRENDS,
    APP_UI_PAGE_NETWORK,
    APP_UI_PAGE_RADIO,
    APP_UI_PAGE_SYSTEM,
    APP_UI_PAGE_COUNT,
} app_ui_page_t;

typedef enum {
    APP_UI_OVERLAY_NONE = 0,
    APP_UI_OVERLAY_SPLASH,  /* boot + recovery window (03 §3.4.1) */
    APP_UI_OVERLAY_PASSKEY, /* F10.5 bonding */
    APP_UI_OVERLAY_ALARM,   /* inverted video, reads across a dark yard */
    APP_UI_OVERLAY_CONFIRM, /* every hold action, release-to-cancel */
    APP_UI_OVERLAY_OTA,     /* rendered here; driven by F14 (M6) */
} app_ui_overlay_t;

typedef enum {
    APP_UI_NET_OFF = 0,
    APP_UI_NET_AP,
    APP_UI_NET_STA,
} app_ui_net_mode_t;

typedef enum {
    APP_UI_NET_IDLE = 0,
    APP_UI_NET_CONNECTING,
    APP_UI_NET_UP,
    APP_UI_NET_FAILED,
} app_ui_net_state_t;

typedef struct {
    char name[APP_UI_NAME_LEN + 1];
    /* Canonical tenths °F. BRIDGE_TEMP_DETACHED renders `---`, NEVER a
     * temperature — 07 §7.2 is explicit that the reference's 0.0 is a
     * real trap on a graph and a real confusion on a screen. */
    int16_t temp_f10;
    int32_t target_f10; /* 0 = unset */
    int16_t band_lo_f10;
    int16_t band_hi_f10;
    bool has_band;
    uint8_t role; /* bridge_probe_role_t */
    bool slope_valid;
    int16_t slope_f10_per_hr;
} app_ui_probe_t;

typedef struct {
    uint8_t page;    /* app_ui_page_t */
    uint8_t overlay; /* app_ui_overlay_t */
    bool celsius;    /* display only; storage stays canonical (04 §4.2) */

    /* ── the status strip (07 §7.1), on every page and overlay ── */
    bool base_ok;     /* a LoRa packet within the last 60 s */
    uint8_t net_mode; /* app_ui_net_mode_t */
    bool ap_client;   /* renders `ap*` */
    /* The APP-CONFIRMED cook clock (app_ui_cook.h), and the only source of
     * an elapsed time anywhere on this device. False renders BLANK — not
     * `--:--`, which would claim there is a cook whose age is unknown. The
     * bridge never infers a cook from an attached probe: it records
     * continuously and lets the app say what a cook is. */
    bool cook_clock_set;
    uint32_t cook_elapsed_s;
    uint8_t soc_pct; /* BRIDGE_SOC_UNKNOWN renders as `--%` */
    bool charging;   /* renders `USB` */
    bool alarm_unacked;

    /* ── page 1: probes ── */
    app_ui_probe_t probe[4];
    uint8_t num_probes;

    /* ── page 2: trends ──
     * Every probe's current reading beside how fast it is moving, over the
     * ring's rolling 10-minute window. There is nothing session-shaped here
     * on purpose: no id, no name, no sample count, no ETA. */
    /* The pit over the RAM ring's 2 h window, oldest → newest.
     * BRIDGE_TEMP_DETACHED marks a hole. No flash reads on this path. */
    int16_t spark[APP_UI_SPARK_MAX];
    uint8_t spark_n;

    /* ── page 3: network ── */
    char ssid[33];
    char psk[11];
    char ip[16];
    char host[24];
    int8_t wifi_rssi;
    uint8_t net_state; /* app_ui_net_state_t */
    uint8_t ap_clients;
    uint8_t retry_attempt;
    uint16_t retry_in_s;
    uint8_t ble_conns;
    uint8_t ble_bonds;

    /* ── page 4: radio ── */
    bool paired;
    char device_id[9];
    uint32_t frequency_hz;
    int8_t lora_rssi;
    int8_t lora_snr;
    uint32_t last_packet_s;
    uint32_t packets_ok;
    uint32_t packets_bad;
    uint16_t interval_s10; /* mean inter-packet interval, tenths of a s */

    /* ── page 5: system ── */
    char fw[12];
    uint32_t uptime_s;
    uint32_t storage_used_b;
    uint32_t storage_total_b;
    /* Recorded log files on flash. A STORAGE number, rendered as `files`
     * rather than `cooks`: the store keeps writing whether or not anyone
     * ever calls a stretch of it a cook, and how it divides into cooks is
     * the app's answer to give. */
    uint16_t stored_files;
    uint32_t heap_free;
    uint32_t heap_min;
    uint16_t mv;
    bool saver;
    /* V3a.1's deferred row, finally countable: the panel's own I²C
     * traffic. M3 could not measure it because the glass was dark. */
    uint32_t i2c_ok;
    uint32_t i2c_err;

    /* ── overlays ── */
    /* Six ASCII digits, NUL-terminated. Zero-padded by the producer:
     * a passkey of 418302 is "418302", and of 302 is "000302". */
    char passkey[APP_UI_PASSKEY_DIGITS + 1];
    uint8_t alarm_rule; /* bridge_alarm_rule_t */
    uint8_t alarm_probe;
    uint8_t alarm_severity;
    int16_t alarm_value_f10;
    char confirm_text[22];
    uint8_t confirm_count; /* 3 → 2 → 1 */
    uint8_t ota_pct;
    char ota_from[12];
    char ota_to[12];
} app_ui_state_t;

/* ── The status strip (F11b.1; 07 §7.1) ─────────────────────────────
 * `●sta  04:12  71%  ⚠` — drawn into row 7 of an already-rendered
 * buffer, so every page and every overlay gets it from one call. */
void app_ui_render_strip(const app_ui_state_t *st, app_ui_fb_t *fb);

/* ── Pages (F11b.3–F11b.5; 07 §7.2) ─────────────────────────────────
 * Each clears `fb`, draws rows 0..6, and calls the strip. */
void app_ui_render_page_probes(const app_ui_state_t *st, app_ui_fb_t *fb);
/* Current temperature beside recent rate of change, per probe, plus the 2 h
 * pit sparkline. This replaced the COOK page: that one led with a session id,
 * a name and `Elapsed 04:12:30`, all three of which the bridge was inferring
 * rather than knowing. */
void app_ui_render_page_trends(const app_ui_state_t *st, app_ui_fb_t *fb);
void app_ui_render_page_network(const app_ui_state_t *st, app_ui_fb_t *fb);
void app_ui_render_page_radio(const app_ui_state_t *st, app_ui_fb_t *fb);
void app_ui_render_page_system(const app_ui_state_t *st, app_ui_fb_t *fb);

/* ── Overlays (F11a.4, F11b.6; 07 §7.3) ─────────────────────────────
 * Transient screens that pre-empt whatever page is showing. */

/* The §7.3 PAIR WITH PHONE overlay. Touches nothing outside the buffer
 * and reads nothing outside `st`.
 *
 * The M3 golden for this changed in M5, and that is the promise F11a
 * recorded rather than drift: row 7 was blank because the strip's sources
 * (battery SoC, the alarm glyph) were M5 components. They exist now. */
void app_ui_render_overlay_passkey(const app_ui_state_t *st, app_ui_fb_t *fb);
/* Inverted video, because it has to read across a dark yard. Persists
 * until acknowledged or 60 s — after which the PAGE reverts but the LED
 * keeps signalling and the alarm stays unacknowledged in the API.
 * Silencing the screen is not the same as dealing with it. */
void app_ui_render_overlay_alarm(const app_ui_state_t *st, app_ui_fb_t *fb);
/* Every destructive or disruptive hold action, with `release to cancel`
 * on the glass — hold actions commit on RELEASE, not on threshold. */
void app_ui_render_overlay_confirm(const app_ui_state_t *st, app_ui_fb_t *fb);
/* Boot splash: version, the 3 s recovery window, and the antenna warning
 * (01 §1.5 — transmitting into an open port can destroy the PA). */
void app_ui_render_overlay_splash(const app_ui_state_t *st, app_ui_fb_t *fb);
void app_ui_render_overlay_ota(const app_ui_state_t *st, app_ui_fb_t *fb);

/* Dispatches to the right overlay or page. The single entry point the
 * panel layer calls, so "what is on the glass" has one answer. */
void app_ui_render(const app_ui_state_t *st, app_ui_fb_t *fb);

/* Formats a canonical tenths-°F value for display, honouring `celsius`.
 * A detached probe renders "---" and NEVER a number. Exposed because the
 * pages and the tests must agree on it exactly. */
void app_ui_format_temp(int16_t f10, bool celsius, bool with_unit, char *out,
                        size_t cap);
/* `04:12` / `--:--` (07 §7.1), and `14:15:30` for uptime. */
void app_ui_format_hhmm(uint32_t seconds, bool valid, char *out, size_t cap);
void app_ui_format_hhmmss(uint32_t seconds, char *out, size_t cap);

#ifdef __cplusplus
}
#endif

#endif /* APP_UI_CORE_H */
