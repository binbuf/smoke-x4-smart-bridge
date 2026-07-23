/* F4.3: the persisted novelty ring — wraps without evicting a pinned
 * first-instance, and survives a remount. */
#include <stdio.h>
#include <string.h>

#include "cook_novelty_log.h"
#include "cook_store_core.h"
#include "test_cook_doubles.h"
#include "test_util.h"

#define LOG_PATH COOK_STORE_DIR "/novelty.log"

static int file_contains(const char *needle) {
    mem_file_t *f = memfs_find(LOG_PATH);
    if (!f) {
        return 0;
    }
    /* NUL-terminate a copy for strstr. */
    static char buf[80 * 1024];
    const size_t n = f->len < sizeof buf - 1 ? f->len : sizeof buf - 1;
    memcpy(buf, f->data, n);
    buf[n] = '\0';
    return strstr(buf, needle) != NULL;
}

static void test_pinned_survive_wrap_and_remount(void) {
    memfs_reset();
    CHECK_EQ_INT(cook_novelty_log_init(&g_vfs), COOK_STORE_OK);

    /* Ten distinct reason+value pairs — the evidence that matters. */
    char reason[16], value[16], needle[64];
    for (int i = 0; i < 10; i++) {
        snprintf(reason, sizeof reason, "reason%d", i);
        snprintf(value, sizeof value, "val%d", i);
        CHECK_EQ_INT(cook_novelty_log_append(1000u + (unsigned)i, reason,
                                             value, "first-instance"),
                     COOK_STORE_OK);
    }

    /* 600 lines of churn on one repeating key: crosses the line budget
     * and forces at least one compaction. */
    for (int i = 0; i < 600; i++) {
        CHECK_EQ_INT(cook_novelty_log_append(10000u + (unsigned)i, "sync",
                                             "000000@918500000",
                                             "repeat-beacon"),
                     COOK_STORE_OK);
    }

    mem_file_t *f = memfs_find(LOG_PATH);
    CHECK(f != NULL);
    CHECK(f->len < COOK_NOVELTY_MAX_BYTES);

    /* Every pinned first-instance survived the churn... */
    for (int i = 0; i < 10; i++) {
        snprintf(needle, sizeof needle, "%u reason%d val%d", 1000u + i, i, i);
        CHECK(file_contains(needle));
    }
    /* ...and the repeated key kept its FIRST instance (t=10000). */
    CHECK(file_contains("10000 sync 000000@918500000"));

    /* Remount: a fresh init sees the same file and keeps appending. */
    CHECK_EQ_INT(cook_novelty_log_init(&g_vfs), COOK_STORE_OK);
    CHECK_EQ_INT(cook_novelty_log_append(99999, "field1", "31", "new-boot"),
                 COOK_STORE_OK);
    CHECK(file_contains("99999 field1 31"));
    for (int i = 0; i < 10; i++) {
        snprintf(needle, sizeof needle, "%u reason%d val%d", 1000u + i, i, i);
        CHECK(file_contains(needle));
    }
}

int main(void) {
    test_pinned_survive_wrap_and_remount();
    return test_summary("test_novelty_log");
}
