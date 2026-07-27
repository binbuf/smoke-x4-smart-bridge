/* test_boot_seq.c — the 03 §3.4 boot skeleton (F1.5).
 *
 * The named done-when cases: a stub failing at step 12 still leaves a booted
 * device with steps 1–11 complete, and the double-reset token round-trips
 * across a reset but not a power cycle.
 */
#include "boot_seq.h"
#include "double_reset.h"
#include "test_util.h"

#include <stdint.h>

typedef struct {
    int calls[BRIDGE_BOOT_STEP_COUNT + 1]; /* invocation order, 1-based */
    int n_calls;
    int fail_step; /* step number to fail, 0 = none */
} fake_t;

static fake_t g_fake;

static int fake_step_1(void *ctx);

#define FAKE_STEP(n)                             \
    static int fake_step_##n(void *ctx) {        \
        (void)ctx;                               \
        g_fake.calls[g_fake.n_calls++] = (n);    \
        return g_fake.fail_step == (n) ? -1 : 0; \
    }

FAKE_STEP(1)
FAKE_STEP(2)
FAKE_STEP(3)
FAKE_STEP(4)
FAKE_STEP(5)
FAKE_STEP(6)
FAKE_STEP(7)
FAKE_STEP(8)
FAKE_STEP(9)
FAKE_STEP(10)
FAKE_STEP(11)
FAKE_STEP(12)
FAKE_STEP(13)
FAKE_STEP(14)
FAKE_STEP(15)
FAKE_STEP(16)
FAKE_STEP(17)

static bridge_boot_ops_t fake_ops(void) {
    bridge_boot_ops_t ops = {
        .steps =
            {
                fake_step_1,
                fake_step_2,
                fake_step_3,
                fake_step_4,
                fake_step_5,
                fake_step_6,
                fake_step_7,
                fake_step_8,
                fake_step_9,
                fake_step_10,
                fake_step_11,
                fake_step_12,
                fake_step_13,
                fake_step_14,
                fake_step_15,
                fake_step_16,
                fake_step_17,
            },
    };
    return ops;
}

static void reset_fake(int fail_step) {
    memset(&g_fake, 0, sizeof g_fake);
    g_fake.fail_step = fail_step;
}

static void test_clean_boot(void) {
    reset_fake(0);
    const bridge_boot_ops_t ops = fake_ops();
    bridge_boot_result_t res;
    CHECK(bridge_boot_run(&ops, NULL, &res));
    CHECK_EQ_INT(res.steps_completed, 17);
    CHECK_EQ_INT(res.failed_mask, 0);
    CHECK_EQ_INT(res.fatal_step, 0);
    CHECK_EQ_INT(g_fake.n_calls, 17);
}

static void test_step12_failure_still_boots(void) {
    /* The named case: app_net_start (step 12) errors; the device is still
     * booted with steps 1–11 complete, and later steps still run — every
     * step after cook_store is individually failure-tolerant. */
    reset_fake(BRIDGE_BOOT_NET);
    const bridge_boot_ops_t ops = fake_ops();
    bridge_boot_result_t res;
    CHECK(bridge_boot_run(&ops, NULL, &res));
    CHECK_EQ_INT(res.steps_completed, 11);
    CHECK_EQ_INT(res.failed_mask, 1u << (BRIDGE_BOOT_NET - 1));
    CHECK_EQ_INT(res.fatal_step, 0);
    CHECK_EQ_INT(g_fake.n_calls, 17); /* 13..17 still ran */
    CHECK_EQ_INT(g_fake.calls[16], 17);
}

static void test_fatal_steps_abort(void) {
    /* Only NVS (1) and the event loop (4) are fatal. */
    reset_fake(BRIDGE_BOOT_NVS);
    bridge_boot_ops_t ops = fake_ops();
    bridge_boot_result_t res;
    CHECK(!bridge_boot_run(&ops, NULL, &res));
    CHECK_EQ_INT(res.fatal_step, 1);
    CHECK_EQ_INT(g_fake.n_calls, 1);

    reset_fake(BRIDGE_BOOT_EVENT_LOOP);
    ops = fake_ops();
    CHECK(!bridge_boot_run(&ops, NULL, &res));
    CHECK_EQ_INT(res.fatal_step, 4);
    CHECK_EQ_INT(g_fake.n_calls, 4);
}

static void test_lora_before_network(void) {
    /* The ordering invariant: smoke_x_start (LoRa RX) runs before
     * app_net_start and app_ble_start. Data capture is the product. */
    reset_fake(0);
    const bridge_boot_ops_t ops = fake_ops();
    CHECK(bridge_boot_run(&ops, NULL, NULL));
    int idx_lora = -1;
    int idx_net = -1;
    int idx_ble = -1;
    for (int i = 0; i < g_fake.n_calls; i++) {
        if (g_fake.calls[i] == BRIDGE_BOOT_SMOKE_X_START) {
            idx_lora = i;
        }
        if (g_fake.calls[i] == BRIDGE_BOOT_NET) {
            idx_net = i;
        }
        if (g_fake.calls[i] == BRIDGE_BOOT_BLE) {
            idx_ble = i;
        }
    }
    CHECK(idx_lora >= 0 && idx_net >= 0 && idx_ble >= 0);
    CHECK(idx_lora < idx_net);
    CHECK(idx_lora < idx_ble);
}

static void test_null_steps_are_skipped(void) {
    const bridge_boot_ops_t ops = {0}; /* all NULL — a bare skeleton boots */
    bridge_boot_result_t res;
    CHECK(bridge_boot_run(&ops, NULL, &res));
    CHECK_EQ_INT(res.steps_completed, 17);
}

static void test_double_reset_token(void) {
    /* "Reset": the token variable survives; only the clock moves. */
    bridge_drt_token_t rtc = {0};

    /* Cold boot: no token → not a double reset; arm. */
    CHECK(!bridge_double_reset_check(&rtc, 1000));
    bridge_double_reset_arm(&rtc, 1000);

    /* Reset 3 s later: token survives RTC SRAM → double reset detected. */
    CHECK(bridge_double_reset_check(&rtc, 4000));
    /* ...and consumed: a third reset right after is NOT a double reset. */
    CHECK(!bridge_double_reset_check(&rtc, 4100));

    /* Stale token (beyond the 10 s window) does not trigger. */
    bridge_double_reset_arm(&rtc, 1000);
    CHECK(!bridge_double_reset_check(&rtc, 1000 + BRIDGE_DRT_WINDOW_MS));

    /* Disarm after a stable boot: nothing pending. */
    bridge_double_reset_arm(&rtc, 50000);
    bridge_double_reset_disarm(&rtc);
    CHECK(!bridge_double_reset_check(&rtc, 51000));

    /* "Power cycle": RTC SRAM comes up zeroed → no token, no trigger. */
    bridge_drt_token_t cold = {0};
    CHECK(!bridge_double_reset_check(&cold, 500));

    /* Corrupt magic (RTC SRAM noise) must not trigger. */
    bridge_drt_token_t noise;
    noise.magic = 0xDEADBEEF;
    noise.armed_at_ms = 100;
    CHECK(!bridge_double_reset_check(&noise, 200));

    /* Clock anomaly: armed_at in the future must not trigger. */
    bridge_double_reset_arm(&rtc, 9000);
    CHECK(!bridge_double_reset_check(&rtc, 8000));
}

int main(void) {
    test_clean_boot();
    test_step12_failure_still_boots();
    test_fatal_steps_abort();
    test_lora_before_network();
    test_null_steps_are_skipped();
    test_double_reset_token();
    return test_summary("test_boot_seq");
}
