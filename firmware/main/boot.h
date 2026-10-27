/*
 * boot.h - ordered, failure-tolerant boot sequence (design 03 section 3.4).
 */
#ifndef SX4_BOOT_H
#define SX4_BOOT_H

#ifdef __cplusplus
extern "C" {
#endif

/* Runs the boot sequence. NVS failure is fatal; every later step logs and is
 * skipped on failure so the bridge can still record/display where possible. */
void sx4_boot_run(void);

#ifdef __cplusplus
}
#endif

#endif /* SX4_BOOT_H */
