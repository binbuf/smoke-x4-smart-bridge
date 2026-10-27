/*
 * ssd1306.h - pure-C SSD1306 command/transfer core (design 01 section 1.5,
 * design 07 section 7.1).
 *
 * The core knows the panel init sequence, the 1 KB page-ordered flush and the
 * 0xAE/0xAF sleep/wake commands. It writes through a small callback so the
 * firmware adapter can use I2C and the host test can record the exact
 * transfer order. No ESP-IDF dependency.
 */
#ifndef SX4_SSD1306_H
#define SX4_SSD1306_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#define SSD1306_WIDTH 128u
#define SSD1306_HEIGHT 64u
#define SSD1306_PAGES 8u
#define SSD1306_FB_SIZE (SSD1306_WIDTH * SSD1306_PAGES)
#define SSD1306_I2C_ADDRESS 0x3Cu
#define SSD1306_I2C_HZ 400000u

/* `data` false = command stream (control byte 0x00), true = GDDRAM (0x40). */
typedef int (*ssd1306_write_fn)(void *ctx, bool data, const uint8_t *buf,
                                size_t len);

typedef struct {
    ssd1306_write_fn write;
    void *ctx;
} ssd1306_io_t;

typedef enum {
    SSD1306_OK = 0,
    SSD1306_ERR_ARGUMENT = -1,
    SSD1306_ERR_IO = -2,
} ssd1306_result_t;

/* Power-on init sequence; ends with display on (0xAF). */
ssd1306_result_t ssd1306_init(const ssd1306_io_t *io);

/* 0xAE (off) or 0xAF (on). The panel keeps its GDDRAM while off. */
ssd1306_result_t ssd1306_set_power(const ssd1306_io_t *io, bool on);

/*
 * Write all eight pages in SSD1306 page order. Each page is preceded by
 * {0xB0|page, 0x00, 0x10} and is a single 128-byte data transfer.
 */
ssd1306_result_t ssd1306_flush(const ssd1306_io_t *io,
                               const uint8_t pages[SSD1306_PAGES]
                                                    [SSD1306_WIDTH]);

#ifdef __cplusplus
}
#endif

#endif /* SX4_SSD1306_H */
