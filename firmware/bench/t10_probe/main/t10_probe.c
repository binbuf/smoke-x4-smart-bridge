/*
 * T10 bench probe — NOT product code.
 *
 * Purpose: capture real Smoke X4 LoRa traffic for the parser fixture corpus.
 * It starts on the 915.0 MHz sync channel, logs every packet with RSSI/SNR and
 * a hex payload, and on a sync beacon retunes to the operating frequency and
 * sends the one allowed pairing ACK so the X4 returns to normal state traffic.
 *
 * The only transmission is the pairing ACK. There is no other TX path.
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <stdbool.h>

#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "esp_log.h"
#include "esp_timer.h"
#include "ra01s.h"

static const char *TAG = "t10cap";

#define SYNC_FREQ_HZ   915000000u
#define FALLBACK_FREQ_HZ 918500000u
#define ACK_ENABLE     1

static bool s_retuned;
static uint32_t s_rx_count;
static uint32_t s_bad_len_count;

static int comma_count(const char *s)
{
    int n = 0;
    for (; *s; s++) {
        if (*s == ',') {
            n++;
        }
    }
    return n;
}

static const char *classify(int commas)
{
    switch (commas) {
    case 2:  return "ack2";
    case 6:  return "sync6";
    case 26: return "state26";
    case 16: return "state16";
    default: return "other";
    }
}

static void log_hex(const uint8_t *buf, int len, char *out, size_t outlen)
{
    size_t pos = 0;
    for (int i = 0; i < len && pos + 3 < outlen; i++) {
        pos += (size_t)snprintf(out + pos, outlen - pos, "%02x", buf[i]);
    }
    if (pos < outlen) {
        out[pos] = '\0';
    }
}

static void log_ascii(const uint8_t *buf, int len, char *out, size_t outlen)
{
    size_t pos = 0;
    for (int i = 0; i < len && pos + 2 < outlen; i++) {
        uint8_t c = buf[i];
        out[pos++] = (c >= 0x20 && c <= 0x7e) ? (char)c : '.';
    }
    if (pos < outlen) {
        out[pos] = '\0';
    }
}

/* Sync beacon: <field0>,<device_id>,<b0>,<b1>,<b2>,<b3>, */
static bool parse_sync(const char *payload, char *id, size_t idlen,
                       uint32_t *freq_hz)
{
    char tmp[192];
    strncpy(tmp, payload, sizeof tmp - 1);
    tmp[sizeof tmp - 1] = '\0';

    char *save = NULL;
    char *f0 = strtok_r(tmp, ",", &save);
    char *dev = strtok_r(NULL, ",", &save);
    char *b0s = strtok_r(NULL, ",", &save);
    char *b1s = strtok_r(NULL, ",", &save);
    char *b2s = strtok_r(NULL, ",", &save);
    char *b3s = strtok_r(NULL, ",", &save);
    if (!f0 || !dev || !b0s || !b1s || !b2s || !b3s) {
        return false;
    }

    char *end = NULL;
    long b0 = strtol(b0s, &end, 10);
    if (!end || *end) {
        return false;
    }
    long b1 = strtol(b1s, &end, 10);
    if (!end || *end) {
        return false;
    }
    long b2 = strtol(b2s, &end, 10);
    if (!end || *end) {
        return false;
    }
    long b3 = strtol(b3s, &end, 10);
    if (!end || *end) {
        return false;
    }

    uint32_t f = (uint32_t)(b0 & 0xff) |
                 ((uint32_t)(b1 & 0xff) << 8) |
                 ((uint32_t)(b2 & 0xff) << 16) |
                 ((uint32_t)(b3 & 0xff) << 24);
    if (f < 902000000u || f > 928000000u) {
        return false;
    }

    strncpy(id, dev, idlen - 1);
    id[idlen - 1] = '\0';
    *freq_hz = f;
    return true;
}

static void retune(uint32_t freq_hz)
{
    ESP_LOGI(TAG, "TUNE %lu Hz", (unsigned long)freq_hz);
    SetStandby(SX126X_STANDBY_RC);
    SetRfFrequency(freq_hz);
    SetRx(SX126X_RX_TIMEOUT_INF);
}

static void send_ack(const char *id)
{
    char ack[32];
    int n = snprintf(ack, sizeof ack, "%s,SUCCESS,", id);
    if (n <= 0 || n >= (int)sizeof ack) {
        ESP_LOGE(TAG, "ACK build failed");
        return;
    }
    ESP_LOGI(TAG, "ACK_TX len=%d payload=%s", n, ack);
    bool ok = LoRaSend((uint8_t *)ack, (int16_t)n, SX126x_TXMODE_SYNC);
    ESP_LOGI(TAG, "ACK_TX result=%d", ok ? 1 : 0);
}

static void handle_packet(const uint8_t *buf, int len)
{
    int64_t t_ms = esp_timer_get_time() / 1000;
    int8_t rssi = 0;
    int8_t snr = 0;
    GetPacketStatus(&rssi, &snr);

    char ascii[320];
    char hex[640];
    log_ascii(buf, len, ascii, sizeof ascii);
    log_hex(buf, len, hex, sizeof hex);

    int commas = comma_count(ascii);
    const char *cls = classify(commas);

    ESP_LOGI(TAG, "RX t_ms=%lld len=%d rssi=%d snr=%d commas=%d class=%s",
             (long long)t_ms, len, rssi, snr, commas, cls);
    ESP_LOGI(TAG, "PAYLOAD ascii=\"%s\"", ascii);
    ESP_LOGI(TAG, "PAYLOAD hex=%s", hex);

    s_rx_count++;

    if (commas == 6 && !s_retuned) {
        char id[16] = { 0 };
        uint32_t freq = 0;
        if (parse_sync(ascii, id, sizeof id, &freq)) {
            ESP_LOGI(TAG, "SYNC id=%s op_freq_hz=%lu", id,
                     (unsigned long)freq);
            s_retuned = true;
            /* Rule: the ACK goes out on the operating frequency, never the
             * sync channel. Retune first, then acknowledge. */
            retune(freq);
            vTaskDelay(pdMS_TO_TICKS(20));
#if ACK_ENABLE
            send_ack(id);
#endif
            SetRx(SX126X_RX_TIMEOUT_INF);
        } else {
            ESP_LOGW(TAG, "SYNC parse failed");
        }
    }
}

void app_main(void)
{
    ESP_LOGI(TAG, "BOOT t10 capture probe; listening on %lu Hz",
             (unsigned long)SYNC_FREQ_HZ);

    LoRaInit();
    int16_t rc = LoRaBegin(SYNC_FREQ_HZ, -3, 3.3f, true);
    if (rc != ERR_NONE) {
        ESP_LOGE(TAG, "LoRaBegin failed rc=%d", rc);
        return;
    }
    LoRaConfig(9, 4, 1, 10, 0, true, false);
    ESP_LOGI(TAG, "READY sf9 bw125 cr4/5 preamble10 sync0x12 crc-on");

    int64_t next_hb = esp_timer_get_time() + 10000000;
    uint8_t buf[256];
    while (true) {
        uint8_t len = LoRaReceive(buf, sizeof buf);
        if (len > 0) {
            handle_packet(buf, len);
        } else if (len == 0) {
            /* no packet this poll */
        }
        if (esp_timer_get_time() >= next_hb) {
            ESP_LOGI(TAG, "HEARTBEAT rx=%lu retuned=%d", (unsigned long)s_rx_count,
                     s_retuned ? 1 : 0);
            next_hb = esp_timer_get_time() + 10000000;
        }
        vTaskDelay(pdMS_TO_TICKS(5));
    }
}
