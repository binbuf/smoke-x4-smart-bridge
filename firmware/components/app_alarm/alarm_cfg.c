/* alarm_cfg.c — the versioned rule-configuration codec (F13.1;
 * design 09 §9.2, 03 §3.6).
 *
 * The layout is APPEND-ONLY and version-tagged, and decode keeps the
 * prefix it understands rather than rejecting the blob. The failure this
 * prevents is specific: a firmware downgrade meeting a newer blob and
 * silently disabling every alarm on the device, which the user would
 * discover at 3 a.m. by not being woken.
 *
 *   off  size  field
 *   ---  ----  --------------------------------------------------------
 *     0     1  version
 *     1     2  enabled_mask
 *     3     2  pit_band_f10
 *     5     2  pit_band_sustain_s
 *     7     2  pit_crash_below_f10
 *     9     2  pit_crash_slope_f10_per_hr
 *    11     2  pit_crash_sustain_s
 *    13     2  base_lost_s
 *    15     1  batt_warn_pct
 *    16     1  batt_crit_pct
 *    17     1  storage_free_pct
 *    18     2  target_rearm_f10
 *    20     2  band_rearm_s
 *    22     2  lid_grace_s
 *    ---  ----
 *          24  of the 64 B blob
 */
#include "app_alarm_core.h"

#include <string.h>

#define ALL_NINE ((uint16_t)((1u << APP_ALARM_RULE_COUNT) - 1u))

void app_alarm_cfg_defaults(app_alarm_cfg_t *out) {
    if (out == NULL) {
        return;
    }
    /* Every default below is 09 §9.2's table, transcribed once. */
    out->enabled_mask = ALL_NINE;
    out->pit_band_f10 = 250;                /* ±25 °F */
    out->pit_band_sustain_s = 600;          /* 10 min */
    out->pit_crash_below_f10 = 500;         /* 50 °F below target */
    out->pit_crash_slope_f10_per_hr = -100; /* −10 °F/hr */
    out->pit_crash_sustain_s = 600;         /* 10 min */
    out->base_lost_s = 600;                 /* 10 min */
    out->batt_warn_pct = 15;
    out->batt_crit_pct = 5;
    out->storage_free_pct = 2;
    out->target_rearm_f10 = 30; /* 3 °F */
    out->band_rearm_s = 300;    /* 5 min */
    out->lid_grace_s = 900;     /* 15 min */
}

bool app_alarm_cfg_rule_enabled(const app_alarm_cfg_t *cfg, uint8_t rule) {
    if (cfg == NULL || rule >= APP_ALARM_RULE_COUNT) {
        return false;
    }
    return (cfg->enabled_mask & (uint16_t)(1u << rule)) != 0;
}

static void put_u16(uint8_t *p, uint16_t v) {
    p[0] = (uint8_t)(v & 0xFFu);
    p[1] = (uint8_t)(v >> 8);
}

static uint16_t get_u16(const uint8_t *p) {
    return (uint16_t)((uint16_t)p[0] | ((uint16_t)p[1] << 8));
}

#define CFG_BYTES 24

int app_alarm_cfg_encode(const app_alarm_cfg_t *cfg, uint8_t *buf,
                         size_t cap) {
    if (cfg == NULL || buf == NULL || cap < CFG_BYTES) {
        return -1;
    }
    buf[0] = APP_ALARM_CFG_VERSION;
    put_u16(&buf[1], cfg->enabled_mask);
    put_u16(&buf[3], (uint16_t)cfg->pit_band_f10);
    put_u16(&buf[5], cfg->pit_band_sustain_s);
    put_u16(&buf[7], (uint16_t)cfg->pit_crash_below_f10);
    put_u16(&buf[9], (uint16_t)cfg->pit_crash_slope_f10_per_hr);
    put_u16(&buf[11], cfg->pit_crash_sustain_s);
    put_u16(&buf[13], cfg->base_lost_s);
    buf[15] = cfg->batt_warn_pct;
    buf[16] = cfg->batt_crit_pct;
    buf[17] = cfg->storage_free_pct;
    put_u16(&buf[18], (uint16_t)cfg->target_rearm_f10);
    put_u16(&buf[20], cfg->band_rearm_s);
    put_u16(&buf[22], cfg->lid_grace_s);
    return CFG_BYTES;
}

int app_alarm_cfg_decode(const void *buf, size_t len, app_alarm_cfg_t *out) {
    if (out == NULL) {
        return 0;
    }
    app_alarm_cfg_defaults(out);
    if (buf == NULL || len < 1) {
        return 0;
    }
    const uint8_t *p = buf;
    /* The version byte is informational on the way in: an unknown FUTURE
     * version still shares this prefix, because the layout only ever
     * grows. Rejecting it would be the silent-disable failure above. */
    size_t off = 1;

/* Each field is read only if the whole field is present. A blob truncated
 * mid-field keeps the default rather than reading half of one. */
#define TAKE(n) (len >= off + (n) ? ((off += (n)), true) : false)
    if (TAKE(2)) {
        out->enabled_mask = get_u16(&p[off - 2]);
    }
    if (TAKE(2)) {
        out->pit_band_f10 = (int16_t)get_u16(&p[off - 2]);
    }
    if (TAKE(2)) {
        out->pit_band_sustain_s = get_u16(&p[off - 2]);
    }
    if (TAKE(2)) {
        out->pit_crash_below_f10 = (int16_t)get_u16(&p[off - 2]);
    }
    if (TAKE(2)) {
        out->pit_crash_slope_f10_per_hr = (int16_t)get_u16(&p[off - 2]);
    }
    if (TAKE(2)) {
        out->pit_crash_sustain_s = get_u16(&p[off - 2]);
    }
    if (TAKE(2)) {
        out->base_lost_s = get_u16(&p[off - 2]);
    }
    if (TAKE(1)) {
        out->batt_warn_pct = p[off - 1];
    }
    if (TAKE(1)) {
        out->batt_crit_pct = p[off - 1];
    }
    if (TAKE(1)) {
        out->storage_free_pct = p[off - 1];
    }
    if (TAKE(2)) {
        out->target_rearm_f10 = (int16_t)get_u16(&p[off - 2]);
    }
    if (TAKE(2)) {
        out->band_rearm_s = get_u16(&p[off - 2]);
    }
    if (TAKE(2)) {
        out->lid_grace_s = get_u16(&p[off - 2]);
    }
#undef TAKE
    return (int)off;
}
