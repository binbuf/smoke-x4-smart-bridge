idf_component_register(
    SRCS "app_ui.c" "app_ui_fb.c" "app_ui_font.c" "app_ui_render.c"
         "app_ui_panel.c" "app_ui_input.c" "app_ui_model.c" "app_ui_led.c"
         "app_ui_cook.c"
    INCLUDE_DIRS "include" "../../../protocol/gen"
    REQUIRES bridge_event
    PRIV_REQUIRES app_alarm app_config app_net app_power cook_store smoke_x
                  esp_driver_gpio esp_driver_i2c esp_driver_ledc esp_timer
                  esp_app_format esp_system
)

# Our code builds warning-clean; IDF components are not our battle.
target_compile_options(${COMPONENT_LIB} PRIVATE -Wall -Wextra -Werror)
