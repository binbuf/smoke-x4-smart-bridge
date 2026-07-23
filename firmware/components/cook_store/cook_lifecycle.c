/* cook_lifecycle — session start/end decisions (F5.4, 04 §4.6). */
#include "cook_lifecycle.h"

#include <string.h>

void cook_lifecycle_reset(cook_lifecycle_t *lc) {
    memset(lc, 0, sizeof *lc);
}

void cook_lifecycle_note_started(cook_lifecycle_t *lc, uint32_t now_s) {
    lc->session_open = true;
    lc->session_started_s = now_s;
    lc->detached_streak = false;
}

void cook_lifecycle_note_ended(cook_lifecycle_t *lc) {
    lc->session_open = false;
    lc->detached_streak = false;
}

cook_lc_action_t cook_lifecycle_step(cook_lifecycle_t *lc,
                                     const cook_lc_input_t *in) {
    if (!lc->session_open) {
        /* Start: paired ∧ receiving ∧ ≥1 probe attached ∧ (hot OR asked). */
        if (in->paired && in->sample && in->any_attached &&
            (in->max_attached_temp_x10 >= COOK_LC_START_TEMP_X10 ||
             in->explicit_start)) {
            return COOK_LC_START;
        }
        return COOK_LC_NONE;
    }

    if (in->unpaired) {
        return COOK_LC_END_UNPAIRED;
    }
    if (in->explicit_stop) {
        return COOK_LC_END_STOP;
    }
    if (in->now_s - lc->session_started_s >= COOK_LC_MAX_SESSION_S) {
        return COOK_LC_END_CAP;
    }

    /* The detached streak advances only on samples that SAY detached; a
     * silent radio leaves the session open. */
    if (in->sample) {
        if (in->any_attached) {
            lc->detached_streak = false;
        } else {
            if (!lc->detached_streak) {
                lc->detached_streak = true;
                lc->detached_since_s = in->now_s;
            } else if (in->now_s - lc->detached_since_s >=
                       COOK_LC_DETACHED_END_S) {
                return COOK_LC_END_DETACHED;
            }
        }
    }
    return COOK_LC_NONE;
}
