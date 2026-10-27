/*
 * sx_protocol.h - pure-C parser for Smoke X LoRa payloads.
 *
 * Portions derived from smoke-x-receiver
 * (https://github.com/G-Two/smoke-x-receiver), MIT License,
 * Copyright (c) 2022 G-Two. Retained and reworked for the X4 evidence in
 * protocol/fixtures/lora/ (design 02 sections 2.2-2.6, 2.9).
 *
 * No ESP-IDF dependency, no heap, no I/O. `strtok_r` on a fixed 128-byte
 * stack copy; every numeric field is parsed strictly. The parser fills its
 * output only on success: a rejected payload never yields a partial sample.
 *
 * Wire format (design 02 section 2.5). Temperatures arrive in tenths of the
 * message's active unit; the parser always emits canonical tenths of
 * Fahrenheit (`temp_f10`). `source_celsius` records the wire unit for
 * provenance only and is never a second value.
 *
 *   Sync beacon (6 commas):
 *     <field0>,<device_id>,<freq_b0>,<freq_b1>,<freq_b2>,<freq_b3>,
 *   State, X4 (26 commas) / X2 defensive (16 commas):
 *     <device_id>,<field1>,<units>,<field3>,
 *       [<state>,<temp_x10>,<alarm_armed>,<alarm_high>,<alarm_low>,] x N
 *     <billows_attached>,<new_alarm>,
 */
#ifndef SX4_SX_PROTOCOL_H
#define SX4_SX_PROTOCOL_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#include "sx_protocol_types.h"

#ifdef __cplusplus
extern "C" {
#endif

#define SX_PROTOCOL_NUM_COMMAS_SYNC 6u
#define SX_PROTOCOL_NUM_COMMAS_ACK 2u
#define SX_PROTOCOL_NUM_COMMAS_X2 16u
#define SX_PROTOCOL_NUM_COMMAS_X4 26u

/* Longest accepted payload; larger input is rejected, never truncated. */
#define SX_PROTOCOL_MAX_PAYLOAD 128u

/* Result codes. Any non-zero result leaves *out untouched. */
typedef enum {
    SX_PROTOCOL_OK = 0,
    SX_PROTOCOL_ERR_ARGUMENT = -1,
    SX_PROTOCOL_ERR_FORMAT = -2,  /* comma count, field, or numeric failure */
    SX_PROTOCOL_ERR_RANGE = -3,   /* converted value outside the canonical range */
    SX_PROTOCOL_ERR_FOREIGN_DEVICE = -4,
} sx_protocol_result_t;

/* Count comma occurrences; synchronisation and classification only. */
unsigned int sx_protocol_count_commas(const char *payload);

/* 16 commas -> 2 probes, 26 -> 4, anything else -> 0. The probe count is
 * learned from the first state message, never from the sync beacon. */
unsigned int sx_protocol_probes_for_commas(unsigned int commas);

/* Parse a 6-comma sync beacon. The frequency is not range-checked here:
 * the caller applies the 902-928 MHz rule before retuning or ACKing. */
sx_protocol_result_t sx_protocol_parse_sync(const char *payload,
                                            sx_protocol_sync_t *out);

/* Parse an X4 (26-comma) or X2 (16-comma, defensive) state message. The
 * probe count is inferred from the comma count; any other count is rejected.
 *
 * paired_device_id is the stored ID. When non-NULL a foreign device ID is
 * dropped (SX_PROTOCOL_ERR_FOREIGN_DEVICE) and the mismatch counter
 * increments. NULL means "no pairing yet" and accepts any syntactically
 * valid ID; that is for discovery and host corpus tests only. */
sx_protocol_result_t sx_protocol_parse_state(const char *payload,
                                             const char *paired_device_id,
                                             sx_protocol_state_t *out);

/* Format "<device_id>,SUCCESS," (the only packet the bridge transmits).
 * Returns bytes written excluding the NUL, or -1 on bad input. A successful
 * call increments the ACK-attempt counter. */
int sx_protocol_format_ack(const char *device_id, char *buf, size_t buf_size);

/* Diagnostics counters. Single writer (the sample/parser task); read from
 * housekeeping without atomics. */
void sx_protocol_counters_get(sx_protocol_counters_t *out);
void sx_protocol_counters_reset(void);

/* Radio-side hook for CRC/header rejects, so diagnostics have one counter
 * block for parse and link errors. The parser itself never sees CRC. */
void sx_protocol_note_crc_failure(void);

#ifdef ESP_PLATFORM
#include "esp_err.h"
/* Firmware boot hook: clears the counters. No allocation, no I/O. */
esp_err_t sx_protocol_init(void);
#endif

#ifdef __cplusplus
}
#endif

#endif /* SX4_SX_PROTOCOL_H */
