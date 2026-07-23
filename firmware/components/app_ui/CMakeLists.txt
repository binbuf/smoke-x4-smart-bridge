idf_component_register(
    SRCS "app_ui.c" "app_ui_fb.c" "app_ui_font.c" "app_ui_render.c"
         "app_ui_panel.c"
    INCLUDE_DIRS "include"
    REQUIRES bridge_event
    PRIV_REQUIRES esp_driver_gpio esp_driver_i2c
)

# Our code builds warning-clean; IDF components are not our battle.
target_compile_options(${COMPONENT_LIB} PRIVATE -Wall -Wextra -Werror)
