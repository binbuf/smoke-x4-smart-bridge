idf_component_register(
    SRCS "smoke_x.c" "smoke_x_parser.c" "smoke_x_ctrl.c" "smoke_x_pktring.c"
         "smoke_x_novelty.c"
    INCLUDE_DIRS "include" "../../../protocol/gen"
    PRIV_REQUIRES app_config app_lora bridge_event esp_timer
)

# Our code builds warning-clean; IDF components are not our battle.
target_compile_options(${COMPONENT_LIB} PRIVATE -Wall -Wextra -Werror)
