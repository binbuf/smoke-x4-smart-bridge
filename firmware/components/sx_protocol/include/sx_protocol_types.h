/*
 * sx_protocol_types.h - plain data types for the Smoke X protocol layer.
 *
 * Shape carried over from legacy/firmware/components/smoke_x/include/
 * smoke_x_types.h, itself derived from smoke-x-receiver (MIT (c) 2022 G-Two)
 * and extended for the X4 evidence captured in protocol/fixtures/lora/.
 *
 * Pure C11: no ESP-IDF headers, so the host suite compiles the same structs.
 * Units are explicit in every field name: `_f10` is tenths of a degree
 * Fahrenheit, `_deg` is a whole degree in the message's active unit (see
 * sx_protocol_state_t.units).
 */
#ifndef SX4_SX_PROTOCOL_TYPES_H
#define SX4_SX_PROTOCOL_TYPES_H

#include <stdbool.h>
#include <stdint.h>

#define SX_PROTOCOL_DEVICE_ID_LEN 8 /* 7 wire chars + NUL */
#define SX_PROTOCOL_MAX_PROBES 4

/* Temperature sentinels (design 04 section 4.2). A detached probe reads
 * SX_PROTOCOL_TEMP_DETACHED, never the X4's frozen numeric field. */
#define SX_PROTOCOL_TEMP_DETACHED INT16_MIN
#define SX_PROTOCOL_TEMP_INVALID (INT16_MIN + 1)

/* Wire value 1 is degrees Fahrenheit; anything else is Celsius. */
typedef enum {
    SX_PROTOCOL_UNITS_CELSIUS = 0,
    SX_PROTOCOL_UNITS_FAHRENHEIT = 1,
} sx_protocol_units_t;

typedef struct {
    char field0[SX_PROTOCOL_DEVICE_ID_LEN]; /* diagnostic model code */
    char device_id[SX_PROTOCOL_DEVICE_ID_LEN]; /* NUL-terminated */
    uint32_t frequency_hz; /* caller validates 902-928 MHz */
} sx_protocol_sync_t;

typedef struct {
    uint8_t state;      /* raw wire value; 3 = detached */
    bool attached;      /* state != 3 */
    bool alarm_armed;   /* an alarm band is set on the Smoke X */
    int16_t temp_f10;   /* canonical tenths of a degree F, or TEMP_DETACHED */
    int16_t alarm_high_deg; /* whole degrees in the message's active unit */
    int16_t alarm_low_deg;  /* whole degrees in the message's active unit */
} sx_protocol_probe_t;

typedef struct {
    char device_id[SX_PROTOCOL_DEVICE_ID_LEN]; /* captured, then matched */
    uint8_t num_probes; /* 4 (X4) or 2 (X2 defensive) */
    uint8_t hdr_field1; /* diagnostic only; only 30 observed */
    sx_protocol_units_t units; /* wire units of this packet */
    bool source_celsius; /* provenance: true when the wire unit was C */
    uint8_t hdr_field3;  /* diagnostic only; role unknown */
    bool billows_attached;
    bool new_alarm; /* trailing edge-triggered field; preserved, unused */

    /* Billows target candidate: probe 4 `max` while billows_attached is
     * set, in `billows_target_units`. The max <-> target relation is not
     * validated until M5, so consumers must show a target only when
     * billows_target_valid is true. It stays false in the MVP parser. */
    int16_t billows_target_deg;
    sx_protocol_units_t billows_target_units;
    bool billows_target_valid;

    sx_protocol_probe_t probes[SX_PROTOCOL_MAX_PROBES];
} sx_protocol_state_t;

typedef struct {
    uint32_t valid_state_packets;
    uint32_t parse_failures; /* malformed state or sync payloads */
    uint32_t crc_failures;   /* radio-reported CRC/header errors (T13 hook) */
    uint32_t foreign_device_packets;
    uint32_t sync_beacons;
    uint32_t ack_attempts;
} sx_protocol_counters_t;

#endif /* SX4_SX_PROTOCOL_TYPES_H */
