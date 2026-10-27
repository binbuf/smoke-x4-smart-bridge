# ble_service - NimBLE GATT server, advertising and security (M2).
# T27 registers the service and serves `info`; advertising/security are T30.
idf_component_register(
    SRCS "ble_service.c" "ble_info.c" "ble_gatt_spec.c"
    INCLUDE_DIRS "include"
    REQUIRES bt bridge_config protocol_gen
    PRIV_REQUIRES log
)
