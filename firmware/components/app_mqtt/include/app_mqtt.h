/* app_mqtt — device glue for the MQTT / Home Assistant publisher (05 §5.7).
 *
 * Wi-Fi-only and opt-in. A bridge with no broker configured — or one on AP /
 * fallback with no uplink — still cooks and still serves HTTP and BLE; this
 * module simply does nothing until it is enabled and the STA link is up.
 *
 * It adds NO application task: esp-mqtt owns its `mqtt_task` (framework-created,
 * outside main/tasks.h's 32 KB budget). The bus handlers build small JSON and
 * `esp_mqtt_client_enqueue()` it — non-blocking, well under the 5 ms handler
 * guard — and that task does the socket send.
 */
#ifndef APP_MQTT_H
#define APP_MQTT_H

#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

/* Boot step (BRIDGE_BOOT_MQTT): read config, subscribe to the bus, and — when
 * enabled and STA is up — start the client. Non-fatal. */
int app_mqtt_init(void);

/* True while a live broker connection is held (GET /config/mqtt "connected"). */
bool app_mqtt_is_connected(void);

/* Re-read config and start / stop / restart the client to match — called after
 * POST /config/mqtt so enabling it takes effect without a reboot. */
void app_mqtt_reconfigure(void);

#ifdef __cplusplus
}
#endif

#endif /* APP_MQTT_H */
