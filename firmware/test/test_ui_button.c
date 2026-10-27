/*
 * test_ui_button.c - host coverage for the PRG gesture machine and the
 * hold-to-wake boot confirmation (T23, design 07 section 7.4).
 *
 * The machine is pure C with an injected 20 ms sample clock. These tests drive
 * exact millisecond timestamps so the 400 ms tap/hold and 1.5 s commit
 * boundaries are checked on both sides.
 */
#include <stdbool.h>
#include <stdint.h>

#include "test_util.h"
#include "ui_button.h"

/* Most samples are "display already awake". */
static ui_button_event_t step(ui_button_t *b, bool pressed, uint64_t now_ms) {
    return ui_button_sample(b, pressed, now_ms, false);
}

static void test_timing_contract(void) {
    CHECK_EQ_UINT(UI_BUTTON_SAMPLE_MS, 20u);
    CHECK_EQ_UINT(UI_BUTTON_DEBOUNCE_MS, 30u);
    CHECK_EQ_UINT(UI_BUTTON_TAP_MAX_MS, 400u);
    CHECK_EQ_UINT(UI_BUTTON_HOLD_MS, 1500u);
    CHECK_EQ_UINT(UI_BUTTON_COUNTDOWN_FROM_MS, 400u);
}

/* First raw press at t=20, debounced at t=50; pressed_since is t=20. */
static void press(ui_button_t *b, uint64_t *now, bool consume) {
    CHECK_EQ_INT(ui_button_sample(b, true, 20u, consume), UI_BUTTON_EVENT_NONE);
    *now = 20u;
    CHECK_EQ_INT(ui_button_sample(b, true, 50u, consume),
                 UI_BUTTON_EVENT_PRESS);
    *now = 50u;
}

/* Release raw at press_since + held_ms, debounced 30 ms later. */
static ui_button_event_t release_at(ui_button_t *b, uint64_t *now,
                                    uint64_t held_ms) {
    uint64_t raw_release = 20u + held_ms;
    /* The raw edge may itself emit a countdown tick; the debounced sample is
     * the one that decides tap/cancel/commit. */
    (void)step(b, false, raw_release);
    ui_button_event_t event = step(b, false, raw_release + 30u);
    *now = raw_release + 30u;
    return event;
}

static void test_debounce(void) {
    ui_button_t b;
    uint64_t now = 0u;
    ui_button_init(&b, false, now, false);

    /* A 20 ms glitch never becomes a press and therefore never becomes a tap. */
    CHECK_EQ_INT(step(&b, true, 20u), UI_BUTTON_EVENT_NONE);
    CHECK_EQ_INT(step(&b, false, 40u), UI_BUTTON_EVENT_NONE);
    CHECK_EQ_INT(step(&b, false, 70u), UI_BUTTON_EVENT_NONE);

    /* A press held through the 30 ms window does register. */
    CHECK_EQ_INT(step(&b, true, 100u), UI_BUTTON_EVENT_NONE);
    CHECK_EQ_INT(step(&b, true, 130u), UI_BUTTON_EVENT_PRESS);
}

static void test_tap(void) {
    ui_button_t b;
    uint64_t now = 0u;
    ui_button_init(&b, false, now, false);
    press(&b, &now, false);

    /* 399 ms is still a tap. */
    CHECK_EQ_INT(release_at(&b, &now, 399u), UI_BUTTON_EVENT_TAP);
    CHECK_EQ_INT(ui_button_countdown_s(&b, now), 0u);

    /* Re-arm and release exactly at 400 ms: countdown, not a tap. */
    ui_button_init(&b, false, 1000u, false);
    CHECK_EQ_INT(step(&b, true, 1020u), UI_BUTTON_EVENT_NONE);
    CHECK_EQ_INT(step(&b, true, 1050u), UI_BUTTON_EVENT_PRESS);
    /* The raw release at 1420 ms (400 ms hold) starts the debounce window, so
     * the countdown appears for one sample and then the release cancels it. */
    CHECK_EQ_INT(step(&b, false, 1420u), UI_BUTTON_EVENT_HOLD_START);
    CHECK_EQ_INT(step(&b, false, 1450u), UI_BUTTON_EVENT_HOLD_CANCEL);
}

static void test_hold_countdown_and_commit(void) {
    ui_button_t b;
    uint64_t now = 0u;
    ui_button_init(&b, false, now, false);
    press(&b, &now, false);

    /* ~400 ms: countdown appears with "2". */
    CHECK_EQ_INT(step(&b, true, 420u), UI_BUTTON_EVENT_HOLD_START);
    CHECK_EQ_UINT(ui_button_countdown_s(&b, 420u), 2u);

    /* ~500 ms: "1". */
    CHECK_EQ_INT(step(&b, true, 520u), UI_BUTTON_EVENT_HOLD_TICK);
    CHECK_EQ_UINT(ui_button_countdown_s(&b, 520u), 1u);

    /* No digit churn between ticks. */
    CHECK_EQ_INT(step(&b, true, 600u), UI_BUTTON_EVENT_NONE);

    /* At 1.5 s: "release to confirm" (0). */
    CHECK_EQ_INT(step(&b, true, 1520u), UI_BUTTON_EVENT_HOLD_TICK);
    CHECK_EQ_UINT(ui_button_countdown_s(&b, 1520u), 0u);

    /* Release after the threshold commits. */
    CHECK_EQ_INT(step(&b, false, 1600u), UI_BUTTON_EVENT_NONE);
    CHECK_EQ_INT(step(&b, false, 1630u), UI_BUTTON_EVENT_HOLD_COMMIT);
}

static void test_early_release_cancels(void) {
    ui_button_t b;
    uint64_t now = 0u;
    ui_button_init(&b, false, now, false);
    press(&b, &now, false);

    CHECK_EQ_INT(step(&b, true, 420u), UI_BUTTON_EVENT_HOLD_START);
    /* Releasing at 1499 ms (raw edge) cancels, not commits. */
    CHECK_EQ_INT(release_at(&b, &now, 1499u), UI_BUTTON_EVENT_HOLD_CANCEL);
    CHECK_EQ_UINT(ui_button_countdown_s(&b, now), 0u);
}

static void test_tap_during_countdown_does_nothing(void) {
    ui_button_t b;
    uint64_t now = 0u;
    ui_button_init(&b, false, now, false);
    press(&b, &now, false);

    CHECK_EQ_INT(step(&b, true, 420u), UI_BUTTON_EVENT_HOLD_START);

    /* A bounce shorter than the debounce window is not a release. It produces
     * no event and does not cancel the countdown; only a real release does. */
    CHECK_EQ_INT(step(&b, false, 430u), UI_BUTTON_EVENT_NONE);
    CHECK_EQ_INT(step(&b, true, 450u), UI_BUTTON_EVENT_NONE);
    CHECK(ui_button_countdown_s(&b, 500u) > 0u);

    CHECK_EQ_INT(step(&b, false, 600u), UI_BUTTON_EVENT_HOLD_TICK);
    CHECK_EQ_INT(step(&b, false, 630u), UI_BUTTON_EVENT_HOLD_CANCEL);
}

static void test_waking_press_consumed(void) {
    ui_button_t b;
    uint64_t now = 0u;
    ui_button_init(&b, false, now, false);

    /* The display was asleep at the press edge: wake only, no tap. */
    press(&b, &now, true);
    CHECK_EQ_INT(release_at(&b, &now, 120u), UI_BUTTON_EVENT_NONE);

    /* A waking long press is consumed too: no countdown and no commit. */
    ui_button_init(&b, false, 1000u, false);
    CHECK_EQ_INT(step(&b, true, 1020u), UI_BUTTON_EVENT_NONE);
    CHECK_EQ_INT(ui_button_sample(&b, true, 1050u, true),
                 UI_BUTTON_EVENT_PRESS);
    for (uint64_t t = 1100u; t <= 2800u; t += 20u) {
        CHECK_EQ_INT(step(&b, true, t), UI_BUTTON_EVENT_NONE);
    }
    CHECK_EQ_UINT(ui_button_countdown_s(&b, 2000u), 0u);
    CHECK_EQ_INT(step(&b, false, 2900u), UI_BUTTON_EVENT_NONE);
    CHECK_EQ_INT(step(&b, false, 2930u), UI_BUTTON_EVENT_NONE);
}

static void test_boot_hold_confirmation(void) {
    ui_boot_hold_t hold;
    ui_boot_hold_init(&hold, true, 0u);

    CHECK_EQ_INT(ui_boot_hold_sample(&hold, true, 20u), UI_BOOT_HOLD_WAIT);
    CHECK_EQ_INT(ui_boot_hold_sample(&hold, true, 1499u), UI_BOOT_HOLD_WAIT);
    CHECK_EQ_INT(ui_boot_hold_sample(&hold, true, 1500u),
                 UI_BOOT_HOLD_CONFIRMED);

    /* An early release goes back to sleep. */
    ui_boot_hold_init(&hold, true, 0u);
    CHECK_EQ_INT(ui_boot_hold_sample(&hold, true, 1480u), UI_BOOT_HOLD_WAIT);
    CHECK_EQ_INT(ui_boot_hold_sample(&hold, false, 1490u),
                 UI_BOOT_HOLD_RELEASED);

    /* No button at all on a spurious wake means sleep immediately. */
    ui_boot_hold_init(&hold, false, 0u);
    CHECK_EQ_INT(ui_boot_hold_sample(&hold, false, 20u),
                 UI_BOOT_HOLD_RELEASED);
}

int main(void) {
    test_timing_contract();
    test_debounce();
    test_tap();
    test_hold_countdown_and_commit();
    test_early_release_cancels();
    test_tap_during_countdown_does_nothing();
    test_waking_press_consumed();
    test_boot_hold_confirmation();
    return sx4_test_summary("ui-button");
}
