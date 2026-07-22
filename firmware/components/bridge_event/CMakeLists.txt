idf_component_register(
    SRCS "bridge_event.c" "bridge_event_guard.c"
    INCLUDE_DIRS "include"
    PRIV_REQUIRES esp_event esp_timer
)
