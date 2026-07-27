/* cook_lifecycle — the automatic session start/end rules (F5.4, 04 §4.6,
 * amended A25).
 *
 * A pure decision function: the caller feeds observations, the function
 * returns the action. Sessions start automatically — asking the user to
 * press start before an 18-hour brisket is a design that loses data.
 *
 * A25 removed the 90 °F start gate: recording begins at power-on + sync
 * (paired, receiving, a probe attached), so the fire-lighting and
 * stabilisation stretch is captured, and a cook who never opens the app
 * until hours in still finds the whole history waiting.
 */
#ifndef COOK_LIFECYCLE_H
#define COOK_LIFECYCLE_H

#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/* All probes detached this long ends the session. */
#define COOK_LC_DETACHED_END_S (10u * 60u)
/* Hard cap; a longer cook continues in a new session. */
#define COOK_LC_MAX_SESSION_S (36u * 3600u)

typedef enum {
    COOK_LC_NONE = 0,
    COOK_LC_START,
    COOK_LC_END_DETACHED,
    COOK_LC_END_STOP,
    COOK_LC_END_CAP,      /* caller closes AND opens a continuation */
    COOK_LC_END_UNPAIRED,
} cook_lc_action_t;

typedef struct {
    bool session_open;
    uint32_t session_started_s; /* uptime when the session opened */
    /* internal: detached streak tracking */
    bool detached_streak;
    uint32_t detached_since_s;
} cook_lifecycle_t;

typedef struct {
    uint32_t now_s;   /* uptime */
    bool paired;
    bool sample;      /* this step carries a received sample */
    bool any_attached;
    /* App-requested start. With the A25 always-record rule an attached probe
     * already starts the session, so this only documents intent; it does NOT
     * bypass the attached requirement (an all-detached "cook" records
     * nothing worth keeping). */
    bool explicit_start;
    bool explicit_stop;
    bool unpaired; /* the bridge was just unpaired */
} cook_lc_input_t;

void cook_lifecycle_reset(cook_lifecycle_t *lc);
void cook_lifecycle_note_started(cook_lifecycle_t *lc, uint32_t now_s);
void cook_lifecycle_note_ended(cook_lifecycle_t *lc);

/* Packet loss is deliberately NOT an end condition: with no samples the
 * detached streak does not advance, so a 40-minute dropout leaves the
 * session open with a visible gap (04 §4.6). */
cook_lc_action_t cook_lifecycle_step(cook_lifecycle_t *lc,
                                     const cook_lc_input_t *in);

#ifdef __cplusplus
}
#endif

#endif /* COOK_LIFECYCLE_H */
