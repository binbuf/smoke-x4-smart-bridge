/* app_api_internal — shared between the core router and handler files. */
#ifndef APP_API_INTERNAL_H
#define APP_API_INTERNAL_H

#include "app_api_core.h"

#ifdef __cplusplus
extern "C" {
#endif

extern const app_api_ops_t *app_api_ops(void);

/* The one error shape (06 §6.1): {"error":{"code","message","detail"}}. */
void app_api_error(app_api_out_t *out, int status, const char *code,
                   const char *message);
void app_api_error_detail_int(app_api_out_t *out, int status,
                              const char *code, const char *message,
                              const char *detail_key, int detail_value);

const char *app_api_query_get(const app_api_req_t *req, const char *key);
int app_api_query_int(const app_api_req_t *req, const char *key,
                      long fallback, long *out);

/* Naive-but-strict JSON field extraction for the small POST bodies. */
const char *app_api_json_find(const char *body, const char *key);
int app_api_json_str(const char *body, const char *key, char *out,
                     size_t cap);
int app_api_json_int(const char *body, const char *key, long *out);
/* Use this one for epoch milliseconds: `long` is 32-bit on the device and
 * 64-bit on the host, so app_api_json_int silently truncates a real
 * timestamp on the board only. */
int app_api_json_i64(const char *body, const char *key, int64_t *out);
int app_api_json_bool(const char *body, const char *key, bool *out);

/* Handlers that live in app_api_sessions.c. */
void app_api_handle_sessions_list(const app_api_req_t *req,
                                  app_api_out_t *out);
void app_api_handle_sessions_post(const app_api_req_t *req,
                                  app_api_out_t *out);
void app_api_handle_session(const app_api_req_t *req, app_api_out_t *out,
                            uint32_t id, const char *sub);

#ifdef __cplusplus
}
#endif

#endif /* APP_API_INTERNAL_H */
