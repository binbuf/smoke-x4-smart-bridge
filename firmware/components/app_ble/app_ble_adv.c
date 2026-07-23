/* app_ble_adv.c — the advertising and scan-response builders and the
 * interval policy (F10.2, ble-gatt §2).
 *
 * Both PDUs are pure functions byte-asserted against the §2 tables, and
 * the 31-byte legacy budget is a build error rather than a runtime
 * surprise. The name comes from F8.3's MAC-suffix helper so the BLE name,
 * the AP SSID, and the mDNS TXT `id` cannot drift apart.
 */
#include "app_ble_internal.h"

#include <stdio.h>
#include <string.h>

#include "app_net_core.h"

/* AD types (Core Supplement, Part A). */
#define AD_FLAGS 0x01
#define AD_UUID128_COMPLETE 0x07
#define AD_NAME_COMPLETE 0x09
#define AD_MANUFACTURER 0xFF
/* LE General Discoverable, BR/EDR not supported. */
#define ADV_FLAGS_VALUE 0x06

/* §2.1: 3 (flags) + 18 (16 B UUID + type + length) = 21 of 31. */
#define ADV_LEN 21
/* §2.2: 18 (16-char name) + 11 (2 B company + 7 B blob) = 29 of 31. */
#define SCAN_RSP_LEN 29

_Static_assert(ADV_LEN <= APP_BLE_ADV_MAX,
               "advertising PDU exceeds the 31-byte legacy budget");
_Static_assert(SCAN_RSP_LEN <= APP_BLE_ADV_MAX,
               "scan response exceeds the 31-byte legacy budget");

static uint64_t s_fast_until_ms;

void app_ble_adv_reset(void) { s_fast_until_ms = 0; }

void app_ble_local_name(const uint8_t mac[6], char out[APP_BLE_NAME_MAX]) {
    /* app_net_ap_ssid is the single definition of the suffix. Reusing it
     * is not laziness: it is why "SmokeBridge-A4F2" in the Wi-Fi picker
     * and in the Bluetooth scan list are provably the same device. */
    char ssid[APP_NET_SSID_MAX];
    app_net_ap_ssid(mac, ssid);
    snprintf(out, APP_BLE_NAME_MAX, "%.*s", APP_BLE_NAME_MAX - 1, ssid);
}

int app_ble_build_adv(uint8_t *out, size_t cap) {
    if (cap < ADV_LEN) {
        return -1;
    }
    size_t off = 0;
    out[off++] = 2; /* length: type + value */
    out[off++] = AD_FLAGS;
    out[off++] = ADV_FLAGS_VALUE;

    out[off++] = 17; /* length: type + 16 B UUID */
    out[off++] = AD_UUID128_COMPLETE;
    app_ble_uuid128(APP_BLE_SERVICE_UUID16, out + off);
    off += 16;
    return (int)off;
}

int app_ble_build_status_blob(uint8_t out[APP_BLE_STATUS_BLOB_LEN]) {
    app_ble_live_t live;
    app_ble_live_snapshot(&live);

    /* Same bit assignments as live_state.flags (§2.3) — one meaning, two
     * places it is read, zero chance of them disagreeing. */
    uint8_t flags = 0;
    if (live.paired) {
        flags |= BRIDGE_LIVE_STATE_FLAGS_PAIRED;
    }
    if (live.session_active) {
        flags |= BRIDGE_LIVE_STATE_FLAGS_SESSION_ACTIVE;
    }
    if (live.billows) {
        flags |= BRIDGE_LIVE_STATE_FLAGS_BILLOWS;
    }
    if (live.alarm_active) {
        flags |= BRIDGE_LIVE_STATE_FLAGS_ALARM_ACTIVE;
    }
    if (live.clock_valid) {
        flags |= BRIDGE_LIVE_STATE_FLAGS_CLOCK_VALID;
    }

    uint32_t minutes = live.session_t / 60u;
    if (minutes > 0xFFFFu) {
        minutes = 0xFFFFu;
    }

    out[0] = 1; /* ver */
    out[1] = flags;
    /* The pit probe, sentinels intact: a detached pit advertises
     * TEMP_DETACHED, never 0 — the scan list says "—", not "0 °F". */
    bridge_put_u16(out + 2, (uint16_t)live.temp[0]);
    out[4] = live.soc_pct; /* SOC_UNKNOWN until F12 (ble-gatt §5.1.1) */
    bridge_put_u16(out + 5, (uint16_t)minutes);
    return APP_BLE_STATUS_BLOB_LEN;
}

int app_ble_build_scan_rsp(uint8_t *out, size_t cap) {
    if (g_ble_ops == NULL || cap < SCAN_RSP_LEN) {
        return -1;
    }
    app_ble_sysinfo_t sys;
    memset(&sys, 0, sizeof sys);
    g_ble_ops->sysinfo(&sys);

    char name[APP_BLE_NAME_MAX];
    app_ble_local_name(sys.mac, name);
    const size_t name_len = strlen(name);

    size_t off = 0;
    out[off++] = (uint8_t)(name_len + 1);
    out[off++] = AD_NAME_COMPLETE;
    memcpy(out + off, name, name_len);
    off += name_len;

    uint8_t blob[APP_BLE_STATUS_BLOB_LEN];
    (void)app_ble_build_status_blob(blob);
    out[off++] = (uint8_t)(1 + 2 + sizeof blob);
    out[off++] = AD_MANUFACTURER;
    bridge_put_u16(out + off, APP_BLE_COMPANY_ID);
    off += 2;
    memcpy(out + off, blob, sizeof blob);
    off += sizeof blob;
    return (int)off;
}

/* ── Interval policy (§2) ─────────────────────────────────────────── */

void app_ble_adv_note_fast(uint64_t now_ms) {
    s_fast_until_ms = now_ms + APP_BLE_ADV_FAST_WINDOW_MS;
}

uint16_t app_ble_adv_interval_ms(uint64_t now_ms) {
    return now_ms < s_fast_until_ms ? APP_BLE_ADV_FAST_MS : APP_BLE_ADV_IDLE_MS;
}
