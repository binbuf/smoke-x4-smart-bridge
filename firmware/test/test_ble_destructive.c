/*
 * test_ble_destructive.c - host state tests for the T49 destructive lifecycle.
 *
 * Links the pure state machine used by ble_service.c, the real advertising
 * state machine, the real destructive router/dispatcher and the real boot-time
 * log-clear policy. Every destructive path is walked and the resulting radio
 * state (advertise / reboot / sleep) is asserted. No NimBLE, NVS or board.
 */
#include <stdbool.h>
#include <stdint.h>
#include <string.h>

#include "ble_adv.h"
#include "ble_control.h"
#include "ble_control_actions.h"
#include "ble_destructive.h"
#include "bridge_config.h"
#include "log_flash.h"
#include "ram_log_io.h"
#include "records.h"
#include "test_util.h"

/* ---- fake backend (bonds/config/log) for the control paths --------------- */

#define BOND_CURRENT 0x1u
#define BOND_OTHER 0x2u

typedef struct {
    uint32_t bonds;
    bool smoke_paired;
    uint32_t generation;
    uint32_t records;
    uint32_t config;
    int power_offs;
    int calls;
} fake_backend_t;

static fake_backend_t s_fake;

static uint8_t backend_common(void) {
    s_fake.calls++;
    return SX4_RESULT_STATUS_OK;
}

static uint8_t backend_forget(void *ctx) {
    (void)ctx;
    uint8_t status = backend_common();
    s_fake.bonds &= ~BOND_CURRENT; /* only the current phone */
    return status;
}

static uint8_t backend_factory(void *ctx) {
    (void)ctx;
    uint8_t status = backend_common();
    s_fake.bonds = 0;
    s_fake.config = 0;
    s_fake.records = 0;
    s_fake.generation++;
    s_fake.smoke_paired = false;
    return status;
}

static uint8_t backend_power(void *ctx) {
    (void)ctx;
    uint8_t status = backend_common();
    s_fake.power_offs++;
    return status;
}

static uint8_t backend_clear(void *ctx) {
    (void)ctx;
    uint8_t status = backend_common();
    s_fake.records = 0;
    s_fake.generation++;
    return status;
}

static uint8_t backend_unpair(void *ctx) {
    (void)ctx;
    uint8_t status = backend_common();
    s_fake.smoke_paired = false;
    return status;
}

static const ble_control_action_ops_t OPS = {
    .ctx = &s_fake,
    .forget_phone = backend_forget,
    .factory_reset = backend_factory,
    .power_off = backend_power,
    .clear_history = backend_clear,
    .unpair_smoke_x = backend_unpair,
};

static void fake_reset(void) {
    memset(&s_fake, 0, sizeof(s_fake));
    s_fake.bonds = BOND_CURRENT | BOND_OTHER;
    s_fake.smoke_paired = true;
    s_fake.generation = 0x12345678u;
    s_fake.records = 42;
    s_fake.config = 5;
}

static void expect_consistent(const ble_destructive_state_t *state) {
    CHECK(ble_destructive_consistent(state));
    CHECK(!(state->link_up && state->advertising));
}

static void put_result(ble_destructive_state_t *state,
                       ble_control_action_t action) {
    ble_destructive_on_connect(state);
    CHECK_EQ_UINT(ble_destructive_on_result(state, action),
                  BLE_DESTRUCTIVE_OUTCOME_NONE);
    CHECK(state->result_sent);
    CHECK(ble_destructive_pending(state));
    CHECK(!state->advertising); /* never advertising while connected */
    expect_consistent(state);
}

/* ---- 1. result first, then one teardown -------------------------------- */

static void check_result_then_disconnect(void) {
    ble_destructive_state_t state;
    ble_destructive_init(&state, true);
    CHECK(state.advertising);
    CHECK(!state.link_up);

    put_result(&state, BLE_CONTROL_ACTION_FORGET_PHONE);
    /* The result was handed to NimBLE before the action timer exists; the link
     * is still up here, which is what makes the answer-first ordering real. */
    CHECK(state.link_up);
    CHECK_EQ_UINT(state.phase, BLE_DESTRUCTIVE_PHASE_ANSWERED);

    CHECK_EQ_UINT(ble_destructive_take_action(&state),
                  BLE_CONTROL_ACTION_FORGET_PHONE);
    CHECK_EQ_UINT(state.phase, BLE_DESTRUCTIVE_PHASE_RUNNING);
    CHECK_EQ_UINT(ble_destructive_on_action_finished(
                      &state, BLE_CONTROL_ACTION_FORGET_PHONE,
                      SX4_RESULT_STATUS_OK),
                  BLE_DESTRUCTIVE_OUTCOME_ADVERTISE);
    CHECK(!state.link_up);
    CHECK(state.advertising);
    CHECK(!ble_destructive_pending(&state));
    expect_consistent(&state);

    /* A second action timer after teardown is a no-op, not a silent radio. */
    CHECK_EQ_UINT(ble_destructive_take_action(&state),
                  BLE_CONTROL_ACTION_NONE);
}

/* ---- 2. forget: current bond gone, other bonds stay, re-advertise ------- */

static void check_forget_readvertise(void) {
    fake_reset();
    ble_destructive_state_t state;
    ble_destructive_init(&state, true);
    put_result(&state, BLE_CONTROL_ACTION_FORGET_PHONE);

    /* App drops after the result but before the 250 ms action timer. The
     * pending action must survive and the bridge must be findable again. */
    CHECK_EQ_UINT(ble_destructive_on_disconnect(&state),
                  BLE_DESTRUCTIVE_OUTCOME_ADVERTISE);
    CHECK(ble_destructive_pending(&state));
    CHECK(state.advertising);
    expect_consistent(&state);

    CHECK_EQ_UINT(ble_destructive_take_action(&state),
                  BLE_CONTROL_ACTION_FORGET_PHONE);
    CHECK_EQ_UINT(ble_control_actions_run(&OPS, BLE_CONTROL_ACTION_FORGET_PHONE),
                  SX4_RESULT_STATUS_OK);
    CHECK_EQ_UINT(s_fake.bonds, BOND_OTHER);
    CHECK_EQ_UINT(ble_destructive_on_action_finished(
                      &state, BLE_CONTROL_ACTION_FORGET_PHONE,
                      SX4_RESULT_STATUS_OK),
                  BLE_DESTRUCTIVE_OUTCOME_ADVERTISE);
    CHECK(state.advertising);
    expect_consistent(&state);

    /* The normal advertising machine then opens a fresh 250 ms window. */
    ble_adv_state_t adv;
    ble_adv_state_init(&adv);
    ble_adv_action_t action =
        ble_adv_state_event(&adv, BLE_ADV_EVENT_DISCONNECT, 5000);
    CHECK(action.advertise);
    CHECK_EQ_UINT(action.interval_ms, BLE_ADV_FAST_INTERVAL_MS);
}

/* ---- 3. factory reset: wipe stays wiped, then reboot -------------------- */

static void check_factory_wipe_and_reboot(void) {
    fake_reset();
    ble_destructive_state_t state;
    ble_destructive_init(&state, true);
    put_result(&state, BLE_CONTROL_ACTION_FACTORY_RESET);

    /* The app may vanish immediately; the wipe still runs and never
     * re-advertises in between. */
    CHECK_EQ_UINT(ble_destructive_on_disconnect(&state),
                  BLE_DESTRUCTIVE_OUTCOME_NONE);
    CHECK(!state.advertising);
    CHECK(ble_destructive_pending(&state));

    CHECK_EQ_UINT(ble_destructive_take_action(&state),
                  BLE_CONTROL_ACTION_FACTORY_RESET);
    CHECK_EQ_UINT(ble_control_actions_run(&OPS, BLE_CONTROL_ACTION_FACTORY_RESET),
                  SX4_RESULT_STATUS_OK);
    CHECK_EQ_UINT(s_fake.bonds, 0u);
    CHECK_EQ_UINT(s_fake.records, 0u);
    CHECK_EQ_UINT(s_fake.config, 0u);
    CHECK_EQ_UINT(ble_destructive_on_action_finished(
                      &state, BLE_CONTROL_ACTION_FACTORY_RESET,
                      SX4_RESULT_STATUS_OK),
                  BLE_DESTRUCTIVE_OUTCOME_REBOOT);
    CHECK(!state.advertising);
    CHECK_EQ_UINT(state.phase, BLE_DESTRUCTIVE_PHASE_REBOOT);
    expect_consistent(&state);

    /* A disconnect during the reboot window must not resurrect advertising. */
    CHECK_EQ_UINT(ble_destructive_on_disconnect(&state),
                  BLE_DESTRUCTIVE_OUTCOME_REBOOT);
    CHECK(!state.advertising);
    expect_consistent(&state);
}

/* ---- 4. power off: silence, then sleep --------------------------------- */

static void check_power_off_sleep(void) {
    ble_destructive_state_t state;
    ble_destructive_init(&state, true);
    put_result(&state, BLE_CONTROL_ACTION_POWER_OFF);

    CHECK_EQ_UINT(ble_destructive_on_disconnect(&state),
                  BLE_DESTRUCTIVE_OUTCOME_NONE);
    CHECK(!state.advertising);
    CHECK(ble_destructive_pending(&state));

    CHECK_EQ_UINT(ble_destructive_take_action(&state),
                  BLE_CONTROL_ACTION_POWER_OFF);
    CHECK_EQ_UINT(ble_destructive_on_action_finished(
                      &state, BLE_CONTROL_ACTION_POWER_OFF,
                      SX4_RESULT_STATUS_OK),
                  BLE_DESTRUCTIVE_OUTCOME_SLEEP);
    CHECK(!state.advertising);
    CHECK_EQ_UINT(state.phase, BLE_DESTRUCTIVE_PHASE_SLEEP);
    expect_consistent(&state);

    /* Any late disconnect keeps it silent rather than advertising. */
    CHECK_EQ_UINT(ble_destructive_on_disconnect(&state),
                  BLE_DESTRUCTIVE_OUTCOME_SLEEP);
    CHECK(!state.advertising);
}

/* ---- 5. normal disconnect --------------------------------------------- */

static void check_normal_disconnect(void) {
    ble_destructive_state_t state;
    ble_destructive_init(&state, true);
    ble_destructive_on_connect(&state);
    CHECK(!state.advertising);

    /* App closed, out of range, failed connect or timeout: no pending action. */
    CHECK_EQ_UINT(ble_destructive_on_disconnect(&state),
                  BLE_DESTRUCTIVE_OUTCOME_ADVERTISE);
    CHECK(state.advertising);
    CHECK(!ble_destructive_pending(&state));
    expect_consistent(&state);

    /* A second disconnect (duplicate event) is idempotent. */
    CHECK_EQ_UINT(ble_destructive_on_disconnect(&state),
                  BLE_DESTRUCTIVE_OUTCOME_ADVERTISE);
    CHECK(state.advertising);
}

/* ---- 6. app drop mid-op for every destructive action ------------------- */

static void check_app_drop_mid_op(void) {
    static const ble_control_action_t actions[] = {
        BLE_CONTROL_ACTION_FORGET_PHONE,
        BLE_CONTROL_ACTION_FACTORY_RESET,
        BLE_CONTROL_ACTION_POWER_OFF,
        BLE_CONTROL_ACTION_CLEAR_HISTORY,
        BLE_CONTROL_ACTION_UNPAIR_SMOKE_X,
    };
    for (size_t i = 0; i < sizeof(actions) / sizeof(actions[0]); i++) {
        fake_reset();
        ble_destructive_state_t state;
        ble_destructive_init(&state, true);
        put_result(&state, actions[i]);

        ble_destructive_outcome_t drop =
            ble_destructive_on_disconnect(&state);
        CHECK(ble_destructive_pending(&state)); /* never lost */

        ble_control_action_t taken = ble_destructive_take_action(&state);
        CHECK_EQ_UINT(taken, actions[i]);
        CHECK_EQ_UINT(ble_control_actions_run(&OPS, taken),
                      SX4_RESULT_STATUS_OK);
        ble_destructive_outcome_t finished = ble_destructive_on_action_finished(
            &state, taken, SX4_RESULT_STATUS_OK);
        expect_consistent(&state);
        CHECK(!state.link_up || !state.advertising);

        switch (actions[i]) {
        case BLE_CONTROL_ACTION_FACTORY_RESET:
            CHECK_EQ_UINT(drop, BLE_DESTRUCTIVE_OUTCOME_NONE);
            CHECK_EQ_UINT(finished, BLE_DESTRUCTIVE_OUTCOME_REBOOT);
            CHECK(!state.advertising);
            break;
        case BLE_CONTROL_ACTION_POWER_OFF:
            CHECK_EQ_UINT(drop, BLE_DESTRUCTIVE_OUTCOME_NONE);
            CHECK_EQ_UINT(finished, BLE_DESTRUCTIVE_OUTCOME_SLEEP);
            CHECK(!state.advertising);
            break;
        default:
            CHECK_EQ_UINT(drop, BLE_DESTRUCTIVE_OUTCOME_ADVERTISE);
            CHECK_EQ_UINT(finished, BLE_DESTRUCTIVE_OUTCOME_ADVERTISE);
            CHECK(state.advertising);
            break;
        }
    }

    /* A late backend failure is the one case that returns to discovery: the
     * result already said ok, so the app must be able to reconnect and retry. */
    ble_destructive_state_t state;
    ble_destructive_init(&state, true);
    put_result(&state, BLE_CONTROL_ACTION_FORGET_PHONE);
    (void)ble_destructive_on_disconnect(&state);
    (void)ble_destructive_take_action(&state);
    CHECK_EQ_UINT(ble_destructive_on_action_finished(
                      &state, BLE_CONTROL_ACTION_FORGET_PHONE,
                      SX4_RESULT_STATUS_FAILED),
                  BLE_DESTRUCTIVE_OUTCOME_ADVERTISE);
    CHECK(state.advertising);
    expect_consistent(&state);
}

/* ---- 7. power cut with clear_pending set ------------------------------- */

#define TEST_SECTORS 4u
#define TEST_BYTES (TEST_SECTORS * SAMPLE_LOG_SECTOR_SIZE)
#define GEN_A 0x0A0B0C0Du
#define GEN_B 0x1A1B1C1Du

static uint8_t g_storage[TEST_BYTES];

typedef struct {
    uint32_t generation;
    bool clear_pending;
    int finish_calls;
} fake_nvs_t;

static int nvs_load(void *ctx, uint32_t *out) {
    *out = ((fake_nvs_t *)ctx)->generation;
    return 0;
}
static int nvs_store(void *ctx, uint32_t generation) {
    ((fake_nvs_t *)ctx)->generation = generation;
    return 0;
}
static int nvs_new(void *ctx, uint32_t *out) {
    fake_nvs_t *nvs = ctx;
    nvs->generation = GEN_B;
    *out = nvs->generation;
    return 0;
}
static int nvs_begin_clear(void *ctx, uint32_t *out) {
    fake_nvs_t *nvs = ctx;
    nvs->generation = GEN_B;
    nvs->clear_pending = true;
    *out = nvs->generation;
    return 0;
}
static bool nvs_clear_pending(void *ctx) {
    return ((fake_nvs_t *)ctx)->clear_pending;
}
static int nvs_finish_clear(void *ctx) {
    fake_nvs_t *nvs = ctx;
    nvs->finish_calls++;
    nvs->clear_pending = false;
    return 0;
}

static const log_flash_hooks_t HOOKS = {
    .load_generation = nvs_load,
    .store_generation = nvs_store,
    .new_generation = nvs_new,
    .begin_clear = nvs_begin_clear,
    .clear_pending = nvs_clear_pending,
    .finish_clear = nvs_finish_clear,
};

static sx4_sample_rec_t make_record(uint32_t unix_s) {
    sx4_sample_rec_t rec;
    memset(&rec, 0, sizeof(rec));
    for (unsigned i = 0; i < 4u; i++) {
        rec.temp[i] = SX4_TEMP_DETACHED;
    }
    rec.unix_s = unix_s;
    return rec;
}

static void append_three(log_flash_t *flash) {
    for (uint32_t i = 0; i < 3u; i++) {
        sx4_sample_rec_t rec = make_record(1000u + i);
        CHECK_EQ_INT(log_flash_append(flash, &rec), SAMPLE_LOG_OK);
    }
}

static uint32_t log_count(log_flash_t *flash) {
    log_ring_info_t info;
    CHECK(log_flash_info(flash, &info));
    return info.count;
}

static void check_power_cut_clear_pending(void) {
    memset(g_storage, 0xFF, sizeof(g_storage));
    ram_log_io_t ram;
    log_io_t io;
    CHECK_EQ_INT(ram_log_io_init(&ram, g_storage, TEST_BYTES,
                                 SAMPLE_LOG_SECTOR_SIZE),
                 0);
    ram_log_io_as_io(&ram, &io);

    fake_nvs_t nvs;
    memset(&nvs, 0, sizeof(nvs));
    nvs.generation = GEN_A;

    log_flash_t flash;
    CHECK_EQ_INT(log_flash_open(&flash, &io, &HOOKS, &nvs), LOG_FLASH_OK);
    append_three(&flash);
    CHECK_EQ_UINT(log_count(&flash), 3u);

    /* A normal reboot keeps the log. */
    CHECK_EQ_UINT(ble_destructive_boot_plan(nvs.clear_pending),
                  BLE_BOOT_OUTCOME_NORMAL);
    log_flash_t rebooted;
    CHECK_EQ_INT(log_flash_open(&rebooted, &io, &HOOKS, &nvs), LOG_FLASH_OK);
    CHECK_EQ_UINT(log_count(&rebooted), 3u);

    /* Power cut during clear_history/factory reset: the new generation and
     * clear_pending are already on NVS, the sectors are partly erased. Boot
     * must finish the wipe before anything advertises or appends. */
    nvs.clear_pending = true;
    nvs.generation = GEN_B;
    CHECK_EQ_UINT(ble_destructive_boot_plan(nvs.clear_pending),
                  BLE_BOOT_OUTCOME_CLEAR_THEN_ADVERTISE);

    log_flash_t after_cut;
    CHECK_EQ_INT(log_flash_open(&after_cut, &io, &HOOKS, &nvs), LOG_FLASH_OK);
    CHECK(!nvs.clear_pending);
    CHECK_EQ_INT(nvs.finish_calls, 1);
    CHECK_EQ_UINT(log_count(&after_cut), 0u);

    log_ring_info_t info;
    CHECK(log_flash_info(&after_cut, &info));
    CHECK_EQ_UINT(info.generation, GEN_B);

    /* Only after the wipe completes does the bridge advertise normally. */
    CHECK_EQ_UINT(ble_destructive_boot_plan(nvs.clear_pending),
                  BLE_BOOT_OUTCOME_NORMAL);
    ble_destructive_state_t boot;
    ble_destructive_init(&boot, true);
    CHECK(boot.advertising);
    expect_consistent(&boot);

    /* The recovered log is appendable again on the new generation. */
    append_three(&after_cut);
    CHECK_EQ_UINT(log_count(&after_cut), 3u);
    CHECK(log_flash_info(&after_cut, &info));
    CHECK_EQ_UINT(info.generation, GEN_B);

    /* And the factory-reset sequence marks the pending clear before any config
     * key is erased, so a cut at any later step still resolves on boot. */
    size_t step_count = 0;
    const bridge_config_reset_step_t *steps =
        bridge_config_factory_reset_steps(&step_count);
    CHECK(steps != NULL);
    CHECK(step_count > 2u);
    CHECK_EQ_UINT(steps[0].action, BRIDGE_CONFIG_RESET_NEW_GENERATION);
    CHECK_EQ_UINT(steps[1].action, BRIDGE_CONFIG_RESET_SET_CLEAR_PENDING);
    for (size_t i = 2; i < step_count; i++) {
        CHECK(steps[i].action == BRIDGE_CONFIG_RESET_ERASE ||
              steps[i].action == BRIDGE_CONFIG_RESET_CLEAR_BONDS);
    }
}

int main(void) {
    check_result_then_disconnect();
    check_forget_readvertise();
    check_factory_wipe_and_reboot();
    check_power_off_sleep();
    check_normal_disconnect();
    check_app_drop_mid_op();
    check_power_cut_clear_pending();
    return sx4_test_summary("ble-destructive");
}
