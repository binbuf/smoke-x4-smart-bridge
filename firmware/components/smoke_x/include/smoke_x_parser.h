/* smoke_x_parser.h — pure-C parser for Smoke X LoRa payloads.
 *
 * Ported from smoke-x-receiver (MIT © 2022 G-Two) and extended against real
 * X4 captures (protocol/fixtures/lora/). No ESP-IDF dependencies; no heap;
 * reentrant (F3.2). The controller wraps these calls with pairing state,
 * NVS, and event dispatch.
 *
 * Sync message (base station, during pairing):
 *   <field0>,<deviceid>,<f0>,<f1>,<f2>,<f3>,
 *   - f0..f3: decimal bytes of the LE uint32 operating frequency in Hz
 *   - field0: "020001" per the X2-era docs; a real X4 sent "000000" (Q2)
 *
 * Sync ACK we transmit back (the only packet we ever transmit, F2.3):
 *   <deviceid>,SUCCESS,
 *
 * State message (X2: 2 probe groups / 16 commas; X4: 4 groups / 26):
 *   <deviceid>,<field1>,<units>,<field3>,
 *     [<state>,<temp_x10>,<alarm_armed>,<alarm_high>,<alarm_low>,] × N
 *   <billows>,<new_alarm>,
 *
 * Field semantics verified on air 2026-07-21 (x4-events-10min):
 *   - units: 1 → °F, else °C; temps are tenths of the ACTIVE unit and the
 *     alarm band is whole degrees of the active unit
 *   - state 3 → detached; the temp field FREEZES at the last reading
 *   - new_alarm is the TRAILING field, edge-triggered one packet per alarm
 *     event; <field3> (the reference's new_alarm) rests at 1, role unknown
 */
#ifndef SMOKE_X_PARSER_H
#define SMOKE_X_PARSER_H

#include <stddef.h>

#include "smoke_x_types.h"

#ifdef __cplusplus
extern "C" {
#endif

#define SMOKE_X_PARSER_NUM_COMMAS_SYNC 6
#define SMOKE_X_PARSER_NUM_COMMAS_SUCCESS 2
#define SMOKE_X_PARSER_NUM_COMMAS_X2 16
#define SMOKE_X_PARSER_NUM_COMMAS_X4 26

/* Longest valid payload; larger inputs are rejected, not truncated. */
#define SMOKE_X_PARSER_MAX_PAYLOAD 128

/* Count comma occurrences; discriminates sync vs X2 vs X4 messages. */
unsigned int smoke_x_parser_count_commas(const char *msg);

/* 16 commas → 2, 26 → 4, anything else → 0. The probe count is learned
 * from the first state message, never from the sync (F3.6). */
unsigned int smoke_x_parser_probes_for_commas(unsigned int commas);

/* Returns 0 on success, -1 on any missing/malformed field. The frequency
 * still needs range-checking by the caller before use (F2.3). */
int smoke_x_parser_parse_sync(const char *msg, smoke_x_sync_t *out);

/* Parse a state message with the given probe count (2 or 4). Returns 0 on
 * success, -1 on malformed input, wrong field count, or a non-numeric
 * field. Detached probes read SMOKE_X_TEMP_DETACHED, never a number. */
int smoke_x_parser_parse_state(const char *msg, unsigned int num_probes,
                               smoke_x_state_t *out);

/* Format "<device_id>,SUCCESS," into buf. Returns bytes written (excluding
 * NUL), or -1 on invalid input / insufficient buffer. */
int smoke_x_parser_format_success(const char *device_id, char *buf,
                                  size_t buf_size);

#ifdef __cplusplus
}
#endif

#endif /* SMOKE_X_PARSER_H */
