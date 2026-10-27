/*
 * bridge_config.h - the only owner of the bridge NVS namespaces (design 03
 * section 3.7). T04 skeleton: load hook only.
 */
#ifndef SX4_BRIDGE_CONFIG_H
#define SX4_BRIDGE_CONFIG_H

#include "esp_err.h"

#ifdef __cplusplus
extern "C" {
#endif

/* Load config, pairing and counters from NVS. Requires nvs_flash_init(). */
esp_err_t bridge_config_init(void);

#ifdef __cplusplus
}
#endif

#endif /* SX4_BRIDGE_CONFIG_H */
