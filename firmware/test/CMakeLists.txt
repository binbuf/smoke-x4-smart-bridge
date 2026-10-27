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

# tasks.h is pure C on purpose: the task table and its stack budget are checked
# without ESP-IDF, in addition to the _Static_assert compiled into the firmware.
add_executable(test_tasks
    test_tasks.c
    "${REPO_ROOT}/firmware/main/tasks.c"
)
target_include_directories(test_tasks PRIVATE "${REPO_ROOT}/firmware/main")
target_link_libraries(test_tasks PRIVATE sx4_test_support)
add_test(NAME task-budget COMMAND test_tasks)
