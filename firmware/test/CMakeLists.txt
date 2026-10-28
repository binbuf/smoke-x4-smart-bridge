cmake_minimum_required(VERSION 3.16)
project(sx4_host_tests C)

# Plain host test project: gcc/clang + CMake + CTest only. No ESP-IDF, no
# network, no board. The protocol codec and every pure-C component linked here
# must stay buildable with a bare C11 toolchain (design 03 section 3.1).

set(CMAKE_C_STANDARD 11)
set(CMAKE_C_STANDARD_REQUIRED ON)
set(CMAKE_C_EXTENSIONS OFF)

if(CMAKE_C_COMPILER_ID MATCHES "GNU|Clang")
    add_compile_options(-Wall -Wextra -Werror)
endif()

enable_testing()

get_filename_component(REPO_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/../.." ABSOLUTE)
file(TO_CMAKE_PATH "${REPO_ROOT}/protocol/fixtures/lora" SX4_LORA_FIXTURES)

# Generated protocol codecs are committed (T02) and are the first pure-C
# component the harness links. Later tasks add sx_protocol/sample_log sources
# to this build rather than introducing an ESP-IDF dependency.
add_library(sx4_protocol_gen STATIC "${REPO_ROOT}/protocol/gen/records.c")
target_include_directories(sx4_protocol_gen
    PUBLIC "${REPO_ROOT}/protocol/gen"
)

# sample_log's record codec (T17) is plain C11 over the generated record bytes:
# it adds explicit record_size and the sentinel/attach-bit consistency rules.
add_library(sx4_sample_log_core STATIC
    "${REPO_ROOT}/firmware/components/sample_log/log_core.c"
)
target_include_directories(sx4_sample_log_core
    PUBLIC "${REPO_ROOT}/firmware/components/sample_log/include"
)
target_link_libraries(sx4_sample_log_core PUBLIC sx4_protocol_gen)

add_executable(test_sample_log_rec test_sample_log_rec.c)
target_link_libraries(test_sample_log_rec PRIVATE sx4_sample_log_core)
add_test(NAME sample-log-rec COMMAND test_sample_log_rec)

# The ring core (T18) is the same log_core.c over a RAM log_io fake.
add_executable(test_sample_log_ring test_sample_log_ring.c)
target_link_libraries(test_sample_log_ring
    PRIVATE sx4_sample_log_core sx4_test_support
)
add_test(NAME sample-log-ring COMMAND test_sample_log_ring)

# The boot recovery/clear policy (T19) is plain C over log_io + an NVS hook
# seam. Host tests inject a RAM partition and in-memory NVS; the firmware links
# the esp_partition adapter in log_flash.c.
add_library(sx4_sample_log_flash STATIC
    "${REPO_ROOT}/firmware/components/sample_log/log_flash_core.c"
)
target_include_directories(sx4_sample_log_flash
    PUBLIC "${REPO_ROOT}/firmware/components/sample_log/include"
)
target_link_libraries(sx4_sample_log_flash PUBLIC sx4_sample_log_core)

add_executable(test_sample_log_flash test_sample_log_flash.c)
target_link_libraries(test_sample_log_flash
    PRIVATE sx4_sample_log_flash sx4_test_support
)
add_test(NAME sample-log-flash COMMAND test_sample_log_flash)

# Shared test-only support: assertions, corpus readers, RAM log_io fake.
add_library(sx4_test_support STATIC
    support/test_util.c
    support/lora_corpus.c
    support/ram_log_io.c
)
target_include_directories(sx4_test_support
    PUBLIC
        "${CMAKE_CURRENT_SOURCE_DIR}/support"
        "${REPO_ROOT}/firmware/components/sample_log/include"
)

# Codec coverage already lives in protocol/test. Alias it here so `ctest` is the
# single host entry point; do not duplicate the test source.
add_executable(test_records "${REPO_ROOT}/protocol/test/test_records.c")
target_link_libraries(test_records PRIVATE sx4_protocol_gen)
add_test(NAME records COMMAND test_records)

add_executable(test_lora_corpus test_lora_corpus.c)
target_link_libraries(test_lora_corpus PRIVATE sx4_test_support)
target_compile_definitions(test_lora_corpus PRIVATE
    SX4_FIXTURE_DIR="${SX4_LORA_FIXTURES}"
)
add_test(NAME lora-corpus COMMAND test_lora_corpus)

add_executable(test_log_io_ram test_log_io_ram.c)
target_link_libraries(test_log_io_ram PRIVATE sx4_test_support)
add_test(NAME log-io-ram COMMAND test_log_io_ram)

# sx_radio's seam and parameter block are pure C (T13). No ESP-IDF or radio is
# linked: the test injects a payload and takes it back from the parser seam.
add_library(sx4_radio_core STATIC
    "${REPO_ROOT}/firmware/components/sx_radio/sx_radio_rx.c"
)
target_include_directories(sx4_radio_core
    PUBLIC "${REPO_ROOT}/firmware/components/sx_radio/include"
)

add_executable(test_sx_radio_rx test_sx_radio_rx.c)
target_link_libraries(test_sx_radio_rx PRIVATE sx4_radio_core sx4_test_support)
target_compile_definitions(test_sx_radio_rx PRIVATE
    SX4_FIXTURE_DIR="${SX4_LORA_FIXTURES}"
)
add_test(NAME sx-radio-rx COMMAND test_sx_radio_rx)

# sx_protocol is pure C: the parser compiled here is the same source the
# firmware links, with no ESP-IDF includes (see the #ifdef ESP_PLATFORM init).
add_library(sx4_sx_protocol STATIC
    "${REPO_ROOT}/firmware/components/sx_protocol/sx_protocol.c"
)
target_include_directories(sx4_sx_protocol
    PUBLIC "${REPO_ROOT}/firmware/components/sx_protocol/include"
)

add_executable(test_sx_protocol test_sx_protocol.c)
target_link_libraries(test_sx_protocol PRIVATE sx4_sx_protocol sx4_test_support)
target_compile_definitions(test_sx_protocol PRIVATE
    SX4_FIXTURE_DIR="${SX4_LORA_FIXTURES}"
)
add_test(NAME sx-protocol COMMAND test_sx_protocol)

# The pairing FSM is pure C over radio/NVS/time callback seams (T16). The host
# test uses RAM/radio fakes; no ESP-IDF and no board.
add_library(sx4_radio_pair STATIC
    "${REPO_ROOT}/firmware/components/sx_radio/sx_radio_pair.c"
)
target_include_directories(sx4_radio_pair
    PUBLIC "${REPO_ROOT}/firmware/components/sx_radio/include"
)
target_link_libraries(sx4_radio_pair PUBLIC sx4_sx_protocol sx4_radio_core)

add_executable(test_sx_radio_pair test_sx_radio_pair.c)
target_link_libraries(test_sx_radio_pair
    PRIVATE sx4_radio_pair sx4_test_support
)
target_compile_definitions(test_sx_radio_pair PRIVATE
    SX4_RADIO_SRC_DIR="${REPO_ROOT}/firmware/components/sx_radio"
)
add_test(NAME sx-radio-pair COMMAND test_sx_radio_pair)

# bridge_config's core is plain C11 over a byte-oriented KV seam; the host
# test supplies a RAM backend, the firmware links the NVS adapter.
add_library(sx4_bridge_config STATIC
    "${REPO_ROOT}/firmware/components/bridge_config/bridge_config.c"
)
target_include_directories(sx4_bridge_config
    PUBLIC "${REPO_ROOT}/firmware/components/bridge_config/include"
)

add_executable(test_bridge_config test_bridge_config.c)
target_link_libraries(test_bridge_config
    PRIVATE sx4_bridge_config sx4_test_support
)
add_test(NAME bridge-config COMMAND test_bridge_config)

# bridge_state's clock/snapshot core is plain C11. It persists the anchor
# through bridge_config and takes time from an injected monotonic source.
add_library(sx4_bridge_state STATIC
    "${REPO_ROOT}/firmware/components/bridge_state/bridge_state.c"
)
target_include_directories(sx4_bridge_state
    PUBLIC "${REPO_ROOT}/firmware/components/bridge_state/include"
)
target_link_libraries(sx4_bridge_state
    PUBLIC sx4_bridge_config sx4_protocol_gen
)

add_executable(test_bridge_state test_bridge_state.c)
target_link_libraries(test_bridge_state
    PRIVATE sx4_bridge_state sx4_test_support
)
add_test(NAME bridge-state COMMAND test_bridge_state)

# The battery divider curve and power-stats accumulator are pure C11 (T24).
# The GPIO37/ADC/calibration half stays in board_battery_esp.c and is not linked
# here; the board reading is checked against a DMM in T62.
add_library(sx4_board_battery STATIC
    "${REPO_ROOT}/firmware/components/board/board_battery.c"
)
target_include_directories(sx4_board_battery
    PUBLIC "${REPO_ROOT}/firmware/components/board/include"
)

add_executable(test_board_battery test_board_battery.c)
target_link_libraries(test_board_battery
    PRIVATE sx4_board_battery sx4_test_support
)
add_test(NAME board-battery COMMAND test_board_battery)

# sample_pipe's core is plain C11. It links the real parser and record codec;
# the test fixture supplies the ring, pairing store and UI-dirty callbacks.
add_library(sx4_sample_pipe STATIC
    "${REPO_ROOT}/firmware/components/sample_pipe/sample_pipe.c"
)
target_include_directories(sx4_sample_pipe
    PUBLIC "${REPO_ROOT}/firmware/components/sample_pipe/include"
)
target_link_libraries(sx4_sample_pipe
    PUBLIC sx4_sample_log_core sx4_sx_protocol
)
target_include_directories(sx4_sample_pipe
    PUBLIC
        "${REPO_ROOT}/firmware/components/bridge_state/include"
        "${REPO_ROOT}/firmware/components/sx_protocol/include"
)

add_executable(test_sample_pipe test_sample_pipe.c)
target_link_libraries(test_sample_pipe PRIVATE sx4_sample_pipe sx4_test_support)
target_compile_definitions(test_sample_pipe PRIVATE
    SX4_FIXTURE_DIR="${SX4_LORA_FIXTURES}"
)
# The replay asserts that the sample path performs no heap allocation. GNU ld
# and lld support --wrap; Apple's linker does not, so the assertion is compiled
# out there (the firmware path still has no allocator call).
if(CMAKE_C_COMPILER_ID MATCHES "GNU|Clang" AND NOT APPLE)
    target_link_options(test_sample_pipe PRIVATE
        -Wl,--wrap=malloc
        -Wl,--wrap=calloc
        -Wl,--wrap=realloc
        -Wl,--wrap=free
    )
    target_compile_definitions(test_sample_pipe PRIVATE SX4_ALLOC_WRAPPED=1)
endif()
add_test(NAME sample-pipe COMMAND test_sample_pipe)

# ble_service's wire encoders and GATT slot table are pure C11 (T27). The
# NimBLE callbacks are not linked here; the byte vectors and the table are the
# host gate.
add_library(sx4_ble_info STATIC
    "${REPO_ROOT}/firmware/components/ble_service/ble_info.c"
    "${REPO_ROOT}/firmware/components/ble_service/ble_gatt_spec.c"
)
target_include_directories(sx4_ble_info
    PUBLIC "${REPO_ROOT}/firmware/components/ble_service/include"
)
target_link_libraries(sx4_ble_info PUBLIC sx4_protocol_gen)

add_executable(test_ble_info test_ble_info.c)
target_link_libraries(test_ble_info PRIVATE sx4_ble_info sx4_test_support)
add_test(NAME ble-info COMMAND test_ble_info)

# The `live` encoder and the bounded ble_tx ring are pure C11 (T28). The
# NimBLE callbacks are not linked; the 05 section 5.4 vector, the required
# snapshot states and the queue semantics are the host gate.
add_library(sx4_ble_live STATIC
    "${REPO_ROOT}/firmware/components/ble_service/ble_live.c"
    "${REPO_ROOT}/firmware/components/ble_service/ble_tx_core.c"
)
target_include_directories(sx4_ble_live
    PUBLIC "${REPO_ROOT}/firmware/components/ble_service/include"
)
target_link_libraries(sx4_ble_live
    PUBLIC sx4_bridge_state sx4_protocol_gen
)

add_executable(test_ble_live test_ble_live.c)
target_link_libraries(test_ble_live PRIVATE sx4_ble_live sx4_test_support)
add_test(NAME ble-live COMMAND test_ble_live)

# The control dispatcher and result encoder are pure C11 over the real
# bridge_state clock core (T29). NimBLE is not linked; the ATT error values,
# every status code, body validation and result truncation are the host gate.
add_library(sx4_ble_control STATIC
    "${REPO_ROOT}/firmware/components/ble_service/ble_control.c"
)
target_include_directories(sx4_ble_control
    PUBLIC "${REPO_ROOT}/firmware/components/ble_service/include"
)
target_link_libraries(sx4_ble_control
    PUBLIC sx4_bridge_state sx4_protocol_gen
)

add_executable(test_ble_control test_ble_control.c)
target_link_libraries(test_ble_control PRIVATE sx4_ble_control sx4_test_support)
add_test(NAME ble-control COMMAND test_ble_control)

# T48: the deferred destructive-action router. The real dispatcher is linked;
# the backend is a fake, so ordering/idempotency/failure are host-provable
# without NimBLE, NVS, flash or the board.
add_library(sx4_ble_control_actions STATIC
    "${REPO_ROOT}/firmware/components/ble_service/ble_control_actions.c"
)
target_include_directories(sx4_ble_control_actions
    PUBLIC "${REPO_ROOT}/firmware/components/ble_service/include"
)
target_link_libraries(sx4_ble_control_actions PUBLIC sx4_ble_control)

add_executable(test_ble_control_actions test_ble_control_actions.c)
target_link_libraries(test_ble_control_actions
    PRIVATE sx4_ble_control_actions sx4_test_support
)
add_test(NAME ble-control-actions COMMAND test_ble_control_actions)

# The `config` validator/encoder is pure C11 (T47). bridge_config supplies the
# shared name/timeout constants; the host test does not touch NVS.
add_library(sx4_ble_config STATIC
    "${REPO_ROOT}/firmware/components/ble_service/ble_config.c"
)
target_include_directories(sx4_ble_config
    PUBLIC "${REPO_ROOT}/firmware/components/ble_service/include"
)
target_link_libraries(sx4_ble_config
    PUBLIC sx4_bridge_config sx4_protocol_gen
)

add_executable(test_ble_config test_ble_config.c)
target_link_libraries(test_ble_config PRIVATE sx4_ble_config sx4_test_support)
add_test(NAME ble-config COMMAND test_ble_config)

# The `stats` encoder is pure C11 (T47); the firmware snapshot gathering lives
# in ble_service.c and is not linked here.
add_library(sx4_ble_stats STATIC
    "${REPO_ROOT}/firmware/components/ble_service/ble_stats.c"
)
target_include_directories(sx4_ble_stats
    PUBLIC "${REPO_ROOT}/firmware/components/ble_service/include"
)
target_link_libraries(sx4_ble_stats PUBLIC sx4_protocol_gen)

add_executable(test_ble_stats test_ble_stats.c)
target_link_libraries(test_ble_stats PRIVATE sx4_ble_stats sx4_test_support)
add_test(NAME ble-stats COMMAND test_ble_stats)

# sync_ctrl parsing, the logical START/RECORDS/END stream and the MTU-bounded
# sync_data framer are pure C11 (T31). The test is a client-style reassembler:
# it covers MTU 23 (split START and split records), MTU 247, backward/forward
# cursors, status/empty and a dropped frame_seq.
add_library(sx4_ble_sync STATIC
    "${REPO_ROOT}/firmware/components/ble_service/ble_sync.c"
)
target_include_directories(sx4_ble_sync
    PUBLIC "${REPO_ROOT}/firmware/components/ble_service/include"
)
target_link_libraries(sx4_ble_sync PUBLIC sx4_protocol_gen)

add_executable(test_ble_sync test_ble_sync.c)
target_link_libraries(test_ble_sync PRIVATE sx4_ble_sync sx4_test_support)
add_test(NAME ble-sync COMMAND test_ble_sync)

# Advertising AD structures, the 250 ms -> 1,000 ms state machine, the bond
# limit and the passkey lifetime are pure C11 (T30). NimBLE is not linked; the
# byte vectors and the state transitions are the host gate.
add_library(sx4_ble_adv STATIC
    "${REPO_ROOT}/firmware/components/ble_service/ble_adv.c"
    "${REPO_ROOT}/firmware/components/ble_service/ble_security.c"
)
target_include_directories(sx4_ble_adv
    PUBLIC "${REPO_ROOT}/firmware/components/ble_service/include"
)

add_executable(test_ble_adv test_ble_adv.c)
target_link_libraries(test_ble_adv PRIVATE sx4_ble_adv sx4_test_support)
add_test(NAME ble-adv COMMAND test_ble_adv)

# T49: destructive-action link lifecycle and boot recovery. The real
# dispatcher/router, advertising state machine, factory-reset step table and
# boot-time log-clear policy are linked; the BLE/NVS/board backends are fakes.
add_library(sx4_ble_destructive STATIC
    "${REPO_ROOT}/firmware/components/ble_service/ble_destructive.c"
)
target_include_directories(sx4_ble_destructive
    PUBLIC "${REPO_ROOT}/firmware/components/ble_service/include"
)
target_link_libraries(sx4_ble_destructive PUBLIC sx4_ble_control)

add_executable(test_ble_destructive test_ble_destructive.c)
target_link_libraries(test_ble_destructive
    PRIVATE
        sx4_ble_destructive
        sx4_ble_adv
        sx4_ble_control_actions
        sx4_bridge_config
        sx4_sample_log_flash
        sx4_test_support
)
add_test(NAME ble-destructive COMMAND test_ble_destructive)


# tasks.h is pure C on purpose: the task table and its stack budget are checked
# without ESP-IDF, in addition to the _Static_assert compiled into the firmware.
add_executable(test_tasks
    test_tasks.c
    "${REPO_ROOT}/firmware/main/tasks.c"
)
target_include_directories(test_tasks PRIVATE "${REPO_ROOT}/firmware/main")
target_link_libraries(test_tasks PRIVATE sx4_test_support)
add_test(NAME task-budget COMMAND test_tasks)

# The OLED renderer, display-sleep state and SSD1306 transfer core are pure C11
# (T22). The host test compares the 1 KB page-ordered framebuffer against
# committed .fb goldens; the PNG tool is for human review only.
add_library(sx4_ui STATIC
    "${REPO_ROOT}/firmware/components/ui/ui_render.c"
    "${REPO_ROOT}/firmware/components/ui/ui_sleep.c"
    "${REPO_ROOT}/firmware/components/ui/ui_button.c"
    "${REPO_ROOT}/firmware/components/ui/ssd1306_core.c"
)
target_include_directories(sx4_ui
    PUBLIC "${REPO_ROOT}/firmware/components/ui/include"
)
add_executable(test_ui_render test_ui_render.c)
target_link_libraries(test_ui_render PRIVATE sx4_ui sx4_test_support)
target_compile_definitions(test_ui_render PRIVATE
    SX4_UI_GOLDEN_DIR="${REPO_ROOT}/firmware/test/goldens/ui"
)
add_test(NAME ui-render COMMAND test_ui_render)

# PRG gestures (tap/hold/cancel/wake-consumed) and the hold-to-wake boot
# confirmation are pure C with an injected clock (T23).
add_executable(test_ui_button test_ui_button.c)
target_link_libraries(test_ui_button PRIVATE sx4_ui sx4_test_support)
add_test(NAME ui-button COMMAND test_ui_button)
