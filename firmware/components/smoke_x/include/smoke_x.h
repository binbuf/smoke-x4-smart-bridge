/* smoke_x — device glue: wires the host-tested controller (smoke_x_ctrl),
 * novelty layer, and packet ring onto the radio and the event bus. */
#ifndef SMOKE_X_H
#define SMOKE_X_H

#include "smoke_x_ctrl.h"
#include "smoke_x_novelty.h"
#include "smoke_x_parser.h"
#include "smoke_x_pktring.h"

#ifdef __cplusplus
extern "C" {
#endif

/* Boot step 9: radio init + controller init (loads any persisted
 * pairing). Returns 0 on success. */
int smoke_x_init(void);

/* Boot step 10: starts the RX task and the 1 Hz watchdog tick. */
int smoke_x_start(void);

#ifdef __cplusplus
}
#endif

#endif /* SMOKE_X_H */
