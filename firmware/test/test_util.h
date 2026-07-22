/* test_util.h — minimal assertion helpers for the host test suite. */
#ifndef TEST_UTIL_H
#define TEST_UTIL_H

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static int g_checks = 0;
static int g_failures = 0;

#define CHECK(cond)                                                       \
    do {                                                                  \
        g_checks++;                                                       \
        if (!(cond)) {                                                    \
            g_failures++;                                                 \
            fprintf(stderr, "FAIL %s:%d: %s\n", __FILE__, __LINE__,       \
                    #cond);                                               \
        }                                                                 \
    } while (0)

#define CHECK_EQ_INT(a, b)                                                \
    do {                                                                  \
        g_checks++;                                                       \
        long long va_ = (long long)(a);                                   \
        long long vb_ = (long long)(b);                                   \
        if (va_ != vb_) {                                                 \
            g_failures++;                                                 \
            fprintf(stderr, "FAIL %s:%d: %s == %s (%lld != %lld)\n",      \
                    __FILE__, __LINE__, #a, #b, va_, vb_);                \
        }                                                                 \
    } while (0)

static inline int test_summary(const char *name)
{
    if (g_failures != 0) {
        fprintf(stderr, "%s: %d/%d checks FAILED\n", name, g_failures,
                g_checks);
        return 1;
    }
    printf("%s: %d checks passed\n", name, g_checks);
    return 0;
}

#endif /* TEST_UTIL_H */
