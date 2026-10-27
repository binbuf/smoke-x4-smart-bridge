#include "ssd1306.h"

#include <string.h>

static ssd1306_result_t cmd(const ssd1306_io_t *io, uint8_t value) {
    if (io == NULL || io->write == NULL) {
        return SSD1306_ERR_ARGUMENT;
    }
    return (io->write(io->ctx, false, &value, 1u) == 0) ? SSD1306_OK
                                                       : SSD1306_ERR_IO;
}

static ssd1306_result_t cmd2(const ssd1306_io_t *io, uint8_t first,
                             uint8_t second) {
    if (io == NULL || io->write == NULL) {
        return SSD1306_ERR_ARGUMENT;
    }
    return (io->write(io->ctx, false, (uint8_t[]){first, second}, 2u) == 0)
               ? SSD1306_OK
               : SSD1306_ERR_IO;
}

ssd1306_result_t ssd1306_init(const ssd1306_io_t *io) {
    if (io == NULL || io->write == NULL) {
        return SSD1306_ERR_ARGUMENT;
    }
    static const uint8_t init[] = {
        0xAE,       /* display off while configuring */
        0xD5, 0x80, /* clock divide / oscillator */
        0xA8, 0x3F, /* multiplex ratio 1/64 */
        0xD3, 0x00, /* display offset 0 */
        0x40,       /* start line 0 */
        0x8D, 0x14, /* charge pump on */
        0x20, 0x00, /* horizontal addressing mode */
        0xA1,       /* segment remap for this panel orientation */
        0xC8,       /* COM scan direction remapped */
        0xDA, 0x12, /* COM pins */
        0x81, 0xCF, /* contrast */
        0xD9, 0xF1, /* pre-charge */
        0xDB, 0x40, /* VCOMH */
        0xA4,       /* resume from GDDRAM */
        0xA6,       /* normal (not inverted) */
        0x2E,       /* deactivate scroll */
        0xAF,       /* display on */
    };
    if (io->write(io->ctx, false, init, sizeof(init)) != 0) {
        return SSD1306_ERR_IO;
    }
    return SSD1306_OK;
}

ssd1306_result_t ssd1306_set_power(const ssd1306_io_t *io, bool on) {
    return cmd(io, on ? 0xAF : 0xAE);
}

ssd1306_result_t ssd1306_flush(const ssd1306_io_t *io,
                               const uint8_t pages[SSD1306_PAGES]
                                                    [SSD1306_WIDTH]) {
    if (io == NULL || io->write == NULL || pages == NULL) {
        return SSD1306_ERR_ARGUMENT;
    }
    for (uint8_t page = 0; page < SSD1306_PAGES; page++) {
        /* Page start address, lower column 0, higher column 0. */
        if (cmd2(io, (uint8_t)(0xB0u | page), 0x00) != SSD1306_OK) {
            return SSD1306_ERR_IO;
        }
        if (cmd(io, 0x10) != SSD1306_OK) {
            return SSD1306_ERR_IO;
        }
        if (io->write(io->ctx, true, pages[page], SSD1306_WIDTH) != 0) {
            return SSD1306_ERR_IO;
        }
    }
    return SSD1306_OK;
}
