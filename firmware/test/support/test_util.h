/* Minimal assertion helpers shared by the host tests. */
#ifndef SX4_TEST_UTIL_H
#define SX4_TEST_UTIL_H

#include <stdio.h>
#include <string.h>

#ifdef __cplusplus
extern "C" {
#endif

extern int sx4_test_failures;

void sx4_test_fail(const char *file, int line, const char *expr);
void sx4_test_fail_int(const char *file, int line, const char *expr,
                       long long got, long long want);
void sx4_test_fail_uint(const char *file, int line, const char *expr,
                        unsigned long long got, unsigned long long want);
void sx4_test_fail_str(const char *file, int line, const char *expr,
                       const char *got, const char *want);

#define CHECK(expr)                                       \
    do {                                                  \
        if (!(expr)) {                                    \
            sx4_test_fail(__FILE__, __LINE__, #expr);     \
        }                                                 \
    } while (0)

#define CHECK_EQ_INT(got, want)                                      \
    do {                                                             \
        long long sx4_got_ = (long long)(got);                       \
        long long sx4_want_ = (long long)(want);                     \
        if (sx4_got_ != sx4_want_) {                                 \
            sx4_test_fail_int(__FILE__, __LINE__, #got, sx4_got_,    \
                              sx4_want_);                            \
        }                                                            \
    } while (0)

#define CHECK_EQ_UINT(got, want)                                       \
    do {                                                               \
        unsigned long long sx4_got_ = (unsigned long long)(got);       \
        unsigned long long sx4_want_ = (unsigned long long)(want);     \
        if (sx4_got_ != sx4_want_) {                                   \
            sx4_test_fail_uint(__FILE__, __LINE__, #got, sx4_got_,     \
                               sx4_want_);                             \
        }                                                              \
    } while (0)

#define CHECK_STR_EQ(got, want)                                      \
    do {                                                             \
        const char *sx4_got_ = (got);                                \
        const char *sx4_want_ = (want);                              \
        if (sx4_got_ == NULL || sx4_want_ == NULL ||                 \
            strcmp(sx4_got_, sx4_want_) != 0) {                      \
            sx4_test_fail_str(__FILE__, __LINE__, #got, sx4_got_,    \
                              sx4_want_);                            \
        }                                                            \
    } while (0)

/* Print a one-line result. Returns 0 when every check passed. */
int sx4_test_summary(const char *suite);

#ifdef __cplusplus
}
#endif

#endif /* SX4_TEST_UTIL_H */
