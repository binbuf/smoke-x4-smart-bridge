/* bench.h — the V1.3/V1.4 bench diagnostic (see Kconfig.projbuild).
 * A no-op unless CONFIG_SMOKEBRIDGE_BENCH_MODE is set.
 */
#ifndef BENCH_H
#define BENCH_H

#ifdef __cplusplus
extern "C" {
#endif

/* Runs the bench loop forever (never returns when bench mode is on). */
void bench_run(void);

#ifdef __cplusplus
}
#endif

#endif /* BENCH_H */
