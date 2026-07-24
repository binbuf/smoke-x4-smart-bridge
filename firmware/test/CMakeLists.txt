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

# The HTTP contract over the real host-tested modules: router, auth,
# fixtures, streaming bound, WS registry (F9, F8.7, F4.5, F4.6).
add_executable(test_app_api
    test_app_api.c
    ${CMAKE_CURRENT_SOURCE_DIR}/../components/app_api/app_api_core.c
    ${CMAKE_CURRENT_SOURCE_DIR}/../components/app_api/app_api_sessions.c
    ${CMAKE_CURRENT_SOURCE_DIR}/../components/app_api/app_api_emit.c
    ${CMAKE_CURRENT_SOURCE_DIR}/../components/app_api/app_api_ws.c
    ${CMAKE_CURRENT_SOURCE_DIR}/../components/app_net/app_net_core.c
    ${CMAKE_CURRENT_SOURCE_DIR}/../components/smoke_x/smoke_x_ctrl.c
    ${CMAKE_CURRENT_SOURCE_DIR}/../components/smoke_x/smoke_x_parser.c
    ${CMAKE_CURRENT_SOURCE_DIR}/../components/smoke_x/smoke_x_pktring.c
    ${CMAKE_CURRENT_SOURCE_DIR}/../components/cook_store/cook_store_core.c
    ${CMAKE_CURRENT_SOURCE_DIR}/../components/cook_store/cook_ring.c
    ${CMAKE_CURRENT_SOURCE_DIR}/../components/cook_store/cook_novelty_log.c
    ${CMAKE_CURRENT_SOURCE_DIR}/../components/app_time/app_time_core.c
    ${CMAKE_CURRENT_SOURCE_DIR}/../components/app_config/app_config_store.c
    ${CMAKE_CURRENT_SOURCE_DIR}/../components/app_alarm/alarm_cfg.c
    ${CMAKE_CURRENT_SOURCE_DIR}/../components/app_alarm/rules.c
    ${CMAKE_CURRENT_SOURCE_DIR}/../components/app_alarm/alarm_lid.c
    ${CMAKE_CURRENT_SOURCE_DIR}/../components/app_alarm/alarm_engine.c
    ${CMAKE_CURRENT_SOURCE_DIR}/../components/app_alarm/app_alarm_svc.c
    ${CMAKE_CURRENT_SOURCE_DIR}/../components/app_power/power_core.c
    ${CMAKE_CURRENT_SOURCE_DIR}/../components/app_power/power_svc.c
    ${CMAKE_CURRENT_SOURCE_DIR}/../components/app_ota/ota_image.c
    ${CMAKE_CURRENT_SOURCE_DIR}/../components/app_ota/ota_core.c
    ${CMAKE_CURRENT_SOURCE_DIR}/../components/app_ota/ota_gate.c
)
target_include_directories(test_app_api PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}/../components/app_ota/include
    ${CMAKE_CURRENT_SOURCE_DIR}/../components/app_alarm/include
    ${CMAKE_CURRENT_SOURCE_DIR}/../components/app_power/include
    ${CMAKE_CURRENT_SOURCE_DIR}/../components/app_api/include
    ${CMAKE_CURRENT_SOURCE_DIR}/../components/app_net/include
    ${CMAKE_CURRENT_SOURCE_DIR}/../components/smoke_x/include
    ${CMAKE_CURRENT_SOURCE_DIR}/../components/cook_store/include
    ${CMAKE_CURRENT_SOURCE_DIR}/../components/app_time/include
    ${CMAKE_CURRENT_SOURCE_DIR}/../components/app_config/include
    ${CMAKE_CURRENT_SOURCE_DIR}/../components/bridge_event/include
    ${REPO_ROOT}/protocol/gen
)
target_compile_definitions(test_app_api PRIVATE
    FIXTURES_HTTP_DIR="${REPO_ROOT}/protocol/fixtures/http"
    FIXTURES_OTA_DIR="${REPO_ROOT}/protocol/fixtures/ota"
)
add_test(NAME app_api COMMAND test_app_api)

# Wi-Fi mode selection and STA supervision (F8.1–F8.3).
add_executable(test_app_net
    test_app_net.c
    ${CMAKE_CURRENT_SOURCE_DIR}/../components/app_net/app_net_core.c
    ${CMAKE_CURRENT_SOURCE_DIR}/../components/app_net/dns_shim.c
    ${CMAKE_CURRENT_SOURCE_DIR}/../components/app_net/app_net_txt.c
    ${CMAKE_CURRENT_SOURCE_DIR}/../components/app_config/app_config_store.c
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

# The Bridge Control Service as a pure core: registry, security table,
# builders against the P3.2 fixtures, advertising PDUs, the MTU chunker,
# and every device_control op through real component doubles (F10).
add_executable(test_app_ble
    test_app_ble.c
    ${CMAKE_CURRENT_SOURCE_DIR}/../components/app_ble/app_ble_core.c
    ${CMAKE_CURRENT_SOURCE_DIR}/../components/app_ble/app_ble_ctrl.c
    ${CMAKE_CURRENT_SOURCE_DIR}/../components/app_ble/app_ble_adv.c
    ${CMAKE_CURRENT_SOURCE_DIR}/../components/app_net/app_net_core.c
    ${CMAKE_CURRENT_SOURCE_DIR}/../components/smoke_x/smoke_x_ctrl.c
    ${CMAKE_CURRENT_SOURCE_DIR}/../components/smoke_x/smoke_x_parser.c
    ${CMAKE_CURRENT_SOURCE_DIR}/../components/cook_store/cook_store_core.c
    ${CMAKE_CURRENT_SOURCE_DIR}/../components/cook_store/cook_ring.c
    ${CMAKE_CURRENT_SOURCE_DIR}/../components/app_time/app_time_core.c
    ${CMAKE_CURRENT_SOURCE_DIR}/../components/app_config/app_config_store.c
    # F10.5's done-when: the passkey app_ble generates must be the passkey
    # F11a draws. The two halves meet here, against the committed golden.
    ${CMAKE_CURRENT_SOURCE_DIR}/../components/app_ui/app_ui_fb.c
    ${CMAKE_CURRENT_SOURCE_DIR}/../components/app_ui/app_ui_font.c
    ${CMAKE_CURRENT_SOURCE_DIR}/../components/app_ui/app_ui_render.c
    ${CMAKE_CURRENT_SOURCE_DIR}/../components/app_alarm/alarm_cfg.c
    ${CMAKE_CURRENT_SOURCE_DIR}/../components/app_alarm/rules.c
    ${CMAKE_CURRENT_SOURCE_DIR}/../components/app_alarm/alarm_lid.c
    ${CMAKE_CURRENT_SOURCE_DIR}/../components/app_alarm/alarm_engine.c
    ${CMAKE_CURRENT_SOURCE_DIR}/../components/app_alarm/app_alarm_svc.c
    ${CMAKE_CURRENT_SOURCE_DIR}/../components/app_power/power_core.c
    ${CMAKE_CURRENT_SOURCE_DIR}/../components/app_power/power_svc.c
)
target_include_directories(test_app_ble PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}/../components/app_alarm/include
    ${CMAKE_CURRENT_SOURCE_DIR}/../components/app_power/include
    ${CMAKE_CURRENT_SOURCE_DIR}/../components/app_ble/include
    ${CMAKE_CURRENT_SOURCE_DIR}/../components/app_ui/include
    ${CMAKE_CURRENT_SOURCE_DIR}/../components/app_net/include
    ${CMAKE_CURRENT_SOURCE_DIR}/../components/smoke_x/include
    ${CMAKE_CURRENT_SOURCE_DIR}/../components/cook_store/include
    ${CMAKE_CURRENT_SOURCE_DIR}/../components/app_time/include
    ${CMAKE_CURRENT_SOURCE_DIR}/../components/app_config/include
    ${CMAKE_CURRENT_SOURCE_DIR}/../components/bridge_event/include
    ${REPO_ROOT}/protocol/gen
)
target_compile_definitions(test_app_ble PRIVATE
    FIXTURES_DIR="${REPO_ROOT}/protocol/fixtures/records"
    GOLDEN_DIR="${CMAKE_CURRENT_SOURCE_DIR}/goldens/oled"
)
add_test(NAME app_ble COMMAND test_app_ble)

# The display layer: primitives, clipping, both fonts, the §7.3 passkey
# overlay against golden framebuffers, and the V1.4 rail-before-bus
# bring-up order through the injected I²C seam (F11a.1–F11a.5).
add_executable(test_app_ui
    test_app_ui.c
    ${CMAKE_CURRENT_SOURCE_DIR}/../components/app_ui/app_ui_fb.c
    ${CMAKE_CURRENT_SOURCE_DIR}/../components/app_ui/app_ui_font.c
    ${CMAKE_CURRENT_SOURCE_DIR}/../components/app_ui/app_ui_render.c
    ${CMAKE_CURRENT_SOURCE_DIR}/../components/app_ui/app_ui_panel.c
    ${CMAKE_CURRENT_SOURCE_DIR}/../components/app_ui/app_ui_input.c
    ${CMAKE_CURRENT_SOURCE_DIR}/../components/app_ui/app_ui_model.c
    ${CMAKE_CURRENT_SOURCE_DIR}/../components/app_ui/app_ui_led.c
)
target_include_directories(test_app_ui PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}/../components/app_ui/include
    ${REPO_ROOT}/protocol/gen
)
# Goldens are reviewed as PNGs (tools/oled); rendered copies land in the
# build dir so CI can upload the picture even when the bytes disagree.
file(MAKE_DIRECTORY ${CMAKE_CURRENT_BINARY_DIR}/oled-render)
target_compile_definitions(test_app_ui PRIVATE
    GOLDEN_DIR="${CMAKE_CURRENT_SOURCE_DIR}/goldens/oled"
    RENDER_DIR="${CMAKE_CURRENT_BINARY_DIR}/oled-render"
)
add_test(NAME app_ui COMMAND test_app_ui)

# The device-tier alarm engine: the 09 §9.2 rule table, the latching
# lifecycle, the ±1 °F oscillation regression from 10 §10.5, and the
# lid-open branch that keeps a spritz from being an alarm (F13.1,
# F13.3–F13.5).
add_executable(test_app_alarm
    test_app_alarm.c
    ${CMAKE_CURRENT_SOURCE_DIR}/../components/app_alarm/alarm_cfg.c
    ${CMAKE_CURRENT_SOURCE_DIR}/../components/app_alarm/rules.c
    ${CMAKE_CURRENT_SOURCE_DIR}/../components/app_alarm/alarm_lid.c
    ${CMAKE_CURRENT_SOURCE_DIR}/../components/app_alarm/alarm_engine.c
)
target_include_directories(test_app_alarm PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}/../components/app_alarm/include
    ${REPO_ROOT}/protocol/gen
)
add_test(NAME app_alarm COMMAND test_app_alarm)

# The alarm engine wired to the REAL app_config_store, smoke_x_ctrl,
# cook_ring and cook_store — the modules the firmware runs, not doubles of
# them. Only the four device facts are faked (F13.6, F13.7).
add_executable(test_app_alarm_svc
    test_app_alarm_svc.c
    ${CMAKE_CURRENT_SOURCE_DIR}/../components/app_alarm/alarm_cfg.c
    ${CMAKE_CURRENT_SOURCE_DIR}/../components/app_alarm/rules.c
    ${CMAKE_CURRENT_SOURCE_DIR}/../components/app_alarm/alarm_lid.c
    ${CMAKE_CURRENT_SOURCE_DIR}/../components/app_alarm/alarm_engine.c
    ${CMAKE_CURRENT_SOURCE_DIR}/../components/app_alarm/app_alarm_svc.c
    ${CMAKE_CURRENT_SOURCE_DIR}/../components/app_config/app_config_store.c
    ${CMAKE_CURRENT_SOURCE_DIR}/../components/cook_store/cook_store_core.c
    ${CMAKE_CURRENT_SOURCE_DIR}/../components/cook_store/cook_ring.c
    ${CMAKE_CURRENT_SOURCE_DIR}/../components/smoke_x/smoke_x_ctrl.c
    ${CMAKE_CURRENT_SOURCE_DIR}/../components/smoke_x/smoke_x_parser.c
)
target_include_directories(test_app_alarm_svc PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}/../components/app_alarm/include
    ${CMAKE_CURRENT_SOURCE_DIR}/../components/app_config/include
    ${CMAKE_CURRENT_SOURCE_DIR}/../components/cook_store/include
    ${CMAKE_CURRENT_SOURCE_DIR}/../components/smoke_x/include
    ${REPO_ROOT}/protocol/gen
)
add_test(NAME app_alarm_svc COMMAND test_app_alarm_svc)

# Battery: the 01 §1.3 discharge curve, the EMA, the inferred charging
# state, the plateau solver and its ±20 % clamp, the saver hysteresis, and
# the V1.3 gate ORDER through the injected ADC seam (F12.1–F12.4).
add_executable(test_app_power
    test_app_power.c
    ${CMAKE_CURRENT_SOURCE_DIR}/../components/app_power/power_core.c
)
target_include_directories(test_app_power PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}/../components/app_power/include
    ${REPO_ROOT}/protocol/gen
)
add_test(NAME app_power COMMAND test_app_power)

# Task table invariants (F1.4).
add_executable(test_tasks_table test_tasks_table.c)
target_include_directories(test_tasks_table PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}/../main
)
add_test(NAME tasks_table COMMAND test_tasks_table)

# The OTA path (F14.1–F14.4): the image inspector against the first 288
# bytes of REAL builds, admission, the phase machine and its throttled
# progress, the injected flash seam with every failure a board would take
# a reflash to produce, and 03 §3.7's health gate as a table. Nothing in
# F14 touches the board before F14.9, and this binary is why.
add_executable(test_app_ota
    test_app_ota.c
    ${CMAKE_CURRENT_SOURCE_DIR}/../components/app_ota/ota_image.c
    ${CMAKE_CURRENT_SOURCE_DIR}/../components/app_ota/ota_core.c
    ${CMAKE_CURRENT_SOURCE_DIR}/../components/app_ota/ota_gate.c
)
target_include_directories(test_app_ota PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}/../components/app_ota/include
)
target_compile_definitions(test_app_ota PRIVATE
    FIXTURES_OTA_DIR="${REPO_ROOT}/protocol/fixtures/ota"
)
add_test(NAME app_ota COMMAND test_app_ota)
