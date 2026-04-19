#!/usr/bin/env bash
set -euo pipefail

# TODO M1: integrate with wb_log_error before exiting

wb_die() {
  echo "wb: error: $*" >&2
  exit 1
}
