# ble_service - NimBLE GATT server, advertising and security (M2).
# Stub only in T04.
idf_component_register(
    SRCS "ble_service.c"
    INCLUDE_DIRS "include"
    REQUIRES esp_common
    PRIV_REQUIRES log
)
