/*
 * main.c - entry point only. All wiring lives in boot.c (design 03 section 3.4).
 */
#include "boot.h"

void app_main(void) { sx4_boot_run(); }
