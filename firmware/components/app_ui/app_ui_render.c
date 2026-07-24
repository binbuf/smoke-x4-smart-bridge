/* app_ui_render.c — the status strip, the five pages, and the overlays
 * (F11a.4, F11b.1, F11b.3–F11b.6; design 07 §7.1–§7.3).
 *
 * Pure functions of the snapshot struct (07 §7.6). No clock, no I²C, no
 * event bus: given the same app_ui_state_t they produce the same 1024
 * bytes, which is what lets CI review them as pictures and the panel layer
 * skip an I²C flush with a memcmp.
 *
 * The recurring constraint is 21 columns. Where a field can overflow it,
 * the renderer truncates on purpose and the golden pins where.
 */
#include "app_ui_core.h"

#include <stdio.h>
#include <string.h>

static bool attached(int16_t f10) {
    return f10 != BRIDGE_TEMP_DETACHED && f10 != BRIDGE_TEMP_INVALID;
}

/* ── formatting ─────────────────────────────────────────────────────── */

void app_ui_format_temp(int16_t f10, bool celsius, bool with_unit, char *out,
                        size_t cap) {
    if (out == NULL || cap == 0) {
        return;
    }
    if (!attached(f10)) {
        /* NEVER a number for a detached probe. 07 §7.2 calls the
         * reference's 0.0 a real trap; this is where it is refused. */
        snprintf(out, cap, "---");
        return;
    }
    int32_t v = f10;
    if (celsius) {
        /* Canonical storage stays °F (04 §4.2); this is display only. */
        v = ((int32_t)f10 - 320) * 5 / 9;
    }
    const int32_t whole = v / 10;
    const int32_t frac = (v < 0 ? -v : v) % 10;
    if (with_unit) {
        snprintf(out, cap, "%ld.%ld\xC2\xB0%c", (long)whole, (long)frac,
                 celsius ? 'C' : 'F');
    } else {
        snprintf(out, cap, "%ld.%ld", (long)whole, (long)frac);
    }
}

/* Whole degrees, for the places where a decimal point costs a column that
 * is not there (the probe rows, the alarm band). */
static void format_temp_whole(int16_t f10, bool celsius, char *out,
                              size_t cap) {
    if (!attached(f10)) {
        snprintf(out, cap, "---");
        return;
    }
    int32_t v = f10;
    if (celsius) {
        v = ((int32_t)f10 - 320) * 5 / 9;
    }
    snprintf(out, cap, "%ld", (long)((v + (v < 0 ? -5 : 5)) / 10));
}

void app_ui_format_hhmm(uint32_t seconds, bool valid, char *out, size_t cap) {
    if (out == NULL || cap == 0) {
        return;
    }
    if (!valid) {
        snprintf(out, cap, "--:--");
        return;
    }
    snprintf(out, cap, "%02u:%02u", (unsigned)(seconds / 3600u),
             (unsigned)((seconds / 60u) % 60u));
}

void app_ui_format_hhmmss(uint32_t seconds, char *out, size_t cap) {
    snprintf(out, cap, "%02u:%02u:%02u", (unsigned)(seconds / 3600u),
             (unsigned)((seconds / 60u) % 60u), (unsigned)(seconds % 60u));
}

/* ── the status strip (F11b.1; 07 §7.1) ─────────────────────────────
 *
 *   ●sta  04:12  71%  ⚠
 *
 * Drawn into row 7 of an already-rendered buffer, so every page and every
 * overlay gets it from one call. The M3 passkey overlay left this row
 * blank with a recorded promise to fill it here; this is that promise.
 *
 * The 5x7 font has no ● or ⚠, and inventing glyphs for a 21-column strip
 * is how a status line becomes unreadable. ASCII stand-ins with the same
 * meaning: '*' filled / 'o' hollow for the packet dot, '!' for the unacked
 * alarm. Both are one cell, both are legible at four feet. */
void app_ui_render_strip(const app_ui_state_t *st, app_ui_fb_t *fb) {
    if (st == NULL || fb == NULL) {
        return;
    }
    char line[APP_UI_COLS + 1];
    char elapsed[8];
    app_ui_format_hhmm(st->elapsed_s, st->session_active, elapsed,
                       sizeof elapsed);

    const char *mode = st->net_mode == APP_UI_NET_STA   ? "sta"
                       : st->net_mode == APP_UI_NET_AP  ? (st->ap_client ? "ap*" : "ap ")
                                                        : "---";
    char batt[5];
    if (st->charging) {
        snprintf(batt, sizeof batt, "USB");
    } else if (st->soc_pct == BRIDGE_SOC_UNKNOWN) {
        /* Never `0%` for a bridge that cannot measure its pack (P3.2). */
        snprintf(batt, sizeof batt, "--%%");
    } else {
        snprintf(batt, sizeof batt, "%u%%", (unsigned)st->soc_pct);
    }

    snprintf(line, sizeof line, "%c%s %s %4s %c", st->base_ok ? '*' : 'o',
             mode, elapsed, batt, st->alarm_unacked ? '!' : ' ');
    app_ui_draw_text(fb, 0, APP_UI_STRIP_ROW, line);
}

/* ── page 1: probes (F11b.3; 07 §7.2) ────────────────────────────────
 *
 *   Pit          204/250
 *
 *       243°F        v
 *
 *   Brisket 163°F  +4.1
 *   Point    159°F  +3.8
 *   Flat        ---
 *   ●sta  04:12  71%
 */

static int pit_index(const app_ui_state_t *st) {
    for (int i = 0; i < 4 && i < st->num_probes; i++) {
        if (st->probe[i].role == BRIDGE_PROBE_ROLE_PIT) {
            return i;
        }
    }
    /* "if no role is assigned, probe 1 does" (07 §7.2). */
    return st->num_probes > 0 ? 0 : -1;
}

/* ▲ above +5 °F/hr, ▼ below −5, – between (07 §7.2). The 5x7 font has no
 * triangles; '^' / 'v' / '-' carry the same three states in one cell. */
static char trend_char(const app_ui_probe_t *p) {
    if (!p->slope_valid) {
        return ' ';
    }
    if (p->slope_f10_per_hr > 50) {
        return '^';
    }
    if (p->slope_f10_per_hr < -50) {
        return 'v';
    }
    return '-';
}

void app_ui_render_page_probes(const app_ui_state_t *st, app_ui_fb_t *fb) {
    app_ui_fb_clear(fb);
    if (st == NULL) {
        return;
    }
    const int pit = pit_index(st);
    char buf[32];

    if (pit >= 0) {
        const app_ui_probe_t *p = &st->probe[pit];
        char nm[APP_UI_NAME_LEN + 1];
        snprintf(nm, sizeof nm, "%s", p->name[0] ? p->name : "Pit");
        app_ui_draw_text(fb, 0, 0, nm);
        if (p->has_band) {
            char lo[8];
            char hi[8];
            format_temp_whole(p->band_lo_f10, st->celsius, lo, sizeof lo);
            format_temp_whole(p->band_hi_f10, st->celsius, hi, sizeof hi);
            snprintf(buf, sizeof buf, "%s/%s", lo, hi);
            const int len = (int)strlen(buf);
            app_ui_draw_text(fb, APP_UI_COLS - len, 0, buf);
        }

        /* The one number you actually want, made large (07 §7.2). */
        char big[12];
        if (attached(p->temp_f10)) {
            char whole[8];
            format_temp_whole(p->temp_f10, st->celsius, whole, sizeof whole);
            snprintf(big, sizeof big, "%s\xC2\xB0", whole);
        } else {
            snprintf(big, sizeof big, "---");
        }
        if (attached(p->temp_f10)) {
            (void)app_ui_draw_text_large(fb, 6, 10, big);
        } else {
            /* The large font has no '-'; a detached pit says so in the
             * small font rather than rendering a number. */
            app_ui_draw_text(fb, 4, 2, "--- detached");
        }
        const char t = trend_char(p);
        if (t != ' ') {
            const char tr[2] = {t, '\0'};
            app_ui_draw_text(fb, APP_UI_COLS - 2, 2, tr);
        }
    }

    /* Rows 4..6: the other probes, name / value / °F-hr. */
    int row = 4;
    for (int i = 0; i < 4 && i < st->num_probes && row <= 6; i++) {
        if (i == pit) {
            continue;
        }
        const app_ui_probe_t *p = &st->probe[i];
        char nm[10];
        snprintf(nm, sizeof nm, "%.8s", p->name[0] ? p->name : "Probe");
        app_ui_draw_text(fb, 0, row, nm);

        char val[10];
        format_temp_whole(p->temp_f10, st->celsius, val, sizeof val);
        const int vlen = (int)strlen(val);
        app_ui_draw_text(fb, 14 - vlen, row, val);

        if (attached(p->temp_f10) && p->slope_valid) {
            const int32_t s = p->slope_f10_per_hr;
            snprintf(buf, sizeof buf, "%+ld.%ld", (long)(s / 10),
                     (long)((s < 0 ? -s : s) % 10));
            const int len = (int)strlen(buf);
            app_ui_draw_text(fb, APP_UI_COLS - len, row, buf);
        }
        row++;
    }

    app_ui_render_strip(st, fb);
}

/* ── page 2: cook (F11b.4; 07 §7.2) ────────────────────────────────── */

void app_ui_render_page_cook(const app_ui_state_t *st, app_ui_fb_t *fb) {
    app_ui_fb_clear(fb);
    if (st == NULL) {
        return;
    }
    char buf[40];

    if (!st->session_active) {
        app_ui_draw_text(fb, 0, 0, "COOK");
        app_ui_draw_text(fb, 0, 2, "No session running");
        app_ui_draw_text(fb, 0, 4, "Hold PRG to start");
        app_ui_render_strip(st, fb);
        return;
    }

    snprintf(buf, sizeof buf, "%.14s", st->session_name);
    app_ui_draw_text(fb, 0, 0, buf);
    snprintf(buf, sizeof buf, "#%u", (unsigned)st->session_id);
    app_ui_draw_text(fb, APP_UI_COLS - (int)strlen(buf), 0, buf);

    char hms[12];
    app_ui_format_hhmmss(st->elapsed_s, hms, sizeof hms);
    snprintf(buf, sizeof buf, "Elapsed %s", hms);
    app_ui_draw_text(fb, 0, 1, buf);

    /* The primary food probe's current → target. */
    int food = -1;
    for (int i = 0; i < 4 && i < st->num_probes; i++) {
        if (st->probe[i].role == BRIDGE_PROBE_ROLE_FOOD &&
            attached(st->probe[i].temp_f10)) {
            food = i;
            break;
        }
    }
    if (food >= 0) {
        char cur[8];
        char tgt[8];
        format_temp_whole(st->probe[food].temp_f10, st->celsius, cur,
                          sizeof cur);
        if (st->probe[food].target_f10 > 0) {
            format_temp_whole((int16_t)st->probe[food].target_f10,
                              st->celsius, tgt, sizeof tgt);
        } else {
            snprintf(tgt, sizeof tgt, "--");
        }
        snprintf(buf, sizeof buf, "%.7s %s>%s\xC2\xB0%c",
                 st->probe[food].name[0] ? st->probe[food].name : "Food", cur,
                 tgt, st->celsius ? 'C' : 'F');
        app_ui_draw_text(fb, 0, 2, buf);
    }

    /* The device's ETA is the cheap one, and it says so. The app tier owns
     * 09 §9.4's two models and its range presentation; the device never
     * renders a confident wrong answer. */
    if (st->stalled) {
        app_ui_draw_text(fb, 0, 3, "ETA  --     (stall)");
    } else if (st->eta_valid) {
        snprintf(buf, sizeof buf, "ETA  %uh%02um",
                 (unsigned)(st->eta_s / 3600u),
                 (unsigned)((st->eta_s / 60u) % 60u));
        app_ui_draw_text(fb, 0, 3, buf);
    } else {
        app_ui_draw_text(fb, 0, 3, "ETA  --");
    }

    /* The 2 h pit sparkline, straight from the RAM ring (04 §4.3). This is
     * where "did the fire hold overnight?" gets answered without
     * unlocking a phone. */
    app_ui_draw_sparkline(fb, 3, 32, 122, 16, st->spark, st->spark_n);

    snprintf(buf, sizeof buf, "Marks %u  %u pts", (unsigned)st->mark_count,
             (unsigned)st->sample_count);
    app_ui_draw_text(fb, 0, 6, buf);

    app_ui_render_strip(st, fb);
}

/* ── page 3: network (F11b.5; 07 §7.2) ──────────────────────────────
 * The page that answers the brief's second question, rendered differently
 * per mode. Hosting puts EVERYTHING needed to join on the glass — no app,
 * no manual, no default password to look up. */

/* `▂▄▆█` has no 5x7 glyphs; four bars of ASCII carry the same reading. */
static const char *signal_bars(int8_t rssi) {
    if (rssi >= -55) {
        return "####";
    }
    if (rssi >= -67) {
        return "###.";
    }
    if (rssi >= -78) {
        return "##..";
    }
    if (rssi >= -90) {
        return "#...";
    }
    return "....";
}

void app_ui_render_page_network(const app_ui_state_t *st, app_ui_fb_t *fb) {
    app_ui_fb_clear(fb);
    if (st == NULL) {
        return;
    }
    char buf[40];

    if (st->net_mode == APP_UI_NET_AP) {
        app_ui_draw_text(fb, 0, 0, "NETWORK   hosting");
        app_ui_draw_text(fb, 0, 1, "SSID");
        snprintf(buf, sizeof buf, "  %.18s", st->ssid);
        app_ui_draw_text(fb, 0, 2, buf);
        app_ui_draw_text(fb, 0, 3, "Password");
        snprintf(buf, sizeof buf, "  %.10s", st->psk);
        app_ui_draw_text(fb, 0, 4, buf);
        app_ui_draw_text(fb, 0, 5, "http://192.168.4.1");
        snprintf(buf, sizeof buf, "%u device%s connected",
                 (unsigned)st->ap_clients, st->ap_clients == 1 ? "" : "s");
        app_ui_draw_text(fb, 0, 6, buf);
    } else if (st->net_state == APP_UI_NET_UP) {
        app_ui_draw_text(fb, 0, 0, "NETWORK   joined");
        snprintf(buf, sizeof buf, "%.21s", st->ssid);
        app_ui_draw_text(fb, 0, 1, buf);
        snprintf(buf, sizeof buf, "  %s  %d dBm", signal_bars(st->wifi_rssi),
                 (int)st->wifi_rssi);
        app_ui_draw_text(fb, 0, 2, buf);
        app_ui_draw_text(fb, 0, 3, st->ip);
        snprintf(buf, sizeof buf, "%.21s", st->host);
        app_ui_draw_text(fb, 0, 4, buf);
        snprintf(buf, sizeof buf, "BLE %u conn  %u bond", (unsigned)st->ble_conns,
                 (unsigned)st->ble_bonds);
        app_ui_draw_text(fb, 0, 5, buf);
    } else {
        /* Connecting or failed. `NETWORK   connecting` is 20 of the 21
         * columns — the tightest line on any page, and the reason this
         * whole layer counts cells. */
        app_ui_draw_text(fb, 0, 0,
                         st->net_state == APP_UI_NET_FAILED
                             ? "NETWORK   failed"
                             : "NETWORK   connecting");
        snprintf(buf, sizeof buf, "%.21s", st->ssid);
        app_ui_draw_text(fb, 0, 1, buf);
        snprintf(buf, sizeof buf, "  attempt %u",
                 (unsigned)st->retry_attempt);
        app_ui_draw_text(fb, 0, 2, buf);
        char mmss[8];
        snprintf(mmss, sizeof mmss, "%u:%02u", (unsigned)(st->retry_in_s / 60u),
                 (unsigned)(st->retry_in_s % 60u));
        snprintf(buf, sizeof buf, "  retry in %s", mmss);
        app_ui_draw_text(fb, 0, 3, buf);
        app_ui_draw_text(fb, 0, 5, "Hold PRG to host");
        app_ui_draw_text(fb, 0, 6, "  own network");
    }
    app_ui_render_strip(st, fb);
}

/* ── page 4: radio (F11b.5; 07 §7.2) ────────────────────────────────
 * The mean inter-packet interval is on the glass because it is the
 * cheapest possible field test of 02 Q1. Billows is decoded and stored
 * and NOT displayed (D11). */

void app_ui_render_page_radio(const app_ui_state_t *st, app_ui_fb_t *fb) {
    app_ui_fb_clear(fb);
    if (st == NULL) {
        return;
    }
    char buf[40];

    if (!st->paired) {
        app_ui_draw_text(fb, 0, 0, "RADIO    UNPAIRED");
        app_ui_draw_text(fb, 0, 2, "Scanning 915/920 MHz");
        app_ui_draw_text(fb, 0, 4, "Put your Smoke X");
        app_ui_draw_text(fb, 0, 5, "base in SYNC mode");
        app_ui_render_strip(st, fb);
        return;
    }

    app_ui_draw_text(fb, 0, 0, "RADIO      paired");
    snprintf(buf, sizeof buf, "Smoke X  %.8s", st->device_id);
    app_ui_draw_text(fb, 0, 1, buf);
    snprintf(buf, sizeof buf, "%u.%u MHz",
             (unsigned)(st->frequency_hz / 1000000u),
             (unsigned)((st->frequency_hz / 100000u) % 10u));
    app_ui_draw_text(fb, 0, 2, buf);
    snprintf(buf, sizeof buf, "RSSI %d  SNR %d", (int)st->lora_rssi,
             (int)st->lora_snr);
    app_ui_draw_text(fb, 0, 3, buf);
    snprintf(buf, sizeof buf, "Last packet %5us",
             (unsigned)st->last_packet_s);
    app_ui_draw_text(fb, 0, 4, buf);
    snprintf(buf, sizeof buf, "OK %u  Bad %u", (unsigned)st->packets_ok,
             (unsigned)st->packets_bad);
    app_ui_draw_text(fb, 0, 5, buf);
    snprintf(buf, sizeof buf, "Interval %u.%us avg",
             (unsigned)(st->interval_s10 / 10u),
             (unsigned)(st->interval_s10 % 10u));
    app_ui_draw_text(fb, 0, 6, buf);
    app_ui_render_strip(st, fb);
}

/* ── page 5: system (F11b.5; 07 §7.2) ───────────────────────────────
 * Where V3a.1's deferred OLED-error row becomes readable without a serial
 * cable: the panel's own I²C ok/err counters. */

void app_ui_render_page_system(const app_ui_state_t *st, app_ui_fb_t *fb) {
    app_ui_fb_clear(fb);
    if (st == NULL) {
        return;
    }
    char buf[40];

    snprintf(buf, sizeof buf, "SYSTEM    %.10s", st->fw);
    app_ui_draw_text(fb, 0, 0, buf);

    if (st->soc_pct == BRIDGE_SOC_UNKNOWN) {
        app_ui_draw_text(fb, 0, 1, "Battery  n/a");
    } else {
        snprintf(buf, sizeof buf, "Battery %u.%02uV %u%%",
                 (unsigned)(st->mv / 1000u), (unsigned)((st->mv / 10u) % 100u),
                 (unsigned)st->soc_pct);
        app_ui_draw_text(fb, 0, 1, buf);
    }
    if (st->charging) {
        app_ui_draw_text(fb, 0, 2, "  charging");
    } else if (st->saver) {
        app_ui_draw_text(fb, 0, 2, "  saver on");
    }

    char hms[12];
    app_ui_format_hhmmss(st->uptime_s, hms, sizeof hms);
    snprintf(buf, sizeof buf, "Uptime  %s", hms);
    app_ui_draw_text(fb, 0, 3, buf);

    const unsigned pct =
        st->storage_total_b > 0
            ? (unsigned)(((uint64_t)st->storage_used_b * 100u) /
                         st->storage_total_b)
            : 0u;
    snprintf(buf, sizeof buf, "Storage %u%% %u cooks", pct,
             (unsigned)st->sessions);
    app_ui_draw_text(fb, 0, 4, buf);
    snprintf(buf, sizeof buf, "Heap %uk (min %uk)",
             (unsigned)(st->heap_free / 1024u),
             (unsigned)(st->heap_min / 1024u));
    app_ui_draw_text(fb, 0, 5, buf);
    /* V3a.1's row. `err` beside `ok` rather than alone, because an error
     * count with no denominator is not a measurement. */
    snprintf(buf, sizeof buf, "I2C %u ok %u err", (unsigned)st->i2c_ok,
             (unsigned)st->i2c_err);
    app_ui_draw_text(fb, 0, 6, buf);

    app_ui_render_strip(st, fb);
}

/* ── overlays (F11a.4, F11b.6; 07 §7.3) ─────────────────────────────── */

/* §7.3's mock, transcribed:
 *
 *   ┌─────────────────────┐
 *   │  PAIR WITH PHONE    │  row 0, small font
 *   │                     │  row 1
 *   │      418 302        │  rows 2-4, large font, group gap
 *   │                     │
 *   │  enter this code    │  row 5
 *   │  in the app         │  row 6
 *   │●sta  04:12  71%     │  row 7 — the strip, added in F11b.1
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
    app_ui_render_strip(st, fb);
}

void app_ui_render_overlay_alarm(const app_ui_state_t *st, app_ui_fb_t *fb) {
    app_ui_fb_clear(fb);
    if (st == NULL) {
        return;
    }
    /* Inverted video on the title bar, so it reads across a dark yard.
     * F11a's invert_region exists for exactly this. */
    app_ui_draw_text_centred(fb, 0, "A L A R M");
    app_ui_invert_region(fb, 0, 0, APP_UI_WIDTH, 8);

    char buf[32];
    if (st->alarm_probe >= 1 && st->alarm_probe <= 4) {
        const app_ui_probe_t *p = &st->probe[st->alarm_probe - 1];
        snprintf(buf, sizeof buf, "%.18s",
                 p->name[0] ? p->name : "Probe");
        app_ui_draw_text(fb, 1, 2, buf);
        char val[16];
        app_ui_format_temp(st->alarm_value_f10, st->celsius, true, val,
                           sizeof val);
        snprintf(buf, sizeof buf, "  %s", val);
        app_ui_draw_text(fb, 1, 3, buf);
    }
    /* The generated name is the JSON spelling; underscores read badly on
     * glass, so they become spaces and nothing else changes. */
    const char *rule = bridge_alarm_rule_str(st->alarm_rule);
    snprintf(buf, sizeof buf, "%.20s", rule);
    for (char *p = buf; *p; p++) {
        if (*p == '_') {
            *p = ' ';
        }
    }
    app_ui_draw_text(fb, 1, 4, buf);
    app_ui_draw_text(fb, 1, 6, "tap PRG to silence");
    app_ui_render_strip(st, fb);
}

void app_ui_render_overlay_confirm(const app_ui_state_t *st,
                                   app_ui_fb_t *fb) {
    app_ui_fb_clear(fb);
    if (st == NULL) {
        return;
    }
    char buf[24];
    snprintf(buf, sizeof buf, "%.21s", st->confirm_text);
    app_ui_draw_text_centred(fb, 1, buf);
    snprintf(buf, sizeof buf, "keep holding   %u",
             (unsigned)st->confirm_count);
    app_ui_draw_text(fb, 2, 3, buf);
    /* The visible cancel path — hold actions commit on RELEASE, and this
     * line is what makes that discoverable rather than folklore. */
    app_ui_draw_text(fb, 2, 5, "release to cancel");
    app_ui_render_strip(st, fb);
}

void app_ui_render_overlay_splash(const app_ui_state_t *st, app_ui_fb_t *fb) {
    app_ui_fb_clear(fb);
    if (st == NULL) {
        return;
    }
    char buf[24];
    app_ui_draw_text_centred(fb, 0, "SMOKE BRIDGE");
    snprintf(buf, sizeof buf, "%.20s", st->fw);
    app_ui_draw_text_centred(fb, 1, buf);
    /* "Hold PRG at boot" is impossible on this chip (GPIO0 is the boot
     * strapping pin); this is the 3 s POST-boot window (03 §3.4.1). */
    app_ui_draw_text(fb, 2, 3, "hold PRG for");
    snprintf(buf, sizeof buf, "AP mode      %u",
             (unsigned)st->confirm_count);
    app_ui_draw_text(fb, 2, 4, buf);
    /* 01 §1.5: transmitting into an open port can destroy the PA. */
    app_ui_draw_text(fb, 2, 6, "connect antenna");
    app_ui_draw_text(fb, 2, 7, "before use");
}

void app_ui_render_overlay_ota(const app_ui_state_t *st, app_ui_fb_t *fb) {
    app_ui_fb_clear(fb);
    if (st == NULL) {
        return;
    }
    char buf[24];
    app_ui_draw_text_centred(fb, 0, "UPDATING FIRMWARE");
    app_ui_draw_progress(fb, 8, 20, 88, 10, st->ota_pct);
    snprintf(buf, sizeof buf, "%u%%", (unsigned)st->ota_pct);
    app_ui_draw_text(fb, 17, 3, buf);
    app_ui_draw_text_centred(fb, 5, "do not power off");
    snprintf(buf, sizeof buf, "%.8s > %.8s", st->ota_from, st->ota_to);
    app_ui_draw_text_centred(fb, 6, buf);
}

/* ── the single entry point ─────────────────────────────────────────── */

void app_ui_render(const app_ui_state_t *st, app_ui_fb_t *fb) {
    if (st == NULL || fb == NULL) {
        return;
    }
    switch (st->overlay) {
    case APP_UI_OVERLAY_SPLASH:
        return app_ui_render_overlay_splash(st, fb);
    case APP_UI_OVERLAY_PASSKEY:
        return app_ui_render_overlay_passkey(st, fb);
    case APP_UI_OVERLAY_ALARM:
        return app_ui_render_overlay_alarm(st, fb);
    case APP_UI_OVERLAY_CONFIRM:
        return app_ui_render_overlay_confirm(st, fb);
    case APP_UI_OVERLAY_OTA:
        return app_ui_render_overlay_ota(st, fb);
    default:
        break;
    }
    switch (st->page) {
    case APP_UI_PAGE_COOK:
        return app_ui_render_page_cook(st, fb);
    case APP_UI_PAGE_NETWORK:
        return app_ui_render_page_network(st, fb);
    case APP_UI_PAGE_RADIO:
        return app_ui_render_page_radio(st, fb);
    case APP_UI_PAGE_SYSTEM:
        return app_ui_render_page_system(st, fb);
    default:
        return app_ui_render_page_probes(st, fb);
    }
}
