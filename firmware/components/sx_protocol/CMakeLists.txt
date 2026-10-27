# sx_protocol - pure parser and canonical sample conversion (T14).
# sx_protocol.c is plain C11 with no heap; firmware/test links it directly.
# The only ESP-IDF code is the #ifdef ESP_PLATFORM init hook.
idf_component_register(
    SRCS "sx_protocol.c"
    INCLUDE_DIRS "include"
    REQUIRES esp_common
    PRIV_REQUIRES log
)
