/* app_config — NVS-backed typed configuration (design 03 §3.6).
 *
 * The typed API lives in app_config_store.h; this header only carries the
 * device-side entry point. No other component opens NVS directly. */
#ifndef APP_CONFIG_H
#define APP_CONFIG_H

#include "app_config_store.h"

#ifdef __cplusplus
extern "C" {
#endif

/* Wires the NVS backend into the store, runs migrations, and generates the
 * AP PSK on first boot. NVS itself must already be initialised (boot step 3).
 * Returns APP_CONFIG_OK on success. */
int app_config_init(void);

#ifdef __cplusplus
}
#endif

#endif /* APP_CONFIG_H */
