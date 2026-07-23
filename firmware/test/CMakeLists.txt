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

# Smoke X payload parser: reference seed corpus + real X4 vectors
# (F3.1–F3.5).
add_executable(test_smoke_x_parser
    test_smoke_x_parser.c
    ${CMAKE_CURRENT_SOURCE_DIR}/../components/smoke_x/smoke_x_parser.c
)
target_include_directories(test_smoke_x_parser PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}/../components/smoke_x/include
)
add_test(NAME smoke_x_parser COMMAND test_smoke_x_parser)

# cook_store write path + crash safety: torn-append recovery at every
# offset, retention, marks, fsync cadence (F5.1–F5.5, F5.7–F5.9).
add_executable(test_cook_store
    test_cook_store.c
    ${CMAKE_CURRENT_SOURCE_DIR}/../components/cook_store/cook_store_core.c
    ${CMAKE_CURRENT_SOURCE_DIR}/../components/app_config/app_config_store.c
)
target_include_directories(test_cook_store PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}/../components/cook_store/include
    ${CMAKE_CURRENT_SOURCE_DIR}/../components/app_config/include
    ${REPO_ROOT}/protocol/gen
)
add_test(NAME cook_store COMMAND test_cook_store)

# cook_store streaming read: buckets, spike survival, binary-search bound
# (F5.10).
add_executable(test_cook_read
    test_cook_read.c
    ${CMAKE_CURRENT_SOURCE_DIR}/../components/cook_store/cook_store_core.c
    ${CMAKE_CURRENT_SOURCE_DIR}/../components/app_config/app_config_store.c
)
target_include_directories(test_cook_read PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}/../components/cook_store/include
    ${CMAKE_CURRENT_SOURCE_DIR}/../components/app_config/include
    ${REPO_ROOT}/protocol/gen
)
add_test(NAME cook_read COMMAND test_cook_read)

# Live ring + slope, and the session lifecycle table (F5.4, F5.6).
add_executable(test_cook_ring_lifecycle
    test_cook_ring_lifecycle.c
    ${CMAKE_CURRENT_SOURCE_DIR}/../components/cook_store/cook_ring.c
    ${CMAKE_CURRENT_SOURCE_DIR}/../components/cook_store/cook_lifecycle.c
)
target_include_directories(test_cook_ring_lifecycle PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}/../components/cook_store/include
    ${REPO_ROOT}/protocol/gen
)
add_test(NAME cook_ring_lifecycle COMMAND test_cook_ring_lifecycle)

# Wi-Fi mode selection and STA supervision (F8.1–F8.3).
add_executable(test_app_net
    test_app_net.c
    ${CMAKE_CURRENT_SOURCE_DIR}/../components/app_net/app_net_core.c
)
target_include_directories(test_app_net PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}/../components/app_net/include
    ${CMAKE_CURRENT_SOURCE_DIR}/../components/app_config/include
)
add_test(NAME app_net COMMAND test_app_net)

# The parser against the whole committed capture corpus, real and
# adversarial (F3.8, T4.3).
add_executable(test_lora_corpus
    test_lora_corpus.c
    ${CMAKE_CURRENT_SOURCE_DIR}/../components/smoke_x/smoke_x_parser.c
)
target_include_directories(test_lora_corpus PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}/../components/smoke_x/include
)
target_compile_definitions(test_lora_corpus PRIVATE
    FIXTURES_LORA_DIR="${REPO_ROOT}/protocol/fixtures/lora"
)
add_test(NAME lora_corpus COMMAND test_lora_corpus)

# Deterministic full-stack replay of a real capture (T4.2).
add_executable(test_replay
    test_replay.c
    ${CMAKE_CURRENT_SOURCE_DIR}/../components/smoke_x/smoke_x_ctrl.c
    ${CMAKE_CURRENT_SOURCE_DIR}/../components/smoke_x/smoke_x_parser.c
    ${CMAKE_CURRENT_SOURCE_DIR}/../components/cook_store/cook_store_core.c
    ${CMAKE_CURRENT_SOURCE_DIR}/../components/cook_store/cook_lifecycle.c
    ${CMAKE_CURRENT_SOURCE_DIR}/../components/app_config/app_config_store.c
)
target_include_directories(test_replay PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}/../components/smoke_x/include
    ${CMAKE_CURRENT_SOURCE_DIR}/../components/cook_store/include
    ${CMAKE_CURRENT_SOURCE_DIR}/../components/app_config/include
    ${REPO_ROOT}/protocol/gen
)
target_compile_definitions(test_replay PRIVATE
    FIXTURES_LORA_DIR="${REPO_ROOT}/protocol/fixtures/lora"
)
add_test(NAME replay COMMAND test_replay)

# The persisted novelty ring: pinned evidence survives wrap + remount
# (F4.3).
add_executable(test_novelty_log
    test_novelty_log.c
    ${CMAKE_CURRENT_SOURCE_DIR}/../components/cook_store/cook_novelty_log.c
)
target_include_directories(test_novelty_log PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}/../components/cook_store/include
    ${CMAKE_CURRENT_SOURCE_DIR}/../components/app_config/include
    ${REPO_ROOT}/protocol/gen
)
add_test(NAME novelty_log COMMAND test_novelty_log)

# Radio params, scanner dwell, and the TX guard invariant (F2).
add_executable(test_app_lora
    test_app_lora.c
    ${CMAKE_CURRENT_SOURCE_DIR}/../components/app_lora/app_lora_core.c
    ${CMAKE_CURRENT_SOURCE_DIR}/../components/smoke_x/smoke_x_ctrl.c
    ${CMAKE_CURRENT_SOURCE_DIR}/../components/smoke_x/smoke_x_parser.c
    ${CMAKE_CURRENT_SOURCE_DIR}/../components/app_config/app_config_store.c
)
target_include_directories(test_app_lora PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}/../components/app_lora/include
    ${CMAKE_CURRENT_SOURCE_DIR}/../components/smoke_x/include
    ${CMAKE_CURRENT_SOURCE_DIR}/../components/app_config/include
)
add_test(NAME app_lora COMMAND test_app_lora)

# Clock arbitration, the named back-patch case, monotonic floor (F6).
add_executable(test_app_time
    test_app_time.c
    ${CMAKE_CURRENT_SOURCE_DIR}/../components/app_time/app_time_core.c
    ${CMAKE_CURRENT_SOURCE_DIR}/../components/cook_store/cook_store_core.c
    ${CMAKE_CURRENT_SOURCE_DIR}/../components/app_config/app_config_store.c
)
target_include_directories(test_app_time PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}/../components/app_time/include
    ${CMAKE_CURRENT_SOURCE_DIR}/../components/cook_store/include
    ${CMAKE_CURRENT_SOURCE_DIR}/../components/app_config/include
    ${REPO_ROOT}/protocol/gen
)
add_test(NAME app_time COMMAND test_app_time)

# Raw packet ring and novelty seen-set (F4.1/F4.2).
add_executable(test_smoke_x_novelty
    test_smoke_x_novelty.c
    ${CMAKE_CURRENT_SOURCE_DIR}/../components/smoke_x/smoke_x_novelty.c
    ${CMAKE_CURRENT_SOURCE_DIR}/../components/smoke_x/smoke_x_pktring.c
    ${CMAKE_CURRENT_SOURCE_DIR}/../components/smoke_x/smoke_x_parser.c
)
target_include_directories(test_smoke_x_novelty PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}/../components/smoke_x/include
)
add_test(NAME smoke_x_novelty COMMAND test_smoke_x_novelty)

# Pairing state machine, watchdog, and packet accounting (F3.4/F3.6/F3.7).
add_executable(test_smoke_x_ctrl
    test_smoke_x_ctrl.c
    ${CMAKE_CURRENT_SOURCE_DIR}/../components/smoke_x/smoke_x_ctrl.c
    ${CMAKE_CURRENT_SOURCE_DIR}/../components/smoke_x/smoke_x_parser.c
    ${CMAKE_CURRENT_SOURCE_DIR}/../components/app_config/app_config_store.c
)
target_include_directories(test_smoke_x_ctrl PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}/../components/smoke_x/include
    ${CMAKE_CURRENT_SOURCE_DIR}/../components/app_config/include
)
add_test(NAME smoke_x_ctrl COMMAND test_smoke_x_ctrl)

# Typed config store: schema round-trips, the reference-compatible sx_pair
# blob, the v0→v1 adoption migration, notifications, PSK (F7.1–F7.3).
add_executable(test_app_config
    test_app_config.c
    ${CMAKE_CURRENT_SOURCE_DIR}/../components/app_config/app_config_store.c
)
target_include_directories(test_app_config PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}/../components/app_config/include
)
add_test(NAME app_config COMMAND test_app_config)

# Task table invariants (F1.4).
add_executable(test_tasks_table test_tasks_table.c)
target_include_directories(test_tasks_table PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}/../main
)
add_test(NAME tasks_table COMMAND test_tasks_table)
