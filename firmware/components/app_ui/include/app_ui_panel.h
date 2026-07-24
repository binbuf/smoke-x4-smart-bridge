/* app_ui_panel — SSD1306 sequencing over an injected I²C seam (F11a.5;
 * design 07 §7.1, 01 §1.2, hardware-verified V1.4).
 *
 * The thin half of app_ui, but thin is not the same as untested: the
 * bring-up ORDER is a board-found fact that cost a bench sitting, so it
 * lives here as code with a host test around it rather than as a comment
 * someone has to remember.
 *
 * THE V1.4 FACT, BAKED IN: the OLED's I²C pull-ups hang off the switched
 * Vext rail. Creating the i2c_master bus while the rail is down runs the
 * controller against floating lines and can leave it wedged bus-busy —
 * after which the rail-on probe fails for a reason that has nothing to do
 * with the rail. The order is therefore Vext on → settle → reset pulse →
 * *then* create the bus → init.
 *
 * That order is not merely documented, it is UNEXPRESSIBLE otherwise:
 * `app_ui_panel_bringup()` is the only entry point that touches the rail
 * or the bus, and it runs the whole sequence internally. There is no
 * public way to call bus_create first, because there is no public
 * bus_create.
 */
#ifndef APP_UI_PANEL_H
#define APP_UI_PANEL_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#include "app_ui_core.h"

#ifdef __cplusplus
extern "C" {
#endif

/* SSD1306 on the Heltec V3 (01 §1.2): SDA 17, SCL 18, RST 21, Vext 36. */
#define APP_UI_PANEL_ADDR 0x3C
#define APP_UI_PANEL_I2C_HZ 400000

/* Settle times, from bench.c's proven sequence. */
#define APP_UI_PANEL_RAIL_SETTLE_MS 100
#define APP_UI_PANEL_RESET_LOW_MS 10
#define APP_UI_PANEL_RESET_SETTLE_MS 50

/* All ops return 0 on success. None may be NULL. */
typedef struct {
    /* `on` = rail powered. The glue is responsible for knowing that means
     * driving GPIO36 LOW (V1.4) — the core states intent, not polarity. */
    int (*vext_power)(void *ctx, bool on);
    /* Panel reset line; `high` = released. */
    int (*reset_line)(void *ctx, bool high);
    /* Create the I²C master bus and attach the panel at 400 kHz. Called
     * by bringup only, and only after the rail is up. */
    int (*bus_create)(void *ctx);
    /* Tear the bus down (used when re-running bring-up after a failure). */
    int (*bus_destroy)(void *ctx);
    /* One I²C transaction to the panel. */
    int (*tx)(void *ctx, const uint8_t *buf, size_t len);
    void (*delay_ms)(void *ctx, uint32_t ms);
} app_ui_panel_ops_t;

/* Binds the seam. Safe to call again (re-init resets internal state), so a
 * host test can drive many scenarios in one process. */
void app_ui_panel_init(const app_ui_panel_ops_t *ops, void *ctx);

/* Rail → settle → reset → bus → SSD1306 init → blank panel. Returns 0 on
 * success; on failure the rail is left powered and the caller may retry. */
int app_ui_panel_bringup(void);

/* Renders `st` and pushes it to the panel ONLY if `st` differs from what
 * is already on the glass. Renderers are pure functions of the snapshot
 * (07 §7.6), so equal state means identical pixels — which is why one
 * memcmp replaces the reference's unconditional 1 Hz redraw and its I²C
 * traffic.
 *
 * Returns true when bytes actually went to the panel. */
bool app_ui_panel_render(const app_ui_state_t *st);

/* F11b.9 — the sleep policy's hands. `on=false` sends 0xAE and stops all
 * traffic; a sleeping panel must do ZERO I²C transfers, because "the
 * display is off" and "the driver stopped talking to it" are different
 * claims and only the second one saves the ~10 mA. */
void app_ui_panel_set_awake(bool on);
bool app_ui_panel_is_awake(void);

/* F11b.11 — V3a.1's deferred row, made countable. M3 could not measure
 * the OLED's I²C error rate because the panel was dark except while a
 * passkey was showing; F11b makes it always-on and this counts what
 * happens. Surfaced on the System page and in GET /api/v1/status. */
void app_ui_panel_counts(uint32_t *ok, uint32_t *err);
void app_ui_panel_reset_counts(void);

#ifdef __cplusplus
}
#endif

#endif /* APP_UI_PANEL_H */
