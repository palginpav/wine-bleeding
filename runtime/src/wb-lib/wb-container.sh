#!/usr/bin/env bash
set -euo pipefail

# wb-container.sh — M11 pressure-vessel / SLR container opt-in support.
# Public API:
#   wb_container_enabled
#   wb_container_detect
#   wb_container_compose_argv <entry_point> <prefix_path> <dist_path> <wine_cmd> [args...]
#
# Argv wire format: one element per line on stdout. Callers reconstruct via
# `while IFS= read -r; argv+=("$REPLY")`. Inputs containing embedded newlines
# would split across argv slots — Windows paths and wine arguments do not
# contain newlines in practice, but validate upstream if you extend the API.

# ---------------------------------------------------------------------------
# wb_container_enabled
# Returns 0 if WB_CONTAINER=1, else 1.
# ---------------------------------------------------------------------------
wb_container_enabled() {
  [[ "${WB_CONTAINER:-0}" == "1" ]]
}

# ---------------------------------------------------------------------------
# wb_container_detect
# Locate the pressure-vessel / SLR entry-point. Checks in order:
#   1. $WB_CONTAINER_ENTRY env override
#   2. $HOME/.steam/steam/steamapps/common/SteamLinuxRuntime_sniper/_v2-entry-point
#   3. $HOME/.steam/root/steamapps/common/SteamLinuxRuntime_sniper/_v2-entry-point
#   4. $HOME/.local/share/Steam/steamapps/common/SteamLinuxRuntime_sniper/_v2-entry-point
# Prints absolute path and exits 0 when found. Prints nothing and exits 1 when not found.
# ---------------------------------------------------------------------------
wb_container_detect() {
  # 1. Explicit env override. Canonicalize via realpath so `..`-laden paths
  # can't hide the real target from the audit log / error output.
  if [[ -n "${WB_CONTAINER_ENTRY:-}" ]]; then
    local canon_entry
    canon_entry="$(realpath -m "${WB_CONTAINER_ENTRY}" 2>/dev/null || echo "${WB_CONTAINER_ENTRY}")"
    if [[ -x "${canon_entry}" ]]; then
      printf '%s' "${canon_entry}"
      return 0
    fi
    # Override set but not executable — still fail cleanly
    return 1
  fi

  # 2-4. Well-known Steam installation paths
  local slr_subpath="steamapps/common/SteamLinuxRuntime_sniper/_v2-entry-point"
  local -a candidates=(
    "${HOME}/.steam/steam/${slr_subpath}"
    "${HOME}/.steam/root/${slr_subpath}"
    "${HOME}/.local/share/Steam/${slr_subpath}"
  )

  local candidate
  for candidate in "${candidates[@]}"; do
    if [[ -x "${candidate}" ]]; then
      printf '%s' "${candidate}"
      return 0
    fi
  done

  return 1
}

# ---------------------------------------------------------------------------
# wb_container_compose_argv <entry_point> <prefix_path> <dist_path> <wine_cmd> [args...]
#
# Produce a pressure-vessel invocation argv, emitting one element per line
# on stdout so callers can reconstruct it safely:
#
#   while IFS= read -r; argv+=("$REPLY"); done < <(wb_container_compose_argv ...)
#
# Output format:
#   <entry_point>
#   --filesystem=<prefix_path>
#   --filesystem=<dist_path>            # so wineloader is visible inside the sandbox
#   --verb=waitforexitandrun
#   --
#   <wine_cmd>
#   [args...]
#
# Both bind-mounts are needed: the prefix holds the user's drive_c; the dist
# holds the wine binaries and libraries. If WB_HOME is outside $HOME (e.g.
# a mounted drive or NFS share), the second bind is load-bearing — without
# it pressure-vessel reports the wineloader as "not found".
# ---------------------------------------------------------------------------
wb_container_compose_argv() {
  local entry_point="$1"
  local prefix_path="$2"
  local dist_path="$3"
  local wine_cmd="$4"
  shift 4

  printf '%s\n' "${entry_point}"
  printf '%s\n' "--filesystem=${prefix_path}"
  printf '%s\n' "--filesystem=${dist_path}"
  printf '%s\n' "--verb=waitforexitandrun"
  printf '%s\n' "--"
  printf '%s\n' "${wine_cmd}"

  local arg
  for arg in "$@"; do
    printf '%s\n' "${arg}"
  done
}
