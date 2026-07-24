/* ota_gate.c — F14.3: design 03 §3.7's health gate as a pure verdict. */
#include "app_ota_gate.h"

#include <stdio.h>
#include <string.h>

app_ota_gate_verdict_t app_ota_gate_eval(const app_ota_gate_facts_t *facts,
                                         uint32_t *failed_mask) {
    uint32_t mask = 0;
    if (failed_mask) {
        *failed_mask = 0;
    }
    if (!facts) {
        return APP_OTA_GATE_NOT_APPLICABLE;
    }

    /* A USB-flashed image is not awaiting confirmation. Marking it valid
     * or rolling it back would both be bugs, and the clauses below are
     * irrelevant however badly they fail. */
    if (!facts->pending_verify) {
        return APP_OTA_GATE_NOT_APPLICABLE;
    }

    /* The image's own fault, and already known — waiting out the
     * remaining seconds serves nothing. */
    if (facts->reset_was_crash) {
        mask |= APP_OTA_GATE_CLAUSE_CRASH;
    }

    if (!facts->storage_mounted) {
        mask |= APP_OTA_GATE_CLAUSE_STORAGE;
    }
    if (!facts->net_settled) {
        mask |= APP_OTA_GATE_CLAUSE_NET;
    }
    if (!facts->httpd_listening) {
        mask |= APP_OTA_GATE_CLAUSE_HTTPD;
    }

    if (mask & APP_OTA_GATE_CLAUSE_CRASH) {
        if (failed_mask) {
            *failed_mask = mask;
        }
        return APP_OTA_GATE_FAIL;
    }

    /* The other three clauses are still settling before 120 s: a slow
     * DHCP lease is not a failure, it is a wait. */
    if (facts->uptime_s < APP_OTA_GATE_UPTIME_S) {
        return APP_OTA_GATE_WAITING;
    }

    if (mask != 0) {
        if (failed_mask) {
            *failed_mask = mask;
        }
        return APP_OTA_GATE_FAIL;
    }
    return APP_OTA_GATE_PASS;
}

const char *app_ota_gate_verdict_str(app_ota_gate_verdict_t v) {
    switch (v) {
    case APP_OTA_GATE_NOT_APPLICABLE:
        return "not_applicable";
    case APP_OTA_GATE_WAITING:
        return "waiting";
    case APP_OTA_GATE_PASS:
        return "passed";
    case APP_OTA_GATE_FAIL:
        return "failed";
    }
    return "unknown";
}

size_t app_ota_gate_clauses_str(uint32_t mask, char *out, size_t cap) {
    static const struct {
        uint32_t bit;
        const char *name;
    } k_names[] = {
        {APP_OTA_GATE_CLAUSE_STORAGE, "storage"},
        {APP_OTA_GATE_CLAUSE_NET, "net"},
        {APP_OTA_GATE_CLAUSE_HTTPD, "httpd"},
        {APP_OTA_GATE_CLAUSE_CRASH, "crash"},
    };
    if (!out || cap == 0) {
        return 0;
    }
    out[0] = '\0';
    size_t n = 0;
    for (size_t i = 0; i < sizeof k_names / sizeof k_names[0]; i++) {
        if ((mask & k_names[i].bit) == 0) {
            continue;
        }
        const char *sep = (n > 0) ? "," : "";
        const size_t want = strlen(sep) + strlen(k_names[i].name);
        if (n + want + 1 > cap) {
            break;
        }
        memcpy(out + n, sep, strlen(sep));
        n += strlen(sep);
        memcpy(out + n, k_names[i].name, strlen(k_names[i].name));
        n += strlen(k_names[i].name);
        out[n] = '\0';
    }
    return n;
}
