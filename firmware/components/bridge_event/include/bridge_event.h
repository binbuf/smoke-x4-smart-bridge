/* bridge_event.h — the BRIDGE_EVENT esp_event base (design 03 §3.2).
 * IDF-facing API; the pure types live in bridge_event_types.h so host tests
 * never pull in ESP-IDF headers.
 */
#ifndef BRIDGE_EVENT_H
#define BRIDGE_EVENT_H

#include "esp_event.h"

#include "bridge_event_types.h"

#ifdef __cplusplus
extern "C" {
#endif

ESP_EVENT_DECLARE_BASE(BRIDGE_EVENT);

/* Registers a handler on the default loop, wrapped so its duration is
 * measured against BRIDGE_EVENT_GUARD_BUDGET_US. In debug builds a handler
 * over budget trips an assertion; in release it logs. `name` labels the
 * handler in diagnostics. */
esp_err_t bridge_event_handler_register(bridge_event_id_t id,
                                        esp_event_handler_t handler,
                                        void *handler_arg, const char *name);

/* Posts payload (copied by esp_event; POD only, no pointers into caller
 * stacks) to the default loop. */
esp_err_t bridge_event_post(bridge_event_id_t id, const void *payload,
                            size_t payload_size);

#ifdef __cplusplus
}
#endif

#endif /* BRIDGE_EVENT_H */
