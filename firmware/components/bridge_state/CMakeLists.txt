# bridge_state - live snapshot, clock and counters (T20). Stub only in T04.
idf_component_register(
    SRCS "bridge_state.c"
    INCLUDE_DIRS "include"
    REQUIRES esp_common
    PRIV_REQUIRES log
)
