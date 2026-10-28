# ble_service - NimBLE GATT server, advertising and security (M2).
# T27 registers the service and serves `info`; T28 adds the live encoder,
# notification ring and the ble_tx writer; advertising/security are T30.
idf_component_register(
    SRCS "ble_service.c" "ble_info.c" "ble_live.c" "ble_control.c"
         "ble_adv.c" "ble_security.c" "ble_gatt_spec.c" "ble_tx_core.c"
         "ble_tx.c" "ble_sync.c" "ble_config.c" "ble_stats.c"
    INCLUDE_DIRS "include"
    REQUIRES bt bridge_config bridge_state protocol_gen sample_log
    PRIV_REQUIRES board log
)
