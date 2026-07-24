/* Follow-on to F12: the persisted battery power log. A FIFO ring that keeps
 * the NEWEST lines (the opposite of the novelty log's pin-first-instance),
 * records the reset reason in a boot marker, and round-trips its line format.
 * The wrap behaviour is the load-bearing one: after a multi-day run the
 * recent decline and the death point must survive; the earliest lines may
 * not. */
#include <stdio.h>
#include <string.h>

#include "cook_power_log.h"
#include "cook_store_core.h"
#include "test_cook_doubles.h"
#include "test_util.h"

#define LOG_PATH COOK_STORE_DIR "/power.log"

static int file_contains(const char *needle) {
    mem_file_t *f = memfs_find(LOG_PATH);
    if (!f) {
        return 0;
    }
    static char buf[80 * 1024];
    const size_t n = f->len < sizeof buf - 1 ? f->len : sizeof buf - 1;
    memcpy(buf, f->data, n);
    buf[n] = '\0';
    return strstr(buf, needle) != NULL;
}

/* Byte offset of a needle in the file, or -1. Lets a test assert one line
 * comes BEFORE another — the whole point of the boot marker. */
static long file_offset(const char *needle) {
    mem_file_t *f = memfs_find(LOG_PATH);
    if (!f) {
        return -1;
    }
    static char buf[80 * 1024];
    const size_t n = f->len < sizeof buf - 1 ? f->len : sizeof buf - 1;
    memcpy(buf, f->data, n);
    buf[n] = '\0';
    const char *p = strstr(buf, needle);
    return p ? (long)(p - buf) : -1;
}

static uint32_t count_newlines(void) {
    mem_file_t *f = memfs_find(LOG_PATH);
    if (!f) {
        return 0;
    }
    uint32_t lines = 0;
    for (size_t i = 0; i < f->len; i++) {
        if (f->data[i] == '\n') {
            lines++;
        }
    }
    return lines;
}

/* Deterministic, collision-free identifiers for a synthetic run: 6-digit
 * uptimes so no line-start prefix is a substring of another. */
static uint32_t up(int i) { return 100000u + (uint32_t)i * 10u; }
static unsigned mv(int i) { return 3000u + (unsigned)(i % 900); }
static unsigned soc(int i) { return (unsigned)(i % 101); }
static unsigned chg(int i) { return (unsigned)(i & 1); }
static void line_of(char *buf, size_t n, int i) {
    snprintf(buf, n, "%lu %u %u %u\n", (unsigned long)up(i), mv(i), soc(i),
             chg(i));
}

/* The format survives a write→read round trip exactly, and the boot marker
 * is greppable and distinct from a reading. */
static void test_format_round_trips(void) {
    memfs_reset();
    CHECK_EQ_INT(cook_power_log_init(&g_vfs, 0, "poweron"), COOK_STORE_OK);
    CHECK(file_contains("0 BOOT poweron"));

    CHECK_EQ_INT(cook_power_log_append(66120, 3612, 8, false), COOK_STORE_OK);
    CHECK_EQ_INT(cook_power_log_append(66180, 3590, 7, true), COOK_STORE_OK);
    CHECK(file_contains("66120 3612 8 0"));
    CHECK(file_contains("66180 3590 7 1"));
    /* Two readings + one marker. */
    CHECK_EQ_INT((int)count_newlines(), 3);
}

/* The forensic scenario the log exists for: a run of readings, then a power
 * cycle whose reason is captured by a fresh _init on the SAME file. The last
 * reading before death and the BOOT marker both survive, in that order. */
static void test_boot_marker_closes_the_brownout_question(void) {
    memfs_reset();
    CHECK_EQ_INT(cook_power_log_init(&g_vfs, 0, "poweron"), COOK_STORE_OK);
    CHECK_EQ_INT(cook_power_log_append(65000, 3700, 12, false), COOK_STORE_OK);
    CHECK_EQ_INT(cook_power_log_append(66120, 3600, 8, false), COOK_STORE_OK);

    /* Power cut, USB replugged: the file persists, a new boot appends its
     * marker. memfs is NOT reset — this is a remount, not a fresh device. */
    CHECK_EQ_INT(cook_power_log_init(&g_vfs, 0, "brownout"), COOK_STORE_OK);

    CHECK(file_contains("66120 3600 8 0")); /* 8% at ~18h22m survived */
    CHECK(file_contains("0 BOOT brownout")); /* the cause of death */
    /* "…8% at 18h22m, then BOOT brownout" — the reading precedes the marker. */
    const long reading = file_offset("66120 3600 8 0");
    const long marker = file_offset("0 BOOT brownout");
    CHECK(reading >= 0 && marker >= 0 && reading < marker);
    /* Nothing was lost across the remount: the poweron marker is still there
     * too (the file is a continuous history). */
    CHECK(file_contains("0 BOOT poweron"));
}

/* The ring wraps FIFO: past the caps it evicts the OLDEST lines and keeps the
 * newest, staying under both the line and byte budgets. */
static void test_fifo_wrap_keeps_newest(void) {
    memfs_reset();
    CHECK_EQ_INT(cook_power_log_init(&g_vfs, 0, "poweron"), COOK_STORE_OK);

    const int total = (int)COOK_POWER_MAX_LINES + 100; /* forces one compact */
    for (int i = 1; i <= total; i++) {
        CHECK_EQ_INT(
            cook_power_log_append(up(i), (uint16_t)mv(i), (uint8_t)soc(i),
                                  chg(i) != 0),
            COOK_STORE_OK);
    }

    mem_file_t *f = memfs_find(LOG_PATH);
    CHECK(f != NULL);
    /* Under both budgets. */
    CHECK(f->len < COOK_POWER_MAX_BYTES);
    const uint32_t lines = count_newlines();
    CHECK(lines <= COOK_POWER_MAX_LINES);
    CHECK(lines >= COOK_POWER_KEEP_LINES);

    char needle[64];
    /* The newest readings survived. */
    line_of(needle, sizeof needle, total);
    CHECK(file_contains(needle));
    line_of(needle, sizeof needle, (int)COOK_POWER_MAX_LINES);
    CHECK(file_contains(needle));
    /* The oldest readings — and the boot marker ahead of them — were evicted:
     * losing the earliest lines is exactly what FIFO is for. */
    line_of(needle, sizeof needle, 1);
    CHECK(!file_contains(needle));
    line_of(needle, sizeof needle, 100);
    CHECK(!file_contains(needle));
    CHECK(!file_contains("BOOT")); /* the sole marker was the oldest line */

    /* Appends keep working after a wrap, and land at the tail. */
    CHECK_EQ_INT(cook_power_log_append(999999, 3111, 3, false),
                 COOK_STORE_OK);
    CHECK(file_contains("999999 3111 3 0"));
}

int main(void) {
    test_format_round_trips();
    test_boot_marker_closes_the_brownout_question();
    test_fifo_wrap_keeps_newest();
    return test_summary("test_power_log");
}
