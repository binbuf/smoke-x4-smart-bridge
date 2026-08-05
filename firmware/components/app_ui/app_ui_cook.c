/* app_ui_cook.c — the app-confirmed cook clock (see app_ui_cook.h).
 *
 * WHY THE STATE IS ONE WORD. The writer is whichever task took the app's
 * request — httpd for `/cook-clock`, the NimBLE host task for the control
 * write — and the reader is app_ui's 25 Hz render task. They share no mutex:
 * app_ui's s_lock deliberately wraps in-memory work only (a handler over
 * 5 ms trips the F1.3 event-bus guard, which panic-looped a board once
 * already), and taking it from an HTTP handler would put a network task
 * behind the render task for a two-field write.
 *
 * So the clock is stored as ONE aligned 32-bit anchor plus a flag. A 32-bit
 * aligned load or store is indivisible on the ESP32-S3, so a reader sees
 * either the old anchor or the new one and never half of each. Storing
 * elapsed-plus-anchor as a PAIR would reintroduce exactly the tear this
 * avoids — the reader could take the new elapsed against the old anchor —
 * which is why the anchor absorbs the elapsed instead of sitting beside it.
 *
 * The anchor is SIGNED because a cook can predate this boot: the bridge
 * browns out four hours into an overnight, the app reconnects and says "this
 * cook is 4 h old", and the honest anchor is 4 h before uptime zero. An
 * unsigned anchor would have to saturate there and under-report the cook by
 * however long the reboot cost.
 */
#include "app_ui_cook.h"

/* `volatile` is doing one job here: stopping the compiler from hoisting the
 * s_set load out of a caller's loop or reordering the two stores below. */
static volatile bool s_set;
static volatile int32_t s_anchor_s; /* uptime at which the cook began; < 0 =
                                       before this boot */

int app_ui_cook_set(uint32_t elapsed_s, uint32_t now_uptime_s) {
    if (elapsed_s > APP_UI_COOK_MAX_ELAPSED_S) {
        return -1;
    }
    const int64_t anchor = (int64_t)now_uptime_s - (int64_t)elapsed_s;
    if (anchor < INT32_MIN || anchor > INT32_MAX) {
        return -1; /* unreachable at any real uptime; refused, not wrapped */
    }
    /* Anchor first, flag second. A reader that sees s_set true has therefore
     * already seen the anchor that goes with it. */
    s_anchor_s = (int32_t)anchor;
    s_set = true;
    return 0;
}

void app_ui_cook_clear(void) {
    /* Flag first, on the way down: a reader must never see `set` with an
     * anchor that is on its way to meaning nothing. */
    s_set = false;
    s_anchor_s = 0;
}

bool app_ui_cook_get(uint32_t now_uptime_s, uint32_t *elapsed_s) {
    if (!s_set) {
        return false;
    }
    int64_t e = (int64_t)now_uptime_s - (int64_t)s_anchor_s;
    if (e < 0) {
        e = 0; /* the app dated the cook in the future; show 00:00, not a
                  negative time that would format as garbage */
    } else if (e > (int64_t)APP_UI_COOK_MAX_ELAPSED_S) {
        e = (int64_t)APP_UI_COOK_MAX_ELAPSED_S;
    }
    if (elapsed_s != NULL) {
        *elapsed_s = (uint32_t)e;
    }
    return true;
}
