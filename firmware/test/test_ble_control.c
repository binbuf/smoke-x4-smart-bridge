/*
 * test_ble_control.c - host tests for the T29 control dispatcher and result
 * encoder.
 *
 * The real bridge_state core runs over a RAM bridge_config backend and a fake
 * monotonic clock, so `set_time` is checked end to end: bytes in, result out,
 * and the bridge clock/clock_valid updated. No NimBLE and no board are linked.
 */
#include <stdint.h>
#include <stdio.h>
#include <string.h>

#include "ble_control.h"
#include "bridge_config.h"
#include "bridge_state.h"
#include "records.h"
#include "test_util.h"

/* ---- RAM bridge_config backend ------------------------------------------ */

#define FAKE_MAX_ENTRIES 32
#define FAKE_NAME_MAX 16
#define FAKE_VALUE_MAX 64

typedef struct {
    bool used;
    char ns[FAKE_NAME_MAX];
    char key[FAKE_NAME_MAX];
    uint8_t value[FAKE_VALUE_MAX];
    size_t len;
} fake_entry_t;

typedef struct {
    fake_entry_t entries[FAKE_MAX_ENTRIES];
    int set_calls;
} fake_t;

static void fake_init(fake_t *fake) { memset(fake, 0, sizeof(*fake)); }

static fake_entry_t *fake_find(fake_t *fake, const char *ns, const char *key) {
    for (size_t i = 0; i < FAKE_MAX_ENTRIES; i++) {
        if (fake->entries[i].used && strcmp(fake->entries[i].ns, ns) == 0 &&
            strcmp(fake->entries[i].key, key) == 0) {
            return &fake->entries[i];
        }
    }
    return NULL;
}

static fake_entry_t *fake_alloc(fake_t *fake, const char *ns,
                                const char *key) {
    fake_entry_t *entry = fake_find(fake, ns, key);
    if (entry != NULL) {
        return entry;
    }
    for (size_t i = 0; i < FAKE_MAX_ENTRIES; i++) {
        if (!fake->entries[i].used) {
            entry = &fake->entries[i];
            memset(entry, 0, sizeof(*entry));
            entry->used = true;
            snprintf(entry->ns, sizeof(entry->ns), "%s", ns);
            snprintf(entry->key, sizeof(entry->key), "%s", key);
            return entry;
        }
    }
    return NULL;
}

static int fake_get(void *ctx, const char *ns, const char *key, void *dst,
                    size_t *len) {
    fake_t *fake = ctx;
    fake_entry_t *entry = fake_find(fake, ns, key);
    if (entry == NULL) {
        return BRIDGE_CONFIG_ERR_NOT_FOUND;
    }
    if (*len < entry->len) {
        return BRIDGE_CONFIG_ERR_INVALID;
    }
    memcpy(dst, entry->value, entry->len);
    *len = entry->len;
    return BRIDGE_CONFIG_OK;
}

static int fake_set(void *ctx, const char *ns, const char *key, const void *src,
                    size_t len) {
    fake_t *fake = ctx;
    if (len > FAKE_VALUE_MAX) {
        return BRIDGE_CONFIG_ERR_INVALID;
    }
    fake_entry_t *entry = fake_alloc(fake, ns, key);
    if (entry == NULL) {
        return BRIDGE_CONFIG_ERR_IO;
    }
    memcpy(entry->value, src, len);
    entry->len = len;
    fake->set_calls++;
    return BRIDGE_CONFIG_OK;
}

static int fake_erase(void *ctx, const char *ns, const char *key) {
    fake_t *fake = ctx;
    fake_entry_t *entry = fake_find(fake, ns, key);
    if (entry == NULL) {
        return BRIDGE_CONFIG_ERR_NOT_FOUND;
    }
    memset(entry, 0, sizeof(*entry));
    return BRIDGE_CONFIG_OK;
}

static const bridge_config_kv_ops_t kFakeOps = {
    .get = fake_get,
    .set = fake_set,
    .erase = fake_erase,
};

static uint32_t fake_random(void *ctx) {
    (void)ctx;
    return 0x12345678u;
}

static void config_init(fake_t *fake) {
    bridge_config_kv_t kv = {.ops = &kFakeOps, .ctx = fake};
    bridge_config_set_random_source(fake_random, NULL);
    CHECK_EQ_INT(bridge_config_core_init(&kv), BRIDGE_CONFIG_OK);
}

/* ---- controllable clock -------------------------------------------------- */

typedef struct {
    uint64_t now_ms;
} clock_fake_t;

static uint64_t clock_now(void *ctx) {
    clock_fake_t *clock = ctx;
    return clock->now_ms;
}

static void state_init(fake_t *fake, clock_fake_t *clock) {
    fake_init(fake);
    config_init(fake);
    bridge_state_time_source_t source = {
        .uptime_ms = clock_now,
        .ctx = clock,
    };
    CHECK_EQ_INT(bridge_state_core_init(&source, 0), BRIDGE_STATE_OK);
}

/* ---- request builders ---------------------------------------------------- */

static size_t build_set_time(uint8_t *out, uint8_t op_id, uint64_t unix_ms,
                             int16_t tz_offset_min) {
    sx4_control_t envelope = {.ver = 1, .op = 1, .op_id = op_id};
    sx4_control_set_time_body_t body = {
        .unix_ms = unix_ms,
        .tz_offset_min = tz_offset_min,
    };
    size_t n = sx4_control_encode(&envelope, out, SX4_BLE_CONTROL_MAX_SIZE);
    n += sx4_control_set_time_body_encode(&body, out + n,
                                          SX4_BLE_CONTROL_MAX_SIZE - n);
    return n;
}

static uint8_t handle(const uint8_t *in, size_t len,
                      ble_control_result_t *result) {
    return ble_control_handle(in, len, result);
}

static void check_result_envelope(const ble_control_result_t *result,
                                  uint8_t op, uint8_t op_id, uint8_t status) {
    CHECK_EQ_UINT(result->ver, 1u);
    CHECK_EQ_UINT(result->op, op);
    CHECK_EQ_UINT(result->op_id, op_id);
    CHECK_EQ_UINT(result->status, status);
}

/* ---- reply-first action seam -------------------------------------------- */

static int s_action_calls;
static ble_control_action_t s_last_action;

static void test_action_handler(ble_control_action_t action, void *ctx) {
    (void)ctx;
    s_action_calls++;
    s_last_action = action;
}

/* ---- tests --------------------------------------------------------------- */

static void check_set_time_round_trip(void) {
    fake_t fake;
    clock_fake_t clock = {.now_ms = 5000};
    state_init(&fake, &clock);

    uint8_t request[SX4_BLE_CONTROL_MAX_SIZE];
    size_t len = build_set_time(request, 42, 1700000000123ull, -300);
    CHECK_EQ_UINT(len, 13u);

    ble_control_result_t result;
    CHECK_EQ_UINT(handle(request, len, &result), SX4_RESULT_STATUS_OK);
    check_result_envelope(&result, SX4_CONTROL_OP_SET_TIME, 42,
                          SX4_RESULT_STATUS_OK);
    CHECK_STR_EQ(result.detail, "clock set");

    /* The result echoes op/op_id and carries status ok. */
    uint8_t encoded[SX4_RESULT_SIZE];
    size_t n = ble_control_encode_result(&result, encoded, sizeof(encoded));
    CHECK_EQ_UINT(n, 5u + strlen("clock set"));
    CHECK_EQ_UINT(encoded[0], 1u);
    CHECK_EQ_UINT(encoded[1], SX4_CONTROL_OP_SET_TIME);
    CHECK_EQ_UINT(encoded[2], 42u);
    CHECK_EQ_UINT(encoded[3], SX4_RESULT_STATUS_OK);
    CHECK_EQ_UINT(encoded[4], strlen("clock set"));
    CHECK(memcmp(encoded + 5, "clock set", strlen("clock set")) == 0);

    /* The bridge clock and its valid flag advanced. */
    bridge_state_clock_t now;
    CHECK_EQ_INT(bridge_state_now(&now), BRIDGE_STATE_OK);
    CHECK(now.valid);
    CHECK(!now.estimated);
    CHECK_EQ_UINT(now.unix_s, 1700000000u);

    bridge_state_live_t live;
    CHECK_EQ_INT(bridge_state_snapshot(&live), BRIDGE_STATE_OK);
    CHECK((live.flags & SX4_LIVE_FLAG_CLOCK_VALID) != 0u);

    /* A later set_time is accepted and moves the base forward. */
    clock.now_ms += 2500;
    len = build_set_time(request, 43, 1700000010000ull, 60);
    CHECK_EQ_UINT(handle(request, len, &result), SX4_RESULT_STATUS_OK);
    CHECK_EQ_UINT(result.op_id, 43u);
    CHECK_EQ_INT(bridge_state_now(&now), BRIDGE_STATE_OK);
    CHECK_EQ_UINT(now.unix_s, 1700000010u);
}

static void check_wrong_length_changes_nothing(void) {
    fake_t fake;
    clock_fake_t clock = {.now_ms = 1000};
    state_init(&fake, &clock);

    /* Establish a known clock. */
    uint8_t request[SX4_BLE_CONTROL_MAX_SIZE];
    size_t len = build_set_time(request, 1, 1600000000000ull, 0);
    ble_control_result_t result;
    CHECK_EQ_UINT(handle(request, len, &result), SX4_RESULT_STATUS_OK);

    bridge_state_clock_t before;
    CHECK_EQ_INT(bridge_state_now(&before), BRIDGE_STATE_OK);
    CHECK_EQ_UINT(before.unix_s, 1600000000u);

    /* One byte short: 2-byte body rather than 10. */
    len = build_set_time(request, 2, 1700000000000ull, 0) - 1u;
    CHECK_EQ_UINT(handle(request, len, &result), SX4_RESULT_STATUS_INVALID);
    check_result_envelope(&result, SX4_CONTROL_OP_SET_TIME, 2,
                          SX4_RESULT_STATUS_INVALID);
    CHECK_STR_EQ(result.detail, "bad set_time length");

    /* One byte long: the trailing byte is not silently ignored. */
    len = build_set_time(request, 3, 1700000000000ull, 0);
    request[len] = 0xAA;
    CHECK_EQ_UINT(handle(request, len + 1u, &result),
                  SX4_RESULT_STATUS_INVALID);
    check_result_envelope(&result, SX4_CONTROL_OP_SET_TIME, 3,
                          SX4_RESULT_STATUS_INVALID);

    /* Too short for the 3-byte envelope. */
    static const uint8_t truncated[2] = {1u, 1u};
    CHECK_EQ_UINT(handle(truncated, sizeof(truncated), &result),
                  SX4_RESULT_STATUS_INVALID);
    CHECK_STR_EQ(result.detail, "malformed control");

    /* Right length but wrong ver. */
    len = build_set_time(request, 4, 1700000000000ull, 0);
    request[0] = 2u;
    CHECK_EQ_UINT(handle(request, len, &result), SX4_RESULT_STATUS_INVALID);
    check_result_envelope(&result, SX4_CONTROL_OP_SET_TIME, 4,
                          SX4_RESULT_STATUS_INVALID);
    CHECK_STR_EQ(result.detail, "unsupported version");

    /* Clock zero is not a time. */
    len = build_set_time(request, 5, 0u, 0);
    CHECK_EQ_UINT(handle(request, len, &result), SX4_RESULT_STATUS_INVALID);
    CHECK_STR_EQ(result.detail, "clock out of range");

    /* Backward correction is refused, matching bridge_state. */
    len = build_set_time(request, 6, 1500000000000ull, 0);
    CHECK_EQ_UINT(handle(request, len, &result), SX4_RESULT_STATUS_INVALID);
    CHECK_STR_EQ(result.detail, "clock out of range");

    bridge_state_clock_t after;
    CHECK_EQ_INT(bridge_state_now(&after), BRIDGE_STATE_OK);
    CHECK_EQ_UINT(after.unix_s, before.unix_s);
}

static void check_op_dispatch(void) {
    fake_t fake;
    clock_fake_t clock = {.now_ms = 0};
    state_init(&fake, &clock);

    ble_control_result_t result;
    uint8_t request[SX4_BLE_CONTROL_MAX_SIZE];

    /* Unknown op: unsupported, with the app's op_id echoed unchanged. */
    static const uint8_t unknown[3] = {1u, 99u, 200u};
    CHECK_EQ_UINT(handle(unknown, sizeof(unknown), &result),
                  SX4_RESULT_STATUS_UNSUPPORTED);
    check_result_envelope(&result, 99u, 200u, SX4_RESULT_STATUS_UNSUPPORTED);
    CHECK_STR_EQ(result.detail, "unknown op");

    /* A known op with the wrong body length is invalid, not unsupported. */
    static const uint8_t forget_with_body[4] = {1u, 2u, 7u, 0u};
    CHECK_EQ_UINT(handle(forget_with_body, sizeof(forget_with_body), &result),
                  SX4_RESULT_STATUS_INVALID);
    check_result_envelope(&result, 2u, 7u, SX4_RESULT_STATUS_INVALID);

    /* Destructive ops understand their empty-body shape but are unsupported
     * until T48 installs the handlers. */
    static const uint8_t destructive_ops[] = {2u, 3u, 4u, 5u, 7u};
    for (size_t i = 0; i < sizeof(destructive_ops); i++) {
        request[0] = 1u;
        request[1] = destructive_ops[i];
        request[2] = (uint8_t)(10u + i);
        CHECK_EQ_UINT(handle(request, 3u, &result),
                      SX4_RESULT_STATUS_UNSUPPORTED);
        check_result_envelope(&result, destructive_ops[i],
                              (uint8_t)(10u + i),
                              SX4_RESULT_STATUS_UNSUPPORTED);
        CHECK_STR_EQ(result.detail, "not available in this build");
    }

    /* set_billows_target is reserved and always unsupported in the MVP. */
    static const uint8_t billows[5] = {1u, 6u, 33u, 0xCAu, 0x08u};
    CHECK_EQ_UINT(handle(billows, sizeof(billows), &result),
                  SX4_RESULT_STATUS_UNSUPPORTED);
    check_result_envelope(&result, 6u, 33u, SX4_RESULT_STATUS_UNSUPPORTED);
    CHECK_STR_EQ(result.detail, "billows control unavailable");

    static const uint8_t billows_short[4] = {1u, 6u, 34u, 0u};
    CHECK_EQ_UINT(handle(billows_short, sizeof(billows_short), &result),
                  SX4_RESULT_STATUS_INVALID);
    CHECK_STR_EQ(result.detail, "bad body length");
}

static void check_every_status_and_truncation(void) {
    uint8_t encoded[SX4_RESULT_SIZE];

    for (uint8_t status = 0; status <= 7u; status++) {
        ble_control_result_t result;
        memset(&result, 0, sizeof(result));
        result.ver = 1;
        result.op = SX4_CONTROL_OP_SET_TIME;
        result.op_id = 77;
        result.status = status;
        snprintf(result.detail, sizeof(result.detail), "%s",
                 ble_control_status_detail(status));

        size_t n =
            ble_control_encode_result(&result, encoded, sizeof(encoded));
        CHECK_EQ_UINT(n, 5u + strlen(result.detail));
        CHECK_EQ_UINT(encoded[0], 1u);
        CHECK_EQ_UINT(encoded[1], SX4_CONTROL_OP_SET_TIME);
        CHECK_EQ_UINT(encoded[2], 77u);
        CHECK_EQ_UINT(encoded[3], status);
        CHECK_EQ_UINT(encoded[4], strlen(result.detail));
        CHECK(memcmp(encoded + 5, result.detail, strlen(result.detail)) == 0);
        CHECK(ble_control_status_detail(status) != NULL);
    }
    /* The list covers every status code in the contract. */
    CHECK_STR_EQ(ble_control_status_detail(SX4_RESULT_STATUS_OK), "ok");
    CHECK_STR_EQ(ble_control_status_detail(SX4_RESULT_STATUS_INVALID),
                 "invalid request");
    CHECK_STR_EQ(ble_control_status_detail(SX4_RESULT_STATUS_UNSUPPORTED),
                 "unsupported");
    CHECK_STR_EQ(ble_control_status_detail(SX4_RESULT_STATUS_BUSY), "busy");
    CHECK_STR_EQ(ble_control_status_detail(SX4_RESULT_STATUS_UNAUTHORIZED),
                 "not authorized");
    CHECK_STR_EQ(ble_control_status_detail(SX4_RESULT_STATUS_FAILED), "failed");
    CHECK_STR_EQ(ble_control_status_detail(SX4_RESULT_STATUS_NOT_FOUND),
                 "not found");
    CHECK_STR_EQ(ble_control_status_detail(SX4_RESULT_STATUS_STORAGE),
                 "storage unavailable");

    /* Detail caps at 59 bytes, so the frame caps at 64. */
    ble_control_result_t result;
    memset(&result, 0, sizeof(result));
    result.ver = 1;
    result.op = 1;
    result.op_id = 9;
    result.status = SX4_RESULT_STATUS_FAILED;
    memset(result.detail, 'A', BLE_CONTROL_DETAIL_MAX);
    result.detail[BLE_CONTROL_DETAIL_MAX] = '\0';

    size_t n = ble_control_encode_result(&result, encoded, sizeof(encoded));
    CHECK_EQ_UINT(n, SX4_RESULT_SIZE);
    CHECK_EQ_UINT(encoded[4], BLE_CONTROL_DETAIL_MAX);
    for (size_t i = 0; i < BLE_CONTROL_DETAIL_MAX; i++) {
        CHECK_EQ_UINT(encoded[5 + i], 'A');
    }

    /* A smaller output buffer truncates the detail, never the header. */
    n = ble_control_encode_result(&result, encoded, 20u);
    CHECK_EQ_UINT(n, 20u);
    CHECK_EQ_UINT(encoded[4], 15u);
    for (size_t i = 0; i < 15u; i++) {
        CHECK_EQ_UINT(encoded[5 + i], 'A');
    }

    /* Truncation never splits a UTF-8 sequence: 58 'A' + 2-byte e-acute is
     * 60 bytes, capped at 59, so the e-acute is dropped whole. */
    memset(&result, 0, sizeof(result));
    result.ver = 1;
    result.status = SX4_RESULT_STATUS_OK;
    memset(result.detail, 'A', 58u);
    result.detail[58] = (char)0xC3;
    result.detail[59] = (char)0xA9;
    result.detail[60] = '\0';
    n = ble_control_encode_result(&result, encoded, sizeof(encoded));
    CHECK_EQ_UINT(n, 5u + 58u);
    CHECK_EQ_UINT(encoded[4], 58u);
    CHECK_EQ_UINT(encoded[5 + 57], 'A');

    /* Bad arguments. */
    CHECK_EQ_UINT(ble_control_encode_result(NULL, encoded, sizeof(encoded)), 0u);
    CHECK_EQ_UINT(ble_control_encode_result(&result, NULL, sizeof(encoded)), 0u);
    CHECK_EQ_UINT(ble_control_encode_result(&result, encoded, 4u), 0u);
}

static void check_write_security(void) {
    CHECK_EQ_INT(ble_control_write_security(false, false),
                 BLE_CONTROL_ATT_INSUFFICIENT_ENC);
    CHECK_EQ_INT(ble_control_write_security(false, true),
                 BLE_CONTROL_ATT_INSUFFICIENT_ENC);
    CHECK_EQ_INT(ble_control_write_security(true, false),
                 BLE_CONTROL_ATT_INSUFFICIENT_AUTHEN);
    CHECK_EQ_INT(ble_control_write_security(true, true), BLE_CONTROL_ATT_OK);
    CHECK_EQ_UINT(BLE_CONTROL_ATT_INSUFFICIENT_ENC, 0x0Fu);
    CHECK_EQ_UINT(BLE_CONTROL_ATT_INSUFFICIENT_AUTHEN, 0x05u);
}

static void check_action_seam(void) {
    fake_t fake;
    clock_fake_t clock = {.now_ms = 0};
    state_init(&fake, &clock);

    s_action_calls = 0;
    s_last_action = BLE_CONTROL_ACTION_NONE;

    /* Without a handler the destructive op stays unsupported. */
    ble_control_result_t result;
    static const uint8_t factory_reset[3] = {1u, 3u, 44u};
    CHECK_EQ_UINT(handle(factory_reset, sizeof(factory_reset), &result),
                  SX4_RESULT_STATUS_UNSUPPORTED);
    CHECK_EQ_UINT(result.action, BLE_CONTROL_ACTION_NONE);

    /* With T48's handler installed the dispatcher only plans the action; the
     * adapter runs it after the result has been notified. */
    ble_control_set_action_handler(test_action_handler, NULL);

    CHECK_EQ_UINT(handle(factory_reset, sizeof(factory_reset), &result),
                  SX4_RESULT_STATUS_OK);
    check_result_envelope(&result, 3u, 44u, SX4_RESULT_STATUS_OK);
    CHECK_EQ_UINT(result.action, BLE_CONTROL_ACTION_FACTORY_RESET);
    CHECK_EQ_UINT(result.action_delay_ms, BLE_CONTROL_ACTION_DELAY_MS);
    CHECK_EQ_UINT(result.action_delay_ms, 250u);
    CHECK_EQ_INT(s_action_calls, 0); /* not run inside the dispatcher */

    ble_control_run_action((ble_control_action_t)result.action);
    CHECK_EQ_INT(s_action_calls, 1);
    CHECK_EQ_INT(s_last_action, (int)BLE_CONTROL_ACTION_FACTORY_RESET);

    ble_control_set_action_handler(NULL, NULL);
}

int main(void) {
    check_set_time_round_trip();
    check_wrong_length_changes_nothing();
    check_op_dispatch();
    check_every_status_and_truncation();
    check_write_security();
    check_action_seam();
    return sx4_test_summary("ble-control");
}
