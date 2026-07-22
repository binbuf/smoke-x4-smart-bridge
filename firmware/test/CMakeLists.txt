cmake_minimum_required(VERSION 3.16)
project(smoke_bridge_host_tests C)

# Host unit tests: plain CMake + CTest, no ESP-IDF, no hardware (design 10
# §10.5, following the reference's test/CMakeLists.txt pattern). Runs in
# seconds with nothing beyond gcc and cmake.

set(CMAKE_C_STANDARD 11)
set(CMAKE_C_STANDARD_REQUIRED ON)

add_compile_options(-Wall -Wextra -Werror)

enable_testing()

set(REPO_ROOT ${CMAKE_CURRENT_SOURCE_DIR}/../..)

# Record codec: generated header + shared golden vectors (P1.2 / P1.5).
add_executable(test_record_gen test_record_gen.c)
target_include_directories(test_record_gen PRIVATE ${REPO_ROOT}/protocol/gen)
target_compile_definitions(test_record_gen PRIVATE
    FIXTURES_DIR="${REPO_ROOT}/protocol/fixtures/records"
)
add_test(NAME record_gen COMMAND test_record_gen)

# The committed cookgen fixture, validated through the generated codec (T2.3).
add_executable(test_smk_fixture test_smk_fixture.c)
target_include_directories(test_smk_fixture PRIVATE ${REPO_ROOT}/protocol/gen)
target_compile_definitions(test_smk_fixture PRIVATE
    SMK_FIXTURE="${REPO_ROOT}/protocol/fixtures/brisket-18h.smk"
)
add_test(NAME smk_fixture COMMAND test_smk_fixture)

# Event-bus handler duration guard (F1.3).
add_executable(test_bridge_event_guard
    test_bridge_event_guard.c
    ${CMAKE_CURRENT_SOURCE_DIR}/../components/bridge_event/bridge_event_guard.c
)
target_include_directories(test_bridge_event_guard PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}/../components/bridge_event/include
)
add_test(NAME bridge_event_guard COMMAND test_bridge_event_guard)

# Boot sequence + double-reset token (F1.5).
add_executable(test_boot_seq
    test_boot_seq.c
    ${CMAKE_CURRENT_SOURCE_DIR}/../main/boot_seq.c
    ${CMAKE_CURRENT_SOURCE_DIR}/../main/double_reset.c
)
target_include_directories(test_boot_seq PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}/../main
)
add_test(NAME boot_seq COMMAND test_boot_seq)

# Task table invariants (F1.4).
add_executable(test_tasks_table test_tasks_table.c)
target_include_directories(test_tasks_table PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}/../main
)
add_test(NAME tasks_table COMMAND test_tasks_table)
