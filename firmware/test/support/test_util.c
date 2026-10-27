#include "test_util.h"

int sx4_test_failures = 0;

void sx4_test_fail(const char *file, int line, const char *expr) {
    sx4_test_failures++;
    fprintf(stderr, "%s:%d: check failed: %s\n", file, line, expr);
}

void sx4_test_fail_int(const char *file, int line, const char *expr,
                       long long got, long long want) {
    sx4_test_failures++;
    fprintf(stderr, "%s:%d: check failed: %s (got %lld, want %lld)\n", file,
            line, expr, got, want);
}

void sx4_test_fail_uint(const char *file, int line, const char *expr,
                        unsigned long long got, unsigned long long want) {
    sx4_test_failures++;
    fprintf(stderr, "%s:%d: check failed: %s (got %llu, want %llu)\n", file,
            line, expr, got, want);
}

void sx4_test_fail_str(const char *file, int line, const char *expr,
                       const char *got, const char *want) {
    sx4_test_failures++;
    fprintf(stderr, "%s:%d: check failed: %s (got \"%s\", want \"%s\")\n",
            file, line, expr, got == NULL ? "(null)" : got,
            want == NULL ? "(null)" : want);
}

int sx4_test_summary(const char *suite) {
    if (sx4_test_failures == 0) {
        printf("%s: ok\n", suite);
        return 0;
    }
    fprintf(stderr, "%s: %d check(s) failed\n", suite, sx4_test_failures);
    return 1;
}
