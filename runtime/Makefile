SHELL := /usr/bin/env bash

PREFIX ?= $(HOME)/.local

RUNTIME_DIR := $(dir $(abspath $(lastword $(MAKEFILE_LIST))))
SRC_DIR     := $(RUNTIME_DIR)src
TESTS_DIR   := $(RUNTIME_DIR)tests
VENDOR_BATS := $(TESTS_DIR)/vendor/bats-core/bin/bats

SHELLCHECK_TARGETS := \
  $(SRC_DIR)/wb \
  $(SRC_DIR)/wb-diag \
  $(SRC_DIR)/wb-lib/wb-log.sh \
  $(SRC_DIR)/wb-lib/wb-die.sh \
  $(RUNTIME_DIR)install.sh

.PHONY: test lint install

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
	  shellcheck $(SHELLCHECK_TARGETS); \
	fi

install:
	@echo "install.sh: not yet implemented (lands M7) [PREFIX=$(PREFIX)]"; exit 1
