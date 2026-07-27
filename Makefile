# Smoke X4 Smart Bridge — root Makefile (T1.4, design 03 §3.8)
#
# Adapted from docs/reference/smoke-x-receiver/Makefile: the export.sh sourcing
# and Python-version detection are carried over; the reference's v2/v3 board
# matrix collapses to the single heltec-v3 target, which removes most of its
# complexity.
#
# Prerequisites:
#   - Host tests: gcc, cmake, ninja (no ESP-IDF, no hardware)
#   - Firmware:   ESP-IDF v5.4 (build/flash/menuconfig auto-source export.sh)
#   - Simulator:  Dart SDK (dart on PATH)
#
# Options:
#   PORT=/dev/...                          Serial port for flash/monitor (auto-detect if omitted)
#   IDF_EXPORT=/path/to/esp-idf/export.sh  Override ESP-IDF location
#                                          (also honors IDF_PATH; defaults to ~/esp/esp-idf)
#
# The reference's `dist` targets merge bootloader, partition table, app, and
# storage with esptool merge_bin at fixed offsets 0x0/0x8000/0x10000/0x210000.
# Those offsets do NOT transfer here — our partition table differs (8 MB, dual
# OTA slots, coredump, www, cooks; see docs/design/03 §3.5 and
# firmware/partitions.csv). Settled in T5.1: `make dist` shells out to
# tools/flash, which reads every offset from the build's own flasher_args.json
# rather than transcribing any of them, so a moved partition cannot silently
# produce a mis-merged image.

.DEFAULT_GOAL := help

IDF_PY ?= idf.py
PORT ?=

# ESP-IDF v5.4 supports Python 3.9+ (no upper bound). Prefer Homebrew python@3.x
# shims, then versioned python3.x binaries already on PATH.
IDF_PYTHON_DIR := $(shell \
	python_ok() { "$$1" -c 'import sys; sys.exit(0 if sys.version_info[:2] >= (3,9) else 1)' 2>/dev/null; }; \
	brew_prefix=$$(brew --prefix 2>/dev/null); \
	for ver in 3.14 3.13 3.12 3.11 3.10 3.9; do \
		for prefix in /opt/homebrew /usr/local $$brew_prefix; do \
			test -n "$$prefix" || continue; \
			dir="$$prefix/opt/python@$$ver/libexec/bin"; \
			test -x "$$dir/python3" && python_ok "$$dir/python3" && { echo "$$dir"; exit 0; }; \
			test -x "$$dir/python" && python_ok "$$dir/python" && { echo "$$dir"; exit 0; }; \
		done; \
	done; \
	for cmd in python3.14 python3.13 python3.12 python3.11 python3.10 python3.9 python3 python; do \
		path=$$(command -v $$cmd 2>/dev/null) || continue; \
		python_ok "$$path" && { dirname "$$path"; exit 0; }; \
	done \
)
IDF_PYTHON_PATH := $(if $(IDF_PYTHON_DIR),PATH="$(IDF_PYTHON_DIR):$$PATH",)

ifdef IDF_PATH
IDF_EXPORT ?= $(IDF_PATH)/export.sh
else
IDF_EXPORT ?= $(HOME)/esp/esp-idf/export.sh
endif

# One board (design 11 §11.4 Q-H): Heltec WiFi LoRa 32 V3 (ESP32-S3, SX1262).
FW_DIR := firmware
CHIP := esp32s3
SDKCONFIG_DEFAULTS_V3 := sdkconfig.defaults;sdkconfig.defaults.heltec-v3
SDKCONFIG := sdkconfig.heltec-v3
FW_BUILD := build/heltec-v3

# msys2 make invoked from Git Bash loses the Windows environment (different
# MSYS runtimes don't share it). gcc's linker needs TMP; dart needs
# LOCALAPPDATA for the pub cache. Restore them from $HOME when absent —
# no-ops everywhere else.
ifneq (,$(findstring NT,$(shell uname -s)))
ifeq ($(LOCALAPPDATA),)
# The registry's Volatile Environment key holds the real profile paths even
# when the process environment lost them.
export LOCALAPPDATA := $(shell reg query 'HKCU\Volatile Environment' 2>/dev/null | sed -n 's/^[ \t]*LOCALAPPDATA[ \t]*REG_SZ[ \t]*//p' | tr -d '\r')
endif
ifeq ($(TMP),)
export TMP := $(LOCALAPPDATA)\Temp
endif
ifeq ($(TEMP),)
export TEMP := $(TMP)
endif
endif

TEST_DIR := firmware/test
TEST_BUILD := firmware/test/build

PORT_ARG := $(if $(PORT),-p $(PORT),)

.PHONY: help check-python check-idf setup build flash flash-monitor monitor \
	menuconfig test-host oled-preview sim clean clean-test \
	doctor deploy-bridge deploy-app dist

# help: Show available targets and usage
help:
	@echo "Smoke X4 Smart Bridge"
	@echo ""
	@awk '\
		/^# --- .+ ---$$/ { \
			if (sections++) print ""; \
			gsub(/^# --- | ---$$/, "", $$0); \
			printf "%s:\n", $$0; \
			next \
		} \
		/^# [a-zA-Z0-9_.-]+: / { \
			if ($$0 ~ /^# (help|idf_v3): /) next; \
			target = $$0; \
			sub(/^# /, "", target); \
			sub(/: .*$$/, "", target); \
			desc = $$0; \
			sub(/^# [a-zA-Z0-9_.-]+: /, "", desc); \
			printf "  \033[36m%s\033[0m   %s\n", target, desc; \
			next \
		}' $(MAKEFILE_LIST)
	@echo ""
	@echo "Firmware targets auto-source: $(IDF_EXPORT)"
	@echo "For interactive shells: source \"$(IDF_EXPORT)\""

# --- Prerequisite checks ---

# check-python: Verify ESP-IDF-compatible Python (3.9+) is available
check-python:
	@if [ -n "$(IDF_PYTHON_DIR)" ]; then \
		if [ -x "$(IDF_PYTHON_DIR)/python3" ]; then \
			py="$(IDF_PYTHON_DIR)/python3"; \
		elif [ -x "$(IDF_PYTHON_DIR)/python" ]; then \
			py="$(IDF_PYTHON_DIR)/python"; \
		else \
			py=$$(ls "$(IDF_PYTHON_DIR)"/python3.* 2>/dev/null | head -n 1); \
		fi; \
		echo "ESP-IDF Python: $$($$py --version) ($$py)"; \
	else \
		echo ""; \
		echo "Error: No supported Python found (ESP-IDF v5.4 needs 3.9+)."; \
		echo ""; \
		echo "Install Python 3.9+ via your system package manager, e.g.:"; \
		echo "  macOS:         brew install python@3.12"; \
		echo "  Debian/Ubuntu: sudo apt install python3"; \
		echo "  Fedora/RHEL:   sudo dnf install python3"; \
		echo ""; \
		current=$$(command -v python3 2>/dev/null); \
		if [ -n "$$current" ]; then \
			echo "Current python3: $$($$current --version) ($$current)"; \
		else \
			echo "Current python3: not found"; \
		fi; \
		exit 1; \
	fi

# check-idf: Verify ESP-IDF export.sh is reachable
check-idf: check-python
	@test -f "$(IDF_EXPORT)" || { \
		echo ""; \
		echo "Error: ESP-IDF export script not found at:"; \
		echo "  $(IDF_EXPORT)"; \
		echo ""; \
		echo "Firmware targets (build/flash/menuconfig) need ESP-IDF v5.4."; \
		echo "Host tests and the simulator do not: try 'make test-host' or 'make sim'."; \
		echo ""; \
		echo "Install ESP-IDF v5.4, then retry or point at it explicitly:"; \
		echo "  https://docs.espressif.com/projects/esp-idf/en/release-v5.4/esp32s3/get-started/"; \
		echo "  make build IDF_EXPORT=/path/to/esp-idf/export.sh"; \
		echo ""; \
		exit 1; \
	}
	@echo "ESP-IDF: $(IDF_EXPORT)"

# idf_v3: source export.sh once, cd into firmware/, run set-target if the build
# dir has never been configured (no CMakeCache.txt), then run the requested
# idf.py command. Single shell so export.sh is sourced once.
# $(1) = idf.py args (build / flash / menuconfig / ...)
define idf_v3
	$(IDF_PYTHON_PATH) . "$(IDF_EXPORT)" && cd $(FW_DIR) && { \
		if [ ! -f $(FW_BUILD)/CMakeCache.txt ]; then \
			rm -rf $(FW_BUILD) && \
			SDKCONFIG_DEFAULTS="$(SDKCONFIG_DEFAULTS_V3)" $(IDF_PY) -B $(FW_BUILD) -DSDKCONFIG=$(SDKCONFIG) set-target $(CHIP); \
		fi && \
		SDKCONFIG_DEFAULTS="$(SDKCONFIG_DEFAULTS_V3)" $(IDF_PY) -B $(FW_BUILD) -DSDKCONFIG=$(SDKCONFIG) $(1); \
	}
endef

# --- Project setup ---

# setup: Fetch submodules (if any) and resolve the Dart pub workspace
setup:
	git submodule update --init --recursive
	dart pub get

# --- Deploy (no toolchain required) ---
#
# The targets above BUILD, which is why they need ESP-IDF. These three only
# WRITE an already-built image, so a user who just wants the bridge running
# never installs a compiler. Same bytes, same board — see scripts/deploy.sh.

# doctor: Report which deploy prerequisites are present and what each is for
#
# `|| true` because the script exits non-zero when something is missing — which
# is right for CI and wrong here, where a missing ESP-IDF is the expected state
# for anyone who only wants to flash. A report is not a failure.
doctor:
	@./scripts/deploy.sh doctor || true

# deploy-bridge: Flash a prebuilt merged image over USB (needs only esptool)
deploy-bridge:
	./scripts/deploy.sh bridge $(DEPLOY_ARGS)

# deploy-app: Build and install the Android app on a connected phone
deploy-app:
	./scripts/deploy.sh app $(DEPLOY_ARGS)

# dist: Pack the merged image, the OTA image, and the installer manifest
dist: build
	dart run flash --build $(FW_DIR)/$(FW_BUILD) \
		--version $$(sed -n 's/^CONFIG_APP_PROJECT_VER="\(.*\)"$$/\1/p' \
			$(FW_DIR)/sdkconfig.defaults) \
		--out dist

# --- Firmware (Heltec WiFi LoRa 32 V3) ---

# build: Build the firmware image
build: check-idf
	$(call idf_v3,build)

# flash: Build and flash (set PORT=... to pick the serial port)
flash: check-idf
	$(call idf_v3,build flash $(PORT_ARG))

# flash-monitor: Build, flash, and open the serial monitor
flash-monitor: check-idf
	$(call idf_v3,build flash monitor $(PORT_ARG))

# monitor: Open the serial monitor without rebuilding
monitor: check-idf
	$(call idf_v3,monitor $(PORT_ARG))

# menuconfig: Open menuconfig for the heltec-v3 build
menuconfig: check-idf
	$(call idf_v3,menuconfig)

# The V1.3/V1.4 bench diagnostic: own build dir + sdkconfig so it never
# clobbers the normal firmware configuration.
BENCH_BUILD := build/heltec-v3-bench
SDKCONFIG_DEFAULTS_BENCH := $(SDKCONFIG_DEFAULTS_V3);sdkconfig.bench
SDKCONFIG_BENCH := sdkconfig.heltec-v3-bench

define idf_bench
	$(IDF_PYTHON_PATH) . "$(IDF_EXPORT)" && cd $(FW_DIR) && { \
		if [ ! -f $(BENCH_BUILD)/CMakeCache.txt ]; then \
			rm -rf $(BENCH_BUILD) && \
			SDKCONFIG_DEFAULTS="$(SDKCONFIG_DEFAULTS_BENCH)" $(IDF_PY) -B $(BENCH_BUILD) -DSDKCONFIG=$(SDKCONFIG_BENCH) set-target $(CHIP); \
		fi && \
		SDKCONFIG_DEFAULTS="$(SDKCONFIG_DEFAULTS_BENCH)" $(IDF_PY) -B $(BENCH_BUILD) -DSDKCONFIG=$(SDKCONFIG_BENCH) $(1); \
	}
endef

# bench: Build the V1.3/V1.4 bench diagnostic firmware
bench: check-idf
	$(call idf_bench,build)

# bench-flash: Build, flash, and monitor the bench diagnostic (PORT=... to pick)
bench-flash: check-idf
	$(call idf_bench,build flash monitor $(PORT_ARG))

# --- Tests ---

# test-host: Build and run host unit tests (plain gcc + cmake, no ESP-IDF, no hardware)
test-host:
	cmake -G Ninja -B $(TEST_BUILD) $(TEST_DIR)
	cmake --build $(TEST_BUILD)
	ctest --test-dir $(TEST_BUILD) --output-on-failure

# oled-preview: Render the golden OLED framebuffers to PNGs for review (F11a.2)
oled-preview:
	python tools/oled/render_oled_preview.py

# --- Simulator ---

# sim: Run the fake bridge (tools/sim) serving an 18-hour cook on port 8080
sim:
	dart run sim --port 8080 --cook fixtures/brisket-18h.smk

# --- Clean ---

# clean-test: Remove the host test build directory
clean-test:
	rm -rf $(TEST_BUILD)

# clean: Remove firmware and test build artifacts
clean: clean-test
	rm -rf $(FW_DIR)/$(FW_BUILD)
