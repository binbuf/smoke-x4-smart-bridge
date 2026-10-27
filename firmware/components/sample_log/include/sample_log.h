/*
 * sample_log.h - raw sample-ring lifecycle (design 03 sections 3.4, 3.6).
 * T04 skeleton: mount/recovery hook only. The geometry (T18) and flash adapter
 * (T19) land later; the byte seam is include/log_io.h.
 */
#ifndef SX4_SAMPLE_LOG_H
#define SX4_SAMPLE_LOG_H

#include "esp_err.h"

#ifdef __cplusplus
extern "C" {
#endif

/* Mount the raw `samples` partition and recover the ring. Failure is not fatal:
 * the bridge reports "storage unavailable" and keeps showing live values. */
esp_err_t sample_log_init(void);

#ifdef __cplusplus
}
#endif

#endif /* SX4_SAMPLE_LOG_H */
