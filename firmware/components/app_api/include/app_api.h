/* app_api.h — declared in the design 03 §3.1 component map; implemented in M1+.
 * The M0 skeleton keeps the component compiled and linked so the build
 * shape is real from the first commit. */
#ifndef APP_API_H
#define APP_API_H

#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

/* Returns 0 on success. Stub until the component's milestone lands. */
int app_api_init(void);

/* F14.8 — one clause of the 03 §3.7 health gate: is the server actually
 * accepting connections? A bridge that booted with no httpd is a bridge
 * nobody can reach in order to fix it. */
bool app_api_is_listening(void);

#ifdef __cplusplus
}
#endif

#endif /* APP_API_H */
