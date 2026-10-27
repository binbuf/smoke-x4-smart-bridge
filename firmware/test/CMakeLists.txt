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

# tasks.h is pure C on purpose: the task table and its stack budget are checked
# without ESP-IDF, in addition to the _Static_assert compiled into the firmware.
add_executable(test_tasks
    test_tasks.c
    "${REPO_ROOT}/firmware/main/tasks.c"
)
target_include_directories(test_tasks PRIVATE "${REPO_ROOT}/firmware/main")
target_link_libraries(test_tasks PRIVATE sx4_test_support)
add_test(NAME task-budget COMMAND test_tasks)
