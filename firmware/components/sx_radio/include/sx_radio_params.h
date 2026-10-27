/*
 * sx_radio_params.h - the single source of truth for Smoke X LoRa settings
 * (design 02 section 2.1, design 03 section 3.3).
 *
 * Pure C: the host test suite includes this header, so it must not depend on
 * ESP-IDF. The radio task reads this block; do not scatter the same numbers
 * through the driver wrapper.
 */
#ifndef SX4_SX_RADIO_PARAMS_H
#define SX4_SX_RADIO_PARAMS_H

#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/* Fixed receive buffer. The largest observed Smoke X payload is ~120 bytes. */
#define SX4_RADIO_MAX_PAYLOAD 128u

/* radio_rx task budget (design 03 section 3.3). */
#define SX4_RADIO_TASK_STACK_BYTES 4096u
#define SX4_RADIO_TASK_PRIORITY 6u
#define SX4_RADIO_TASK_CORE 1u

/* Driver polling cadence (design 03 section 3.3). */
#define SX4_RADIO_POLL_DELAY_TICKS 1u

/* Until T16 owns the persisted pairing record, start on the X4 sync channel. */
#define SX4_RADIO_DEFAULT_FREQUENCY_HZ 915000000u

typedef struct {
    uint8_t spreading_factor;   /* SF9 */
    uint8_t bandwidth_index;    /* SX126x driver index 4 == 125 kHz */
    uint8_t coding_rate;        /* SX126X_LORA_CR_4_5 */
    uint16_t preamble_symbols;  /* 10 */
    uint8_t sync_word;          /* 0x12 */
    bool crc_on;                /* CRC on */
    float tcxo_voltage;         /* Heltec V3 TCXO: 3.3 V via DIO3 */
    bool use_regulator_ldo;     /* TCXO 3.3 V LDO */
    uint32_t frequency_min_hz;  /* 902 MHz */
    uint32_t frequency_max_hz;  /* 928 MHz */
    uint32_t sync_x4_hz;        /* 915 MHz */
    uint32_t sync_x2_hz;        /* 920 MHz */
} sx4_radio_params_t;

/* The approved parameter block from design 02 section 2.1. */
extern const sx4_radio_params_t sx4_radio_params;

/* True only for 902-928 MHz. Retuning must pass this check. */
bool sx4_radio_frequency_valid(uint32_t frequency_hz);

#ifdef __cplusplus
}
#endif

#endif /* SX4_SX_RADIO_PARAMS_H */
