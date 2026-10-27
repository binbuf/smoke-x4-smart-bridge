# bridge_state - live snapshot, clock and counters (T20).
# bridge_state.c is plain C11 (host-testable); bridge_state_esp.c installs the
# ESP timer. Anchor persistence goes through bridge_config, never raw NVS.
idf_component_register(
    SRCS "bridge_state.c" "bridge_state_esp.c"
    INCLUDE_DIRS "include"
    REQUIRES esp_common bridge_config protocol_gen
    PRIV_REQUIRES esp_timer
)
