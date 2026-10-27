# sx_protocol - pure parser and record conversion (T14). Stub only in T04.
idf_component_register(
    SRCS "sx_protocol.c"
    INCLUDE_DIRS "include"
    REQUIRES esp_common
    PRIV_REQUIRES log
)
