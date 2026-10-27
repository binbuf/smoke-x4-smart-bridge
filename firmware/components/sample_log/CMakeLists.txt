# sample_log - pure ring core + IDF flash adapter (T17/T18/T19).
# The host seam include/log_io.h is committed by T03 and must stay pure C.
idf_component_register(
    SRCS "sample_log.c" "log_core.c"
    INCLUDE_DIRS "include"
    REQUIRES esp_common protocol_gen
    PRIV_REQUIRES log
)
