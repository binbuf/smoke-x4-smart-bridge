# Root developer entry points. The protocol contract is generated, committed,
# and checked for drift; the host test compiles the generated C codec and runs
# the equivalent Dart codec test.

PYTHON ?= python
CC ?= gcc
DART ?= dart

ifeq ($(OS),Windows_NT)
EXE := .exe
else
EXE :=
endif

PROTO_TEST_BIN := build/protocol_test$(EXE)

.PHONY: protocol protocol-check protocol-test

protocol:
	$(PYTHON) tools/protogen/protogen.py

protocol-check:
	$(PYTHON) tools/protogen/protogen.py --check

protocol-test: protocol
	$(PYTHON) -c "import os; os.makedirs('build', exist_ok=True)"
	$(CC) -std=c11 -Wall -Wextra -Werror -Iprotocol/gen protocol/test/test_records.c protocol/gen/records.c -o $(PROTO_TEST_BIN)
	$(PROTO_TEST_BIN)
	$(DART) protocol/test/records_test.dart
