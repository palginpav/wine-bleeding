SHELL := /usr/bin/env bash

PREFIX ?= $(HOME)/.local

RUNTIME_DIR := $(dir $(abspath $(lastword $(MAKEFILE_LIST))))
SRC_DIR     := $(RUNTIME_DIR)src
TESTS_DIR   := $(RUNTIME_DIR)tests
VENDOR_BATS := $(TESTS_DIR)/vendor/bats-core/bin/bats

SCHEMA_FILE  := $(RUNTIME_DIR)share/schemas/wb_dist_meta.schema.json
FIXTURE_DIST := $(TESTS_DIR)/fixtures/fake-dist

SHELLCHECK_TARGETS := \
  $(SRC_DIR)/wb \
  $(SRC_DIR)/wb-diag \
  $(SRC_DIR)/wb-lib/wb-log.sh \
  $(SRC_DIR)/wb-lib/wb-die.sh \
  $(SRC_DIR)/wb-lib/wb-paths.sh \
  $(SRC_DIR)/wb-lib/wb-config.sh \
  $(SRC_DIR)/wb-lib/wb-json.sh \
  $(SRC_DIR)/wb-lib/wb-lock.sh \
  $(SRC_DIR)/wb-lib/wb-dist.sh \
  $(RUNTIME_DIR)install.sh

.PHONY: test lint install schema-check

test:
	@if [[ -x "$(VENDOR_BATS)" ]]; then \
	  echo "Using vendored bats-core at $(VENDOR_BATS)"; \
	  "$(VENDOR_BATS)" "$(TESTS_DIR)"; \
	elif command -v bats >/dev/null 2>&1; then \
	  echo "Using system bats on PATH"; \
	  bats "$(TESTS_DIR)"; \
	else \
	  echo "SKIP: bats-core not found. Run: git submodule update --init -- runtime/tests/vendor/bats-core"; \
	  exit 0; \
	fi

lint:
	@if ! command -v shellcheck >/dev/null 2>&1; then \
	  echo "SKIP: shellcheck not found on PATH"; \
	  exit 0; \
	else \
	  shellcheck -x --source-path=$(SRC_DIR) $(SHELLCHECK_TARGETS); \
	fi

schema-check:
	@if ! command -v check-jsonschema >/dev/null 2>&1; then \
	  echo "SKIP: check-jsonschema not found (pip install check-jsonschema)"; \
	  exit 0; \
	else \
	  echo "Generating manifest from fixture dist for schema validation..."; \
	  tmp_home=$$(mktemp -d); \
	  mkdir -p "$${tmp_home}/dist"; \
	  cp -a "$(FIXTURE_DIST)" "$${tmp_home}/dist/WINE-BLEEDING-fixture"; \
	  WB_HOME="$${tmp_home}" bash -c " \
	    source $(SRC_DIR)/wb-lib/wb-log.sh 2>/dev/null; \
	    source $(SRC_DIR)/wb-lib/wb-json.sh; \
	    source $(SRC_DIR)/wb-lib/wb-dist.sh; \
	    wb_dist_meta_write '$${tmp_home}/dist/WINE-BLEEDING-fixture' \
	  "; \
	  check-jsonschema --schemafile "$(SCHEMA_FILE)" \
	    "$${tmp_home}/dist/WINE-BLEEDING-fixture/.wb_dist_meta"; \
	  rc=$$?; rm -rf "$${tmp_home}"; exit $$rc; \
	fi

install:
	@echo "install.sh: not yet implemented (lands M7) [PREFIX=$(PREFIX)]"; exit 1
