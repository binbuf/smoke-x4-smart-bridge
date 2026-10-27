/*
 * sx_protocol.h - payload parser and sample conversion (design 03 section 3.6).
 * T04 skeleton: init hook only. The pure-C parser and record conversion land
 * with T14 and must stay buildable in firmware/test without ESP-IDF.
 */
#ifndef SX4_SX_PROTOCOL_H
#define SX4_SX_PROTOCOL_H

#include "esp_err.h"

#ifdef __cplusplus
extern "C" {
#endif

/* Build static validation tables. No allocation, no I/O. */
esp_err_t sx_protocol_init(void);

#ifdef __cplusplus
}
#endif

#endif /* SX4_SX_PROTOCOL_H */
