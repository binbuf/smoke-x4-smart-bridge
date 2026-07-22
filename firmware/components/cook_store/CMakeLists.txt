idf_component_register(
    SRCS "cook_store.c"
    INCLUDE_DIRS "include"
)

# Our code builds warning-clean; IDF components are not our battle.
target_compile_options(${COMPONENT_LIB} PRIVATE -Wall -Wextra -Werror)
