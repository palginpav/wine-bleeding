#!/bin/sh
# .github/workflows/build-tools-manifest.sh
#
# Aggregate per-job tarball metadata into a single manifest.json conforming to
# w1-managed-tools-manifest-schema.md (schema_version: 1).
#
# Usage:
#   build-tools-manifest.sh <tarball-dir> <release-tag>
#
# Arguments:
#   tarball-dir   — directory containing *.tar.zst and matching *.meta.json files
#   release-tag   — GitHub release tag (e.g. tools-v20260424); used in download URLs
#
# Output: manifest.json written to stdout.
#
# Requirements: POSIX sh, jq.
# Exit codes:
#   0  success
#   1  usage / missing argument
#   2  tarball-dir does not exist or is empty
#   3  required tool (jq) is missing
#   4  manifest validation failed (output would be malformed)

set -eu

# ---------------------------------------------------------------------------
# Argument handling
# ---------------------------------------------------------------------------
if [ "$#" -ne 2 ]; then
  printf 'Usage: %s <tarball-dir> <release-tag>\n' "$0" >&2
  exit 1
fi

TARBALL_DIR="$1"
RELEASE_TAG="$2"

if [ ! -d "${TARBALL_DIR}" ]; then
  printf 'ERROR: tarball-dir %s does not exist\n' "${TARBALL_DIR}" >&2
  exit 2
fi

if ! command -v jq >/dev/null 2>&1; then
  printf 'ERROR: jq is required but not found in PATH\n' >&2
  exit 3
fi

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------
SCHEMA_VERSION=1
MANIFEST_URL="https://github.com/palginpav/wine-bleeding/releases/latest/download/manifest.json"
GITHUB_RELEASE_BASE="https://github.com/palginpav/wine-bleeding/releases/download"
GENERATED_UTC="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
GENERATOR="build-tools-manifest.sh v1.0"

# ---------------------------------------------------------------------------
# Tool metadata (display names, descriptions, source references)
# These stay stable across releases; only versions / flavors change.
# ---------------------------------------------------------------------------
tool_display_name() {
  case "$1" in
    mingw-w64)     printf 'MinGW-w64 cross toolchain' ;;
    glslang)       printf 'glslang shader compiler' ;;
    *)             printf '%s' "$1" ;;
  esac
}

# Canonical manifest key per tool. Must match the tool keys used by
# runtime/libexec/wb-preflight.py and runtime/libexec/wb-tools-manager.py
# so the manager's flavor-pick step can look up a tool by its preflight
# name. Tarball filenames may use a shorter form — only the manifest KEY
# has to match across W3 + W4.
tool_manifest_key() {
  case "$1" in
    mingw-w64)     printf 'mingw-w64-gcc' ;;
    *)             printf '%s' "$1" ;;
  esac
}

tool_description() {
  case "$1" in
    mingw-w64)
      printf 'Windows cross-compiler (x86_64 + i686 targets). Required by DXVK, VKD3D, NVAPI.' ;;
    glslang)
      printf 'SPIR-V shader compiler for DXVK.' ;;
    *)
      printf '' ;;
  esac
}

tool_source_ref() {
  _sr_tool="$1"
  _sr_version="$2"
  case "${_sr_tool}" in
    mingw-w64)
      printf 'https://github.com/mirror/mingw-w64/releases/tag/v%s' "${_sr_version}" ;;
    glslang)
      printf 'https://github.com/KhronosGroup/glslang/releases/tag/%s' "${_sr_version}" ;;
    *)
      printf '' ;;
  esac
}

# ---------------------------------------------------------------------------
# Collect .meta.json sidecar files produced by each matrix job.
# Each sidecar has: tool, version, arch, flavor, glibc_min, glibc_max,
# tarball_name, sha256, size_bytes, build_host.
# ---------------------------------------------------------------------------
META_FILES="$(find "${TARBALL_DIR}" -name '*.meta.json' | sort)"

if [ -z "${META_FILES}" ]; then
  printf 'ERROR: no *.meta.json files found in %s\n' "${TARBALL_DIR}" >&2
  exit 2
fi

# ---------------------------------------------------------------------------
# Validate that every listed tarball file actually exists and has non-zero size.
# ---------------------------------------------------------------------------
for meta in ${META_FILES}; do
  tarball_name="$(jq -r '.tarball_name' "${meta}")"
  tarball_path="${TARBALL_DIR}/${tarball_name}"

  if [ ! -f "${tarball_path}" ]; then
    printf 'ERROR: tarball %s listed in %s does not exist\n' \
      "${tarball_path}" "${meta}" >&2
    exit 2
  fi

  size="$(wc -c < "${tarball_path}")"
  if [ "${size}" -eq 0 ]; then
    printf 'ERROR: tarball %s is empty (0 bytes)\n' "${tarball_path}" >&2
    exit 2
  fi

  sha_from_meta="$(jq -r '.sha256' "${meta}")"
  if [ -z "${sha_from_meta}" ] || [ "${sha_from_meta}" = "null" ]; then
    printf 'ERROR: sha256 missing in %s\n' "${meta}" >&2
    exit 4
  fi
done

# ---------------------------------------------------------------------------
# Discover the unique set of tools across all meta files.
# ---------------------------------------------------------------------------
TOOLS="$(for meta in ${META_FILES}; do jq -r '.tool' "${meta}"; done | sort -u)"

# ---------------------------------------------------------------------------
# Build the JSON structure using jq.
# Strategy: assemble a shell variable per tool as a JSON fragment, then
# compose them with jq --argjson into the final document.
#
# We iterate: for each tool, find all meta files for that tool, collect their
# version (they should all be the same version for a given tool in one CI run),
# then build the flavors array.
# ---------------------------------------------------------------------------

# Accumulate tool fragments into a jq-filter compatible JSON object string.
tools_json="{}"

for tool in ${TOOLS}; do
  # Collect the tool version (should be identical for all flavors).
  tool_version="$(for meta in ${META_FILES}; do
    jq -r "select(.tool == \"${tool}\") | .version" "${meta}"
  done | sort -u | head -1)"

  if [ -z "${tool_version}" ]; then
    printf 'WARN: could not determine version for tool %s — skipping\n' \
      "${tool}" >&2
    continue
  fi

  display_name="$(tool_display_name "${tool}")"
  description="$(tool_description "${tool}")"
  source_ref="$(tool_source_ref "${tool}" "${tool_version}")"
  released_utc="${GENERATED_UTC}"

  # Build the flavors JSON array for this tool+version.
  flavors_json="[]"
  for meta in ${META_FILES}; do
    # Skip entries for other tools.
    this_tool="$(jq -r '.tool' "${meta}")"
    if [ "${this_tool}" != "${tool}" ]; then
      continue
    fi

    tarball_name="$(jq -r '.tarball_name' "${meta}")"
    sha256="$(jq -r '.sha256' "${meta}")"
    arch="$(jq -r '.arch' "${meta}")"
    glibc_min="$(jq -r '.glibc_min' "${meta}")"
    build_host="$(jq -r '.build_host' "${meta}")"

    # Re-read size_bytes from the actual file to be authoritative.
    tarball_path="${TARBALL_DIR}/${tarball_name}"
    size_bytes="$(wc -c < "${tarball_path}")"

    # Validate sha256 format: exactly 64 lowercase hex chars.
    if ! printf '%s' "${sha256}" | grep -qE '^[0-9a-f]{64}$'; then
      printf 'ERROR: sha256 for %s is not 64 lowercase hex chars: %s\n' \
        "${tarball_name}" "${sha256}" >&2
      exit 4
    fi

    download_url="${GITHUB_RELEASE_BASE}/${RELEASE_TAG}/${tarball_name}"

    # Append this flavor to the flavors array.
    flavor_entry="$(jq -n \
      --arg glibc_min "${glibc_min}" \
      --arg arch "${arch}" \
      --arg url "${download_url}" \
      --arg sha256 "${sha256}" \
      --argjson size_bytes "${size_bytes}" \
      --arg build_host "${build_host}" \
      '{
        glibc_min: $glibc_min,
        glibc_max: null,
        arch: $arch,
        url: $url,
        sha256: $sha256,
        size_bytes: $size_bytes,
        build_host: $build_host,
        notes: null
      }')"

    flavors_json="$(printf '%s' "${flavors_json}" \
      | jq --argjson entry "${flavor_entry}" '. + [$entry]')"
  done

  # Sort flavors by glibc_min descending (newest first) — mirrors the
  # manager's pick_flavor algorithm preference.
  flavors_json="$(printf '%s' "${flavors_json}" \
    | jq 'sort_by(.glibc_min | split(".") | map(tonumber)) | reverse')"

  # Build the version entry.
  version_entry="$(jq -n \
    --arg released_utc "${released_utc}" \
    --arg source_ref "${source_ref}" \
    --argjson flavors "${flavors_json}" \
    '{
      released_utc: $released_utc,
      source_ref: $source_ref,
      flavors: $flavors
    }')"

  # Build the tool entry.
  tool_entry="$(jq -n \
    --arg display_name "${display_name}" \
    --arg description "${description}" \
    --arg latest_version "${tool_version}" \
    --arg version_key "${tool_version}" \
    --argjson version_entry "${version_entry}" \
    '{
      display_name: $display_name,
      description: $description,
      latest_version: $latest_version,
      versions: { ($version_key): $version_entry }
    }')"

  # Merge this tool into the tools object under its canonical manifest key
  # (matches wb-preflight.py's probe key; tarball filenames use the short form).
  manifest_key="$(tool_manifest_key "${tool}")"
  tools_json="$(printf '%s' "${tools_json}" \
    | jq --arg tool_key "${manifest_key}" --argjson tool_entry "${tool_entry}" \
      '. + { ($tool_key): $tool_entry }')"
done

# ---------------------------------------------------------------------------
# Assemble the top-level manifest document.
# ---------------------------------------------------------------------------
manifest="$(jq -n \
  --argjson schema_version "${SCHEMA_VERSION}" \
  --arg manifest_url "${MANIFEST_URL}" \
  --arg generated_utc "${GENERATED_UTC}" \
  --arg generator "${GENERATOR}" \
  --argjson tools "${tools_json}" \
  '{
    schema_version: $schema_version,
    manifest_url: $manifest_url,
    generated_utc: $generated_utc,
    generator: $generator,
    tools: $tools
  }')"

# ---------------------------------------------------------------------------
# Final validation before emitting.
# ---------------------------------------------------------------------------

# schema_version must be 1.
sv="$(printf '%s' "${manifest}" | jq '.schema_version')"
if [ "${sv}" != "${SCHEMA_VERSION}" ]; then
  printf 'ERROR: schema_version mismatch in generated manifest: %s\n' "${sv}" >&2
  exit 4
fi

# manifest_url must start with https://.
mu="$(printf '%s' "${manifest}" | jq -r '.manifest_url')"
case "${mu}" in
  https://*) ;;
  *)
    printf 'ERROR: manifest_url does not start with https://: %s\n' "${mu}" >&2
    exit 4
    ;;
esac

# Every flavor URL must start with https://.
bad_urls="$(printf '%s' "${manifest}" \
  | jq -r '[.tools[].versions[].flavors[].url | select(startswith("https://") | not)] | length')"
if [ "${bad_urls}" != "0" ]; then
  printf 'ERROR: %s flavor URL(s) do not start with https://\n' "${bad_urls}" >&2
  exit 4
fi

# Every sha256 must be 64 lowercase hex chars.
bad_shas="$(printf '%s' "${manifest}" \
  | jq -r '[.tools[].versions[].flavors[].sha256 | select(test("^[0-9a-f]{64}$") | not)] | length')"
if [ "${bad_shas}" != "0" ]; then
  printf 'ERROR: %s sha256 value(s) failed format check\n' "${bad_shas}" >&2
  exit 4
fi

# Every size_bytes must be a positive integer.
bad_sizes="$(printf '%s' "${manifest}" \
  | jq -r '[.tools[].versions[].flavors[].size_bytes | select(. <= 0)] | length')"
if [ "${bad_sizes}" != "0" ]; then
  printf 'ERROR: %s size_bytes value(s) are zero or negative\n' "${bad_sizes}" >&2
  exit 4
fi

# ---------------------------------------------------------------------------
# Emit to stdout.
# ---------------------------------------------------------------------------
printf '%s\n' "${manifest}" | jq .
