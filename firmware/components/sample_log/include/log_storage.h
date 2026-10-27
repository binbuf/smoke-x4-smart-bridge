/*
 * log_storage.h - storage state shared by the sample log, UI and stats (T19).
 *
 * Pure C11 so the boot-recovery core and host tests can use it without
 * ESP-IDF. Definitions live in design 03 section 3.5.4 and design 07.
 */
#ifndef SX4_LOG_STORAGE_H
#define SX4_LOG_STORAGE_H

#include "log_core.h"

#ifdef __cplusplus
extern "C" {
#endif

typedef enum {
    SAMPLE_LOG_STORAGE_OK = 0,
    SAMPLE_LOG_STORAGE_NEAR_FULL = 1,
    SAMPLE_LOG_STORAGE_READ_ONLY = 2,
} sample_log_storage_state_t;

/* "Near full" boundary: one sector of capacity remains. */
#define SAMPLE_LOG_NEAR_FULL_RECORDS \
    (SAMPLE_LOG_CAPACITY_RECORDS - SAMPLE_LOG_RECORDS_PER_SECTOR)

#ifdef __cplusplus
}
#endif

#endif /* SX4_LOG_STORAGE_H */
