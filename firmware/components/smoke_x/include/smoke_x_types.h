/* smoke_x_types.h — plain data types for the Smoke X protocol layer.
 *
 * Derived from smoke-x-receiver (MIT © 2022 G-Two), extended for the X4
 * evidence captured in protocol/fixtures/lora/x4-events-10min.loralog.
 * Pure C11, no ESP-IDF headers: everything here builds in the host suite.
 */
#ifndef SMOKE_X_TYPES_H
#define SMOKE_X_TYPES_H

#include <stdbool.h>
#include <stdint.h>

#define SMOKE_X_DEVICE_ID_LEN 8
#define SMOKE_X_MAX_PROBES 4

/* Temperature sentinels (design 04 §4.2). A detached probe must be
 * structurally incapable of surfacing as 0 — the X4 freezes the last
 * reading in the temp field when a probe detaches (x4-events-10min), so
 * trusting the field without the state would draw a flat line forever. */
#define SMOKE_X_TEMP_DETACHED INT16_MIN
#define SMOKE_X_TEMP_INVALID (INT16_MIN + 1)

/* Wire value 1 is °F, otherwise °C — confirmed live by the °F↔°C flip in
 * the real capture. An explicit enum, not a string pointer: the reference
 * detects unit changes by pointer identity, which is a refactoring trap
 * (F3.3). */
typedef enum {
    SMOKE_X_UNITS_C = 0,
    SMOKE_X_UNITS_F = 1,
} smoke_x_units_t;

typedef struct {
    char field0[SMOKE_X_DEVICE_ID_LEN]; /* Q2: "020001" (X2 docs), "000000"
                                           observed from a real X4 */
    char device_id[SMOKE_X_DEVICE_ID_LEN]; /* NUL-terminated */
    uint32_t frequency;                    /* Hz; caller validates range */
} smoke_x_sync_t;

typedef struct {
    uint8_t state;     /* raw wire value; 3 = detached */
    bool attached;     /* state != 3 */
    bool alarm_armed;  /* an alarm band is set on this probe */
    int16_t temp_x10;  /* tenths of the active unit;
                          SMOKE_X_TEMP_DETACHED when detached */
    int16_t alarm_high; /* whole degrees, active unit; overloaded as the
                           Billows target when billows_attached (D11) */
    int16_t alarm_low;  /* whole degrees, active unit */
} smoke_x_probe_t;

typedef struct {
    char device_id[SMOKE_X_DEVICE_ID_LEN]; /* captured, not discarded: two
                                              units in range must not
                                              interleave (F3.4) */
    uint8_t num_probes;                    /* 2 or 4 */
    uint8_t hdr_field1;                    /* Q1: only 30 observed */
    smoke_x_units_t units;
    uint8_t hdr_field3; /* role unknown — rests at 1, moves to 2 around
                           alarm/menu activity (x4-events-10min) */
    bool billows_attached;
    bool new_alarm; /* trailing field: pulses for exactly one packet per
                       alarm event (edge-triggered — Q8 answered by the
                       real capture; the reference read header field 3,
                       which on a real X4 rests at 1) */
    smoke_x_probe_t probes[SMOKE_X_MAX_PROBES];
} smoke_x_state_t;

#endif /* SMOKE_X_TYPES_H */
