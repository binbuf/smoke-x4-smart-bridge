/* ota_image.c — F14.1: is this 288 bytes the front of an app image for
 * THIS chip? Pure C11; every offset below is read off a real build and
 * pinned by protocol/fixtures/ota/. */
#include "app_ota_core.h"

#include <string.h>

/* esp_image_header_t */
#define OFF_MAGIC 0u
#define OFF_CHIP_ID 12u /* uint16 LE */
#define IMAGE_MAGIC 0xE9u

/* esp_app_desc_t, which begins right after the image header (24 B) and
 * the first segment header (8 B). */
#define OFF_APP_DESC 32u
#define APP_DESC_MAGIC 0xABCD5432u
#define OFF_VERSION 48u     /* char[32] */
#define OFF_PROJECT 80u     /* char[32] */
#define OFF_IDF_VER 144u    /* char[32] */
#define DESC_STR_LEN 32u

static void copy_desc_str(char *dst, size_t dst_cap, const uint8_t *src) {
    /* The descriptor's char[32] fields are NOT guaranteed terminated by
     * anything but convention; force it. */
    size_t n = 0;
    while (n < DESC_STR_LEN && n + 1 < dst_cap && src[n] != '\0') {
        dst[n] = (char)src[n];
        n++;
    }
    dst[n] = '\0';
}

static uint16_t rd_u16le(const uint8_t *p) {
    return (uint16_t)((uint16_t)p[0] | ((uint16_t)p[1] << 8));
}

static uint32_t rd_u32le(const uint8_t *p) {
    return (uint32_t)p[0] | ((uint32_t)p[1] << 8) | ((uint32_t)p[2] << 16) |
           ((uint32_t)p[3] << 24);
}

app_ota_img_verdict_t app_ota_image_inspect(const void *buf, size_t len,
                                            app_ota_image_info_t *out) {
    app_ota_image_info_t local;
    if (!out) {
        out = &local;
    }
    memset(out, 0, sizeof *out);

    if (!buf || len < APP_OTA_HEADER_MIN) {
        /* Undecided, not invalid: the caller is streaming. */
        out->verdict = APP_OTA_IMG_UNDECIDED;
        return out->verdict;
    }

    const uint8_t *p = (const uint8_t *)buf;

    if (p[OFF_MAGIC] != IMAGE_MAGIC) {
        out->verdict = APP_OTA_IMG_BAD_MAGIC;
        return out->verdict;
    }

    out->chip_id = rd_u16le(p + OFF_CHIP_ID);
    if (out->chip_id != APP_OTA_CHIP_ID_ESP32S3) {
        out->verdict = APP_OTA_IMG_WRONG_CHIP;
        return out->verdict;
    }

    /* The clause that catches the merged image and bootloader.bin: both
     * carry 0xE9 and the right chip id, and neither has an
     * esp_app_desc_t here. */
    if (rd_u32le(p + OFF_APP_DESC) != APP_DESC_MAGIC) {
        out->verdict = APP_OTA_IMG_NO_APP_DESC;
        return out->verdict;
    }

    copy_desc_str(out->version, sizeof out->version, p + OFF_VERSION);
    copy_desc_str(out->project, sizeof out->project, p + OFF_PROJECT);
    copy_desc_str(out->idf_ver, sizeof out->idf_ver, p + OFF_IDF_VER);

    out->verdict = APP_OTA_IMG_OK;
    return out->verdict;
}

const char *app_ota_image_verdict_str(app_ota_img_verdict_t v) {
    switch (v) {
    case APP_OTA_IMG_OK:
        return "ok";
    case APP_OTA_IMG_UNDECIDED:
        return "header_incomplete";
    case APP_OTA_IMG_BAD_MAGIC:
        return "not_an_esp_image";
    case APP_OTA_IMG_WRONG_CHIP:
        return "wrong_chip";
    case APP_OTA_IMG_NO_APP_DESC:
        /* Named for the mistake, not for the byte: this is what a human
         * uploading smoke-bridge-heltec-v3-1.0.0.bin instead of
         * smoke-bridge-1.0.0-ota.bin gets to read. */
        return "not_an_app_image_use_the_ota_bin";
    }
    return "unknown";
}
