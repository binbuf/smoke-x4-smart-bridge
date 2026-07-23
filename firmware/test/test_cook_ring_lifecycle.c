/* Host tests for the live ring (F5.6) and the session lifecycle rules
 * (F5.4, design 04 §4.6) — table-driven over every start and end
 * condition, including the 40-minute dropout that must NOT end a cook. */
#include <string.h>

#include "cook_lifecycle.h"
#include "cook_ring.h"
#include "record_gen.h"
#include "test_util.h"

/* ── Ring ─────────────────────────────────────────────────────────────── */

static void push_sample(uint32_t t, int16_t p1) {
    cook_ring_sample_t s = {.t = t, .temp = {p1, 0, 0, 0}, .flags = 0,
                            .rssi = -40};
    cook_ring_push(&s);
}

static void test_ring_is_exactly_240_and_wraps(void) {
    cook_ring_reset();
    CHECK_EQ_INT(cook_ring_count(), 0);
    for (int i = 0; i < 500; i++) {
        push_sample((uint32_t)i * 30, (int16_t)i);
    }
    CHECK_EQ_INT(cook_ring_count(), COOK_RING_SIZE);
    CHECK_EQ_INT(cook_ring_get(0)->temp[0], 499);
    CHECK_EQ_INT(cook_ring_get(COOK_RING_SIZE - 1)->temp[0],
                 500 - COOK_RING_SIZE);
    CHECK(cook_ring_get(COOK_RING_SIZE) == NULL);
}

static void test_slope_on_linear_ramp(void) {
    cook_ring_reset();
    /* +1.0 °F per sample at 30 s = +120 °F/hr, exactly. */
    for (int i = 0; i < 30; i++) {
        push_sample((uint32_t)i * 30, (int16_t)(1000 + i * 10));
    }
    float slope = 0;
    CHECK(cook_ring_slope_f_per_hr(0, &slope));
    CHECK(slope > 119.9f && slope < 120.1f);
}

static void test_slope_null_rules(void) {
    /* Fewer than 12 valid samples → no value (A2.2's contract). */
    cook_ring_reset();
    for (int i = 0; i < 11; i++) {
        push_sample((uint32_t)i * 30, 1000);
    }
    float slope;
    CHECK(!cook_ring_slope_f_per_hr(0, &slope));

    /* Detached samples don't count as valid. */
    cook_ring_reset();
    for (int i = 0; i < 20; i++) {
        push_sample((uint32_t)i * 30,
                    i % 2 ? BRIDGE_TEMP_DETACHED : 1000);
    }
    CHECK(!cook_ring_slope_f_per_hr(0, &slope));

    /* A gap > 2 min inside the window voids the slope. */
    cook_ring_reset();
    for (int i = 0; i < 10; i++) {
        push_sample((uint32_t)i * 30, 1000);
    }
    for (int i = 0; i < 10; i++) {
        push_sample(270 + 150 + (uint32_t)i * 30, 1010);
    }
    CHECK(!cook_ring_slope_f_per_hr(0, &slope));
}

/* ── Lifecycle ────────────────────────────────────────────────────────── */

static cook_lc_input_t base_input(uint32_t now_s) {
    cook_lc_input_t in = {0};
    in.now_s = now_s;
    in.paired = true;
    in.sample = true;
    in.any_attached = true;
    in.max_attached_temp_x10 = 2250;
    return in;
}

static void test_start_conditions(void) {
    cook_lifecycle_t lc;
    cook_lifecycle_reset(&lc);

    /* Hot probe → start. */
    cook_lc_input_t in = base_input(100);
    CHECK_EQ_INT(cook_lifecycle_step(&lc, &in), COOK_LC_START);

    /* Cold probe on the counter → no start... */
    in.max_attached_temp_x10 = 750;
    CHECK_EQ_INT(cook_lifecycle_step(&lc, &in), COOK_LC_NONE);
    /* ...unless explicitly started. */
    in.explicit_start = true;
    CHECK_EQ_INT(cook_lifecycle_step(&lc, &in), COOK_LC_START);
    in.explicit_start = false;

    /* Unpaired, probe-less, or silent: never. */
    in.max_attached_temp_x10 = 2250;
    in.paired = false;
    CHECK_EQ_INT(cook_lifecycle_step(&lc, &in), COOK_LC_NONE);
    in.paired = true;
    in.any_attached = false;
    CHECK_EQ_INT(cook_lifecycle_step(&lc, &in), COOK_LC_NONE);
    in.any_attached = true;
    in.sample = false;
    CHECK_EQ_INT(cook_lifecycle_step(&lc, &in), COOK_LC_NONE);

    /* Already open → no second start. */
    in.sample = true;
    cook_lifecycle_note_started(&lc, 100);
    CHECK_EQ_INT(cook_lifecycle_step(&lc, &in), COOK_LC_NONE);
}

static void test_end_all_detached_10_minutes(void) {
    cook_lifecycle_t lc;
    cook_lifecycle_reset(&lc);
    cook_lifecycle_note_started(&lc, 0);

    cook_lc_input_t in = base_input(1000);
    in.any_attached = false;
    CHECK_EQ_INT(cook_lifecycle_step(&lc, &in), COOK_LC_NONE); /* streak on */
    in.now_s = 1000 + 599;
    CHECK_EQ_INT(cook_lifecycle_step(&lc, &in), COOK_LC_NONE);
    in.now_s = 1000 + 600;
    CHECK_EQ_INT(cook_lifecycle_step(&lc, &in), COOK_LC_END_DETACHED);

    /* A reattach mid-streak resets the timer. */
    cook_lifecycle_reset(&lc);
    cook_lifecycle_note_started(&lc, 0);
    in = base_input(1000);
    in.any_attached = false;
    CHECK_EQ_INT(cook_lifecycle_step(&lc, &in), COOK_LC_NONE);
    in.now_s = 1300;
    in.any_attached = true; /* plugged back in */
    CHECK_EQ_INT(cook_lifecycle_step(&lc, &in), COOK_LC_NONE);
    in.now_s = 1400;
    in.any_attached = false;
    CHECK_EQ_INT(cook_lifecycle_step(&lc, &in), COOK_LC_NONE);
    in.now_s = 1400 + 599;
    CHECK_EQ_INT(cook_lifecycle_step(&lc, &in), COOK_LC_NONE);
    in.now_s = 1400 + 600;
    CHECK_EQ_INT(cook_lifecycle_step(&lc, &in), COOK_LC_END_DETACHED);
}

static void test_dropout_does_not_end_the_session(void) {
    cook_lifecycle_t lc;
    cook_lifecycle_reset(&lc);
    cook_lifecycle_note_started(&lc, 0);

    /* 40 minutes of radio silence: no samples arrive, so the caller has
     * nothing to feed — and a later tick without a sample changes
     * nothing. The session stays open (04 §4.6). */
    cook_lc_input_t in = base_input(40 * 60);
    in.sample = false;
    in.any_attached = false; /* unknowable during silence */
    CHECK_EQ_INT(cook_lifecycle_step(&lc, &in), COOK_LC_NONE);

    /* First packet after the gap: still cooking. */
    in.sample = true;
    in.any_attached = true;
    CHECK_EQ_INT(cook_lifecycle_step(&lc, &in), COOK_LC_NONE);
}

static void test_end_stop_cap_unpair(void) {
    cook_lifecycle_t lc;
    cook_lifecycle_reset(&lc);
    cook_lifecycle_note_started(&lc, 0);

    cook_lc_input_t in = base_input(100);
    in.explicit_stop = true;
    CHECK_EQ_INT(cook_lifecycle_step(&lc, &in), COOK_LC_END_STOP);
    in.explicit_stop = false;

    in.now_s = COOK_LC_MAX_SESSION_S; /* 36 h hard cap */
    CHECK_EQ_INT(cook_lifecycle_step(&lc, &in), COOK_LC_END_CAP);

    in.now_s = 200;
    in.unpaired = true;
    CHECK_EQ_INT(cook_lifecycle_step(&lc, &in), COOK_LC_END_UNPAIRED);
}

int main(void) {
    test_ring_is_exactly_240_and_wraps();
    test_slope_on_linear_ramp();
    test_slope_null_rules();
    test_start_conditions();
    test_end_all_detached_10_minutes();
    test_dropout_does_not_end_the_session();
    test_end_stop_cap_unpair();
    return test_summary("test_cook_ring_lifecycle");
}
