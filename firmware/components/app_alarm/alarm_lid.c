/* alarm_lid.c — the lid-open detector (F13.5; design 09 §9.4).
 *
 * A port of app/lib/domain/analysis/lid_open.dart, which is the settled
 * implementation with the constants already argued and table-tested. This
 * file owns no new decisions; any constant that differs between the two is
 * a defect in one of them, and test_app_alarm.c asserts them equal.
 *
 *   detect:  pit drops ≥ 25 °F within any 3-minute window
 *   confirm: recovers ≥ 50 % of the drop within 20 min → it was a lid open
 *            does not recover                          → escalate to pit_crash
 *
 * Firing on DETECTION is what starts the pit-alarm grace window
 * immediately; confirming afterwards is what lets a genuine fire failure
 * still escalate 20 minutes later. Suppressing a real pit_crash is the
 * expensive failure, so both branches exist and both are tested.
 */
#include "app_alarm_core.h"

#include <string.h>

static bool attached(int16_t f10) {
    return f10 != BRIDGE_TEMP_DETACHED && f10 != BRIDGE_TEMP_INVALID;
}

void app_alarm_lid_reset(app_alarm_lid_t *l) {
    if (l != NULL) {
        memset(l, 0, sizeof *l);
    }
}

bool app_alarm_lid_pending(const app_alarm_lid_t *l) {
    return l != NULL && l->active;
}

/* Drops points older than the 3-minute window, then appends. The ring is
 * 16 deep against 6 samples at the 30 s cadence, so the window bound —
 * not the capacity — is what evicts under normal operation. */
static void push_recent(app_alarm_lid_t *l, uint32_t t, int16_t f10) {
    int w = 0;
    for (int i = 0; i < l->n; i++) {
        if (l->recent[i].t + APP_ALARM_LID_WINDOW_S >= t) {
            l->recent[w++] = l->recent[i];
        }
    }
    l->n = w;
    if (l->n == APP_ALARM_LID_RING) {
        /* Full despite the window: a burst of samples. Drop the oldest,
         * which is also the least likely to be the reference maximum. */
        memmove(&l->recent[0], &l->recent[1],
                sizeof l->recent[0] * (APP_ALARM_LID_RING - 1));
        l->n--;
    }
    l->recent[l->n].t = t;
    l->recent[l->n].f10 = f10;
    l->n++;
}

app_alarm_lid_evt_t app_alarm_lid_add(app_alarm_lid_t *l, uint32_t t,
                                      int16_t pit_f10) {
    if (l == NULL || !attached(pit_f10)) {
        /* A detached pit is skipped, not read as a 3276.8 °F drop. */
        return APP_ALARM_LID_NONE;
    }

    if (!l->active) {
        /* Evict, then compare against the window's maximum — the same
         * order lid_open.dart uses, and it matters: the current sample is
         * appended only after the comparison, so a single reading can
         * never be its own reference. */
        int w = 0;
        for (int i = 0; i < l->n; i++) {
            if (l->recent[i].t + APP_ALARM_LID_WINDOW_S >= t) {
                l->recent[w++] = l->recent[i];
            }
        }
        l->n = w;
        if (l->n > 0) {
            int16_t ref = l->recent[0].f10;
            for (int i = 1; i < l->n; i++) {
                if (l->recent[i].f10 > ref) {
                    ref = l->recent[i].f10;
                }
            }
            if ((int32_t)ref - (int32_t)pit_f10 >= APP_ALARM_LID_DROP_F10) {
                l->active = true;
                l->reference_f10 = ref;
                l->low_f10 = pit_f10;
                l->detect_t = t;
                l->n = 0;
                return APP_ALARM_LID_DETECTED;
            }
        }
        push_recent(l, t, pit_f10);
        return APP_ALARM_LID_NONE;
    }

    if (pit_f10 < l->low_f10) {
        l->low_f10 = pit_f10;
    }
    const int32_t drop = (int32_t)l->reference_f10 - (int32_t)l->low_f10;
    const int32_t recovered = (int32_t)pit_f10 - (int32_t)l->low_f10;
    if (recovered * APP_ALARM_LID_RECOVER_DEN >=
        drop * APP_ALARM_LID_RECOVER_NUM) {
        l->active = false;
        l->n = 0;
        push_recent(l, t, pit_f10);
        return APP_ALARM_LID_CONFIRMED;
    }
    if (t - l->detect_t >= APP_ALARM_LID_CONFIRM_S) {
        l->active = false;
        l->n = 0;
        push_recent(l, t, pit_f10);
        return APP_ALARM_LID_ESCALATED;
    }
    return APP_ALARM_LID_NONE;
}
