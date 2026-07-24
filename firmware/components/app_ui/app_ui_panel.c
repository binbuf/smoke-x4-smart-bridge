/* app_ui_panel.c — see app_ui_panel.h for the V1.4 ordering rule this
 * file exists to make unbreakable (F11a.5).
 */
#include "app_ui_panel.h"

#include <string.h>

static const app_ui_panel_ops_t *s_ops;
static void *s_ctx;
static bool s_up;    /* bring-up completed */
static bool s_awake; /* panel is displaying (0xAF), not blanked (0xAE) */
static bool s_shown_valid;
static app_ui_state_t s_shown;
static app_ui_fb_t s_fb;
static uint32_t s_i2c_ok;
static uint32_t s_i2c_err;

/* The reference's init sequence, unchanged — it is proven on this exact
 * panel and these exact pins (V1.4 rail_on_init=OK). */
static const uint8_t k_init_seq[] = {
    0xAE,       /* display off              */
    0xD5, 0x80, /* clock divide             */
    0xA8, 0x3F, /* multiplex 64             */
    0xD3, 0x00, /* display offset           */
    0x40,       /* start line 0             */
    0x8D, 0x14, /* charge pump on           */
    0x20, 0x00, /* horizontal addressing    */
    0xA1,       /* segment remap            */
    0xC8,       /* COM scan direction       */
    0xDA, 0x12, /* COM pins                 */
    0x81, 0xCF, /* contrast                 */
    0xD9, 0xF1, /* precharge                */
    0xDB, 0x40, /* VCOM detect              */
    0xA4,       /* resume from RAM          */
    0xA6,       /* normal (not inverted)    */
};

#define SSD1306_DISPLAY_OFF 0xAE
#define SSD1306_DISPLAY_ON 0xAF
#define CTRL_CMD 0x00
#define CTRL_DATA 0x40

void app_ui_panel_init(const app_ui_panel_ops_t *ops, void *ctx) {
    s_ops = ops;
    s_ctx = ctx;
    s_up = false;
    s_awake = false;
    s_shown_valid = false;
    memset(&s_shown, 0, sizeof s_shown);
    app_ui_fb_clear(&s_fb);
    s_i2c_ok = 0;
    s_i2c_err = 0;
}

/* Every transaction goes through here, so the V3a.1 counters cannot miss
 * one. Counting the WINDOW commands and the page writes separately would
 * flatter the error rate; one call, one count. */
static int tx(const uint8_t *buf, size_t len) {
    const int err = s_ops->tx(s_ctx, buf, len);
    if (err == 0) {
        s_i2c_ok++;
    } else {
        s_i2c_err++;
    }
    return err;
}

void app_ui_panel_counts(uint32_t *ok, uint32_t *err) {
    if (ok != NULL) {
        *ok = s_i2c_ok;
    }
    if (err != NULL) {
        *err = s_i2c_err;
    }
}

void app_ui_panel_reset_counts(void) {
    s_i2c_ok = 0;
    s_i2c_err = 0;
}

static int cmds(const uint8_t *seq, size_t n) {
    /* One transaction per command keeps the stack buffer at 2 bytes and
     * matches the reference; the panel is configured once per boot, so
     * the extra transactions cost nothing that matters. */
    for (size_t i = 0; i < n; i++) {
        const uint8_t buf[2] = {CTRL_CMD, seq[i]};
        const int err = tx(buf, sizeof buf);
        if (err != 0) {
            return err;
        }
    }
    return 0;
}

static int cmd1(uint8_t c) { return cmds(&c, 1); }

int app_ui_panel_bringup(void) {
    if (s_ops == NULL) {
        return -1;
    }
    int err;

    /* 1. Rail up FIRST. Everything below depends on the pull-ups this
     *    powers; see the header. */
    if ((err = s_ops->vext_power(s_ctx, true)) != 0) {
        return err;
    }
    s_ops->delay_ms(s_ctx, APP_UI_PANEL_RAIL_SETTLE_MS);

    /* 2. Reset pulse, with the rail already up. */
    if ((err = s_ops->reset_line(s_ctx, false)) != 0) {
        return err;
    }
    s_ops->delay_ms(s_ctx, APP_UI_PANEL_RESET_LOW_MS);
    if ((err = s_ops->reset_line(s_ctx, true)) != 0) {
        return err;
    }
    s_ops->delay_ms(s_ctx, APP_UI_PANEL_RESET_SETTLE_MS);

    /* 3. Only now is it safe to create the bus. */
    if ((err = s_ops->bus_create(s_ctx)) != 0) {
        return err;
    }

    /* 4. Panel init, then leave the glass dark: M3 shows the passkey
     *    overlay and nothing else (07 §7.3 scope note). */
    if ((err = cmds(k_init_seq, sizeof k_init_seq)) != 0) {
        s_ops->bus_destroy(s_ctx);
        return err;
    }
    s_up = true;
    s_awake = false;
    s_shown_valid = false;
    return 0;
}

/* Window the whole panel, then stream the buffer. Horizontal addressing
 * auto-increments across transactions, so 8 x 129-byte writes need no
 * 1 KB staging buffer. */
static int flush(const app_ui_fb_t *fb) {
    static const uint8_t window[] = {
        0x21, 0x00, APP_UI_WIDTH - 1, /* column range */
        0x22, 0x00, APP_UI_PAGES - 1, /* page range   */
    };
    int err = cmds(window, sizeof window);
    if (err != 0) {
        return err;
    }
    uint8_t buf[1 + APP_UI_WIDTH];
    buf[0] = CTRL_DATA;
    for (int page = 0; page < APP_UI_PAGES; page++) {
        memcpy(buf + 1, fb->px + (size_t)page * APP_UI_WIDTH, APP_UI_WIDTH);
        if ((err = tx(buf, sizeof buf)) != 0) {
            return err;
        }
    }
    return 0;
}

void app_ui_panel_set_awake(bool on) {
    if (!s_up || s_awake == on) {
        return;
    }
    if (cmd1(on ? SSD1306_DISPLAY_ON : SSD1306_DISPLAY_OFF) != 0) {
        return;
    }
    s_awake = on;
    if (on) {
        /* Whatever was on the glass before the sleep is gone as far as we
         * are concerned; force a redraw rather than trust it. */
        s_shown_valid = false;
    }
}

bool app_ui_panel_render(const app_ui_state_t *st) {
    if (!s_up || st == NULL) {
        return false;
    }
    if (!s_awake) {
        /* Asleep: ZERO transfers. This is the ~10 mA (07 §7.1, 01 §1.6),
         * and it only exists if the driver actually stops talking. */
        return false;
    }
    if (s_shown_valid && memcmp(&s_shown, st, sizeof *st) == 0) {
        return false; /* the glass already says this */
    }

    app_ui_render(st, &s_fb);
    if (flush(&s_fb) != 0) {
        s_shown_valid = false; /* unknown glass state — redraw next time */
        return false;
    }
    s_shown = *st;
    s_shown_valid = true;
    return true;
}

bool app_ui_panel_is_awake(void) { return s_awake; }
