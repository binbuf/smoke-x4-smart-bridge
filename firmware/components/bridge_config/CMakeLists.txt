# bridge_config - typed NVS config, pairing and bond metadata (T15).
# Stub only in T04.
idf_component_register(
    SRCS "bridge_config.c"
    INCLUDE_DIRS "include"
    REQUIRES esp_common
    PRIV_REQUIRES log
)
