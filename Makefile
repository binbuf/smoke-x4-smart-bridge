# Root developer entry points. The protocol contract is generated, committed,
# and checked for drift; the host test compiles the generated C codec and runs
# the equivalent Dart codec test.

PYTHON ?= python
CC ?= gcc
DART ?= dart
APP_DIR ?= app

ifeq ($(OS),Windows_NT)
EXE := .exe
FLUTTER ?= flutter.bat
else
EXE :=
FLUTTER ?= flutter
endif

PROTO_TEST_BIN := build/protocol_test$(EXE)
HOST_TEST_BUILD ?= firmware/test/build

.PHONY: protocol protocol-check protocol-test host-test bench-test app-analyze app-test app-check design-export design-capture design-diff design-approve thumbs capture

protocol:
	$(PYTHON) tools/protogen/protogen.py

protocol-check:
	$(PYTHON) tools/protogen/protogen.py --check

protocol-test: protocol
	$(PYTHON) -c "import os; os.makedirs('build', exist_ok=True)"
	$(CC) -std=c11 -Wall -Wextra -Werror -Iprotocol/gen protocol/test/test_records.c protocol/gen/records.c -o $(PROTO_TEST_BIN)
	$(PROTO_TEST_BIN)
	$(DART) protocol/test/records_test.dart

# Plain host suite: gcc/clang + CMake + Ninja + CTest. No ESP-IDF, no board.
host-test:
	cmake -S firmware/test -B $(HOST_TEST_BUILD) -G Ninja
	cmake --build $(HOST_TEST_BUILD)
	ctest --test-dir $(HOST_TEST_BUILD) --output-on-failure

# Bench tooling (no board, no third-party dependencies).
bench-test:
	$(PYTHON) -m unittest discover -s tools/bench -p "test_*.py" -v

# Flutter app checks. Run from the repository root; CI (T08) uses app-check.
app-analyze:
	cd $(APP_DIR) && $(FLUTTER) analyze

app-test:
	cd $(APP_DIR) && $(FLUTTER) test

app-check: app-analyze app-test

# Laboratory contact sheet. Downscales the approved screenshots into
# app/assets/thumbs, which the Experimental lab shows as a grid.
thumbs:
	$(PYTHON3) tools/make_thumbs.py

# Fresh 3x captures of every approved screen, for review without touching the
# baseline. Written by the golden test, so it needs no export step.
CAPTURE_DIR := $(CURDIR)/build/captures

capture:
	$(RM) -r $(CAPTURE_DIR)
	cd $(APP_DIR) && UI_CAPTURE_DIR=$(CAPTURE_DIR) $(FLUTTER) test tool/ui_screenshots_test.dart

# Review a visual change before accepting it: approved screenshots against the
# captures from `make capture`.
design-diff:
	$(PYTHON3) tools/scenario_diff.py $(DIFF_ARGS)

# FigCraft hand-off. The screenshots stay the UI contract; the export turns the
# real render tree into editable FigCraft text over a cleaned reference image.
# Generated files live under design/figcraft/render (git-ignored).
FIGCRAFT_DUMP_DIR := $(CURDIR)/design/figcraft/render/dump
PYTHON3 ?= python3

design-export:
	cd $(APP_DIR) && FIGCRAFT_DUMP=$(FIGCRAFT_DUMP_DIR) $(FLUTTER) test tool/ui_screenshots_test.dart
	$(PYTHON3) tools/figcraft_export.py

# Save in FigCraft first, then this lists the copy that changed.
design-capture:
	$(PYTHON3) tools/figcraft_capture.py

# Accept an intentional visual change. Run `make design-diff` first and look at
# the changed screens; this then rewrites the baseline, records the new hashes
# and refreshes the lab thumbnails.
design-approve:
	cd $(APP_DIR) && $(FLUTTER) test --update-goldens tool/ui_screenshots_test.dart
	cd $(APP_DIR) && $(DART) run tool/screenshot_manifest.dart
	$(PYTHON3) tools/make_thumbs.py
