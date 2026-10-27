# sample_log - pure ring core + boot recovery + IDF flash adapter (T17/T18/T19).
# host seam include/log_io.h committed T03 and must stay pure C. The recovery
# core (log_flash_core.c) is plain C11; log_flash.c is the raw-partition adapter.
idf_component_register(
    SRCS "sample_log.c" "log_core.c" "log_flash.c" "log_flash_core.c"
    INCLUDE_DIRS "include"
    REQUIRES esp_common protocol_gen
    PRIV_REQUIRES log esp_partition esp_timer bridge_config
)
