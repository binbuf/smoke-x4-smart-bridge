/*
 * test_ble_control_actions.c - host tests for the T48 destructive ops.
 *
 * The real dispatcher (ble_control.c) is linked with a fake backend behind the
 * pure routing module (ble_control_actions.c). This covers, for every op:
 * answer-first ordering, op_id echo, idempotent repeat, failure mapping and
 * malformed/wrong-length/unknown requests. No NimBLE, NVS, flash or board.
 */
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

#include "ble_control.h"
#include "ble_control_actions.h"
#include "records.h"
#include "test_util.h"

#define IND_FORGET 1
#define IND_FACTORY 2
#define IND_POWER 3
#define IND_CLEAR 4
#define IND_UNPAIR 5

#define CURRENT_BOND 0x1u
#define OTHER_BOND 0x2u

typedef struct {
    int calls[6];
    uint8_t fail_status[6];
    uint32_t bond_mask;
    bool smoke_paired;
    uint32_t generation;
    uint32_t records;
    uint32_t config_values;
    uint32_t power_offs;
} fake_backend_t;

static fake_backend_t s_fake;
static int s_dispatch_calls;

static fake_backend_t *fake_init(void) {
    memset(&s_fake, 0, sizeof(s_fake));
    s_fake.bond_mask = CURRENT_BOND | OTHER_BOND;
    s_fake.smoke_paired = true;
    s_fake.generation = 0x11112222u;
    s_fake.records = 77;
    s_fake.config_values = 3;
    s_dispatch_calls = 0;
    return &s_fake;
}

static uint8_t fail_or_ok(fake_backend_t *fake, int index) {
    fake->calls[index]++;
    uint8_t status = fake->fail_status[index];
    if (status != SX4_RESULT_STATUS_OK) {
        return status;
    }
    return SX4_RESULT_STATUS_OK;
}

static uint8_t backend_forget(void *ctx) {
    fake_backend_t *fake = ctx;
    uint8_t status = fail_or_ok(fake, IND_FORGET);
    if (status == SX4_RESULT_STATUS_OK) {
        fake->bond_mask &= ~CURRENT_BOND; /* other bonds stay */
    }
    return status;
}

static uint8_t backend_factory(void *ctx) {
    fake_backend_t *fake = ctx;
    uint8_t status = fail_or_ok(fake, IND_FACTORY);
    if (status == SX4_RESULT_STATUS_OK) {
        fake->bond_mask = 0;
        fake->config_values = 0;
        fake->records = 0;
        fake->generation++;
    }
    return status;
}

static uint8_t backend_power(void *ctx) {
    fake_backend_t *fake = ctx;
    uint8_t status = fail_or_ok(fake, IND_POWER);
    if (status == SX4_RESULT_STATUS_OK) {
        fake->power_offs++;
    }
    return status;
}

static uint8_t backend_clear(void *ctx) {
    fake_backend_t *fake = ctx;
    uint8_t status = fail_or_ok(fake, IND_CLEAR);
    if (status == SX4_RESULT_STATUS_OK) {
        fake->records = 0;
        fake->generation++;
        /* Pairing/config survive a clear. */
    }
    return status;
}

static uint8_t backend_unpair(void *ctx) {
    fake_backend_t *fake = ctx;
    uint8_t status = fail_or_ok(fake, IND_UNPAIR);
    if (status == SX4_RESULT_STATUS_OK) {
        fake->smoke_paired = false; /* log/config/bonds untouched */
    }
    return status;
}

static ble_control_action_ops_t s_ops = {
    .ctx = &s_fake,
    .forget_phone = backend_forget,
    .factory_reset = backend_factory,
    .power_off = backend_power,
    .clear_history = backend_clear,
    .unpair_smoke_x = backend_unpair,
};

static uint8_t dispatch_handler(ble_control_action_t action, void *ctx) {
    (void)ctx;
    s_dispatch_calls++;
    s_ops.ctx = &s_fake;
    return ble_control_actions_run(&s_ops, action);
}

static void install(void) {
    s_ops.ctx = &s_fake;
    ble_control_set_action_handler(dispatch_handler, &s_fake);
}

static size_t build_request(uint8_t *out, uint8_t op, uint8_t op_id) {
    out[0] = 1u;
    out[1] = op;
    out[2] = op_id;
    return 3u;
}

static uint8_t expected_action(uint8_t op) {
    switch (op) {
    case 2:
        return BLE_CONTROL_ACTION_FORGET_PHONE;
    case 3:
        return BLE_CONTROL_ACTION_FACTORY_RESET;
    case 4:
        return BLE_CONTROL_ACTION_POWER_OFF;
    case 5:
        return BLE_CONTROL_ACTION_CLEAR_HISTORY;
    case 7:
        return BLE_CONTROL_ACTION_UNPAIR_SMOKE_X;
    default:
        return BLE_CONTROL_ACTION_NONE;
    }
}

static int fake_index(uint8_t op) {
    switch (op) {
    case 2:
        return IND_FORGET;
    case 3:
        return IND_FACTORY;
    case 4:
        return IND_POWER;
    case 5:
        return IND_CLEAR;
    case 7:
        return IND_UNPAIR;
    default:
        return 0;
    }
}

static void check_ordering_and_idempotency(void) {
    static const uint8_t ops[] = {2u, 3u, 4u, 5u, 7u};
    for (size_t i = 0; i < sizeof(ops); i++) {
        const uint8_t op = ops[i];
        const int index = fake_index(op);
        fake_init();
        install();

        uint8_t request[4];
        size_t len = build_request(request, op, (uint8_t)(10u + i));
        ble_control_result_t result;
        CHECK_EQ_UINT(ble_control_handle(request, len, &result),
                      SX4_RESULT_STATUS_OK);
        CHECK_EQ_UINT(result.ver, 1u);
        CHECK_EQ_UINT(result.op, op);
        CHECK_EQ_UINT(result.op_id, (uint8_t)(10u + i));
        CHECK_EQ_UINT(result.status, SX4_RESULT_STATUS_OK);
        CHECK_EQ_UINT(result.action, expected_action(op));
        CHECK_EQ_UINT(result.action_delay_ms, BLE_CONTROL_ACTION_DELAY_MS);
        /* Answer first: the backend must not have run inside the dispatcher. */
        CHECK_EQ_INT(s_fake.calls[index], 0);
        CHECK_EQ_INT(s_dispatch_calls, 0);
        CHECK_STR_EQ(result.detail, "accepted");

        /* Run the action the way the adapter's timer does. */
        CHECK_EQ_UINT(ble_control_run_action((ble_control_action_t)result.action),
                      SX4_RESULT_STATUS_OK);
        CHECK_EQ_INT(s_fake.calls[index], 1);
        CHECK_EQ_INT(s_dispatch_calls, 1);

        if (op == 2u) {
            CHECK_EQ_UINT(s_fake.bond_mask, OTHER_BOND);
        } else if (op == 3u) {
            CHECK_EQ_UINT(s_fake.bond_mask, 0u);
            CHECK_EQ_UINT(s_fake.config_values, 0u);
            CHECK_EQ_UINT(s_fake.records, 0u);
        } else if (op == 4u) {
            CHECK_EQ_UINT(s_fake.power_offs, 1u);
        } else if (op == 5u) {
            CHECK_EQ_UINT(s_fake.records, 0u);
            CHECK_EQ_UINT(s_fake.generation, 0x11112223u);
            CHECK_EQ_UINT(s_fake.config_values, 3u); /* config survives */
            CHECK_EQ_UINT(s_fake.bond_mask, CURRENT_BOND | OTHER_BOND);
        } else {
            CHECK(!s_fake.smoke_paired);
            CHECK_EQ_UINT(s_fake.records, 77u); /* log survives */
            CHECK_EQ_UINT(s_fake.config_values, 3u);
        }

        /* Repeat: planning the same op again changes nothing until the timer
         * runs, and the second run is safe/idempotent. */
        len = build_request(request, op, (uint8_t)(100u + i));
        CHECK_EQ_UINT(ble_control_handle(request, len, &result),
                      SX4_RESULT_STATUS_OK);
        CHECK_EQ_UINT(result.op_id, (uint8_t)(100u + i));
        CHECK_EQ_INT(s_fake.calls[index], 1);
        CHECK_EQ_UINT(ble_control_run_action((ble_control_action_t)result.action),
                      SX4_RESULT_STATUS_OK);
        CHECK_EQ_INT(s_fake.calls[index], 2);

        if (op == 2u) {
            CHECK_EQ_UINT(s_fake.bond_mask, OTHER_BOND);
        } else if (op == 3u) {
            CHECK_EQ_UINT(s_fake.bond_mask, 0u);
            CHECK_EQ_UINT(s_fake.config_values, 0u);
            CHECK_EQ_UINT(s_fake.records, 0u);
        } else if (op == 4u) {
            CHECK_EQ_UINT(s_fake.power_offs, 2u);
        } else if (op == 5u) {
            CHECK_EQ_UINT(s_fake.records, 0u);
            CHECK_EQ_UINT(s_fake.generation, 0x11112224u);
            CHECK_EQ_UINT(s_fake.config_values, 3u);
        } else {
            CHECK(!s_fake.smoke_paired);
            CHECK_EQ_UINT(s_fake.records, 77u);
            CHECK_EQ_UINT(s_fake.config_values, 3u);
        }
    }
    ble_control_set_action_handler(NULL, NULL);
}

static void check_failure_mapping(void) {
    static const uint8_t ops[] = {2u, 3u, 4u, 5u, 7u};
    static const uint8_t failures[] = {
        SX4_RESULT_STATUS_NOT_FOUND,
        SX4_RESULT_STATUS_STORAGE,
        SX4_RESULT_STATUS_FAILED,
        SX4_RESULT_STATUS_BUSY,
        SX4_RESULT_STATUS_UNAUTHORIZED,
    };
    for (size_t i = 0; i < sizeof(ops); i++) {
        const uint8_t op = ops[i];
        const int index = fake_index(op);
        fake_init();
        s_fake.fail_status[index] = failures[i];
        install();

        uint8_t request[4];
        size_t len = build_request(request, op, 50u);
        ble_control_result_t result;
        CHECK_EQ_UINT(ble_control_handle(request, len, &result),
                      SX4_RESULT_STATUS_OK);
        CHECK_EQ_UINT(result.status, SX4_RESULT_STATUS_OK);
        /* The failure happens after the answer; it cannot rewrite result. */
        CHECK_EQ_UINT(ble_control_run_action((ble_control_action_t)index),
                      failures[i]);
        CHECK_EQ_INT(s_fake.calls[index], 1);

        if (op == 2u) {
            CHECK_EQ_UINT(s_fake.bond_mask, CURRENT_BOND | OTHER_BOND);
        } else if (op == 3u) {
            CHECK_EQ_UINT(s_fake.config_values, 3u);
            CHECK_EQ_UINT(s_fake.records, 77u);
        } else if (op == 5u) {
            CHECK_EQ_UINT(s_fake.records, 77u);
            CHECK_EQ_UINT(s_fake.generation, 0x11112222u);
        } else if (op == 7u) {
            CHECK(s_fake.smoke_paired);
            CHECK_EQ_UINT(s_fake.records, 77u);
        }
    }
    ble_control_set_action_handler(NULL, NULL);
}

static void check_malformed_bodies_change_nothing(void) {
    static const uint8_t ops[] = {2u, 3u, 4u, 5u, 7u};
    fake_init();
    install();

    for (size_t i = 0; i < sizeof(ops); i++) {
        const int index = fake_index(ops[i]);
        uint8_t request[4] = {1u, ops[i], (uint8_t)(20u + i), 0xAAu};
        ble_control_result_t result;
        CHECK_EQ_UINT(ble_control_handle(request, sizeof(request), &result),
                      SX4_RESULT_STATUS_INVALID);
        CHECK_EQ_UINT(result.op, ops[i]);
        CHECK_EQ_UINT(result.op_id, (uint8_t)(20u + i));
        CHECK_EQ_UINT(result.action, BLE_CONTROL_ACTION_NONE);
        CHECK_EQ_INT(s_fake.calls[index], 0);
    }

    /* Wrong version is invalid before any op dispatch. */
    uint8_t request[3] = {2u, 3u, 77u};
    ble_control_result_t result;
    CHECK_EQ_UINT(ble_control_handle(request, sizeof(request), &result),
                  SX4_RESULT_STATUS_INVALID);
    CHECK_EQ_UINT(result.action, BLE_CONTROL_ACTION_NONE);

    /* Truncated envelope still echoes what arrived and changes nothing. */
    static const uint8_t truncated[2] = {1u, 4u};
    CHECK_EQ_UINT(ble_control_handle(truncated, sizeof(truncated), &result),
                  SX4_RESULT_STATUS_INVALID);
    CHECK_EQ_UINT(result.op, 4u);
    CHECK_EQ_UINT(result.action, BLE_CONTROL_ACTION_NONE);

    /* The characteristic is 16 B maximum: a longer write is invalid, even for
     * an unknown op that would otherwise be unsupported. */
    uint8_t too_long[SX4_BLE_CONTROL_MAX_SIZE + 1u];
    memset(too_long, 0, sizeof(too_long));
    too_long[0] = 1u;
    too_long[1] = 99u;
    too_long[2] = 204u;
    CHECK_EQ_UINT(ble_control_handle(too_long, sizeof(too_long), &result),
                  SX4_RESULT_STATUS_INVALID);
    CHECK_EQ_UINT(result.op, 99u);
    CHECK_EQ_UINT(result.op_id, 204u);
    CHECK_EQ_UINT(result.action, BLE_CONTROL_ACTION_NONE);
    CHECK_STR_EQ(result.detail, "control too long");

    CHECK_EQ_INT(s_dispatch_calls, 0);
    ble_control_set_action_handler(NULL, NULL);
}

static void check_unknown_and_billows(void) {
    fake_init();
    install();

    /* Unknown op stays unsupported even with a live handler. */
    uint8_t request[4] = {1u, 99u, 201u, 0u};
    ble_control_result_t result;
    CHECK_EQ_UINT(ble_control_handle(request, 3u, &result),
                  SX4_RESULT_STATUS_UNSUPPORTED);
    CHECK_EQ_UINT(result.op, 99u);
    CHECK_EQ_UINT(result.op_id, 201u);
    CHECK_EQ_UINT(result.action, BLE_CONTROL_ACTION_NONE);
    CHECK_STR_EQ(result.detail, "unknown op");

    /* set_billows_target is reserved: exact 2-byte body, always unsupported. */
    static const uint8_t billows[5] = {1u, 6u, 202u, 0xCAu, 0x08u};
    CHECK_EQ_UINT(ble_control_handle(billows, sizeof(billows), &result),
                  SX4_RESULT_STATUS_UNSUPPORTED);
    CHECK_EQ_UINT(result.op, 6u);
    CHECK_EQ_UINT(result.op_id, 202u);
    CHECK_EQ_UINT(result.action, BLE_CONTROL_ACTION_NONE);
    CHECK_STR_EQ(result.detail, "billows control unavailable");

    static const uint8_t billows_short[4] = {1u, 6u, 203u, 0u};
    CHECK_EQ_UINT(ble_control_handle(billows_short, sizeof(billows_short),
                                     &result),
                  SX4_RESULT_STATUS_INVALID);
    CHECK_EQ_UINT(result.action, BLE_CONTROL_ACTION_NONE);

    CHECK_EQ_INT(s_dispatch_calls, 0);
    ble_control_set_action_handler(NULL, NULL);
}

static void check_routing_edge_cases(void) {
    /* No backend at all. */
    CHECK_EQ_UINT(ble_control_actions_run(NULL, BLE_CONTROL_ACTION_POWER_OFF),
                  SX4_RESULT_STATUS_UNSUPPORTED);

    /* An empty backend reports unsupported per action. */
    ble_control_action_ops_t empty;
    memset(&empty, 0, sizeof(empty));
    CHECK_EQ_UINT(ble_control_actions_run(&empty, BLE_CONTROL_ACTION_FORGET_PHONE),
                  SX4_RESULT_STATUS_UNSUPPORTED);
    CHECK_EQ_UINT(ble_control_actions_run(&empty, BLE_CONTROL_ACTION_NONE),
                  SX4_RESULT_STATUS_UNSUPPORTED);
    CHECK_EQ_UINT(ble_control_actions_run(&empty, (ble_control_action_t)99),
                  SX4_RESULT_STATUS_UNSUPPORTED);

    /* Without a registered handler, a known op is still unsupported. */
    fake_init();
    uint8_t request[3] = {1u, 4u, 1u};
    ble_control_result_t result;
    CHECK_EQ_UINT(ble_control_handle(request, sizeof(request), &result),
                  SX4_RESULT_STATUS_UNSUPPORTED);
    CHECK_EQ_UINT(result.action, BLE_CONTROL_ACTION_NONE);
    CHECK_EQ_UINT(ble_control_run_action(BLE_CONTROL_ACTION_POWER_OFF),
                  SX4_RESULT_STATUS_UNSUPPORTED);
}

int main(void) {
    check_ordering_and_idempotency();
    check_failure_mapping();
    check_malformed_bodies_change_nothing();
    check_unknown_and_billows();
    check_routing_edge_cases();
    return sx4_test_summary("ble-control-actions");
}
