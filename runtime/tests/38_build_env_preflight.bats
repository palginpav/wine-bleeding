#!/usr/bin/env bats
# runtime/tests/38_build_env_preflight.bats — wb-preflight.py contract tests
#
# Acceptance gates from W3.md:
#   1. --json emits valid JSON with expected top-level keys
#   2. --build-type components vs dist changes the tool set
#   3. Overlay merge: user override wins over shipped map
#   4. Missing distro falls back to tier-3 (recognized=false, no crash)
#
# All network calls are stubbed; tool probes use fake PATH binaries.

load "lib/common.bash"

PREFLIGHT="${BATS_TEST_DIRNAME}/../libexec/wb-preflight.py"
PKG_MAP="${BATS_TEST_DIRNAME}/../share/wb-preflight-packages.json"

setup() {
  TEST_HOME="$(mktemp -d)"
  export TEST_HOME

  # Fake tools dir — stub executables that print a valid version string.
  # python3 is NOT stubbed here so that the real python3 is used by wb-preflight.py.
  # The fake bin is prepended to PATH so fake tool stubs shadow real ones.
  FAKE_BIN="${TEST_HOME}/fake-bin"
  mkdir -p "${FAKE_BIN}"

  # Helper: write a stub that prints a version string and exits 0
  _make_stub() {
    local name="$1"
    local ver="$2"
    cat > "${FAKE_BIN}/${name}" <<STUB
#!/usr/bin/env bash
echo "${name} version ${ver}"
exit 0
STUB
    chmod +x "${FAKE_BIN}/${name}"
  }

  # Stubs for all components tools at versions above the floor.
  # These shadow system binaries so probes return controlled versions.
  _make_stub gcc              "12.3.0"
  _make_stub g++              "12.3.0"
  _make_stub make             "4.3"
  _make_stub meson            "1.2.0"
  _make_stub ninja            "1.11.1"
  _make_stub glslangValidator "15.0.0"
  _make_stub glslang          "15.0.0"
  _make_stub x86_64-w64-mingw32-gcc "12.2.0"
  _make_stub pkg-config       "1.8.1"
  _make_stub pkgconf           "1.8.1"
  _make_stub git              "2.41.0"
  # dist-only tools
  _make_stub flex             "2.6.4"
  _make_stub bison            "3.8.2"
  _make_stub autoconf         "2.71"

  # Record real python3 path before PATH mutation (used for --version/--pretty tests)
  REAL_PYTHON3="$(command -v python3)"
  export REAL_PYTHON3

  export ORIG_PATH="${PATH}"
  export PATH="${FAKE_BIN}:${PATH}"

  # Isolate the managed-tools probe — wb-preflight.py probes
  # $WB_HOME/build-tools (or $XDG_DATA_HOME/wine-bleeding/build-tools) for
  # managed tool installs alongside the system PATH probe. Without this
  # override, a real installed tool in the developer's home (e.g.
  # ~/.local/share/wine-bleeding/build-tools/mingw-w64-gcc/current/bin/...)
  # leaks into the test and a "tool missing" case actually finds the
  # binary, breaking overall_ok=false expectations.
  export WB_MANAGED_TOOLS_DIR="${TEST_HOME}/managed-tools-empty"
  mkdir -p "${WB_MANAGED_TOOLS_DIR}"

  # Fake os-release pointing at fedora
  FAKE_OS_RELEASE="${TEST_HOME}/os-release-fedora"
  cat > "${FAKE_OS_RELEASE}" <<'EOF'
ID=fedora
VERSION_ID=40
PRETTY_NAME="Fedora Linux 40 (Workstation Edition)"
ID_LIKE=rhel
EOF
  export FAKE_OS_RELEASE
}

teardown() {
  export PATH="${ORIG_PATH}"
  rm -rf "${TEST_HOME}"
}

# ---------------------------------------------------------------------------
# Helper: run preflight with test fixtures
# Stderr is suppressed so bats ${output} contains only stdout (the JSON).
# ---------------------------------------------------------------------------
_run_preflight() {
  python3 "${PREFLIGHT}" \
    --package-map "${PKG_MAP}" \
    --overlay-dir "${TEST_HOME}/no-overlays" \
    --os-release "${FAKE_OS_RELEASE}" \
    "$@" 2>/dev/null
}

# ===========================================================================
# Gate 1: --json emits valid JSON with expected top-level keys
# ===========================================================================

@test "preflight --json emits parseable JSON with required top-level keys" {
  run _run_preflight --json --build-type components
  [ "${status}" -eq 0 ] || [ "${status}" -eq 1 ]

  # Must be valid JSON: python3 can parse it back
  echo "${output}" | python3 -c "
import json, sys
data = json.load(sys.stdin)
required = ['schema_version', 'preflight_version', 'timestamp_utc', 'distro',
            'build_type', 'overall_ok', 'overlays_loaded', 'overlay_errors', 'tools']
for k in required:
    assert k in data, f'missing key: {k}'
assert data['schema_version'] == 1
assert isinstance(data['overall_ok'], bool)
assert isinstance(data['tools'], list)
assert len(data['tools']) > 0
# each tool must have the stable keys
for t in data['tools']:
    for tk in ['name', 'found', 'path', 'version', 'min_version', 'ok', 'reason',
               'distro_install_cmd', 'source_build_fallback',
               'source_build_fallback_label', 'source_build_fallback_cmd', 'notes']:
        assert tk in t, f'tool missing key: {tk}'
print('JSON shape OK')
"
}

@test "preflight --json exit 0 when all tools OK" {
  run _run_preflight --json --build-type components
  [ "${status}" -eq 0 ]
}

@test "preflight --json overall_ok=true when all stubs present and above floor" {
  run _run_preflight --json --build-type components
  echo "${output}" | python3 -c "
import json, sys
data = json.load(sys.stdin)
assert data['overall_ok'] is True, f'expected overall_ok=true, got: {data[\"overall_ok\"]}'
"
}

@test "preflight --json overall_ok=false when a tool is missing" {
  # Remove the mingw stub — x86_64-w64-mingw32-gcc is not installed system-wide
  # on CI / test machines, so removing from fake-bin makes it truly not found.
  rm "${FAKE_BIN}/x86_64-w64-mingw32-gcc"
  run _run_preflight --json --build-type components
  [ "${status}" -eq 1 ]
  echo "${output}" | python3 -c "
import json, sys
data = json.load(sys.stdin)
assert data['overall_ok'] is False, 'expected overall_ok=false'
mingw_row = next(t for t in data['tools'] if t['name'] == 'mingw-w64-gcc')
assert mingw_row['found'] is False, f'expected found=false, got: {mingw_row}'
assert mingw_row['reason'] == 'not_found'
"
}

@test "preflight --json overall_ok=false when tool version too old" {
  # Replace meson stub with one reporting a version below the floor (0.60.0)
  cat > "${FAKE_BIN}/meson" <<'EOF'
#!/usr/bin/env bash
echo "0.58.2"
exit 0
EOF
  chmod +x "${FAKE_BIN}/meson"
  run _run_preflight --json --build-type components
  [ "${status}" -eq 1 ]
  echo "${output}" | python3 -c "
import json, sys
data = json.load(sys.stdin)
meson_row = next(t for t in data['tools'] if t['name'] == 'meson')
assert meson_row['ok'] is False
assert meson_row['reason'] == 'version_too_old'
assert meson_row['version'] == '0.58.2'
"
}

# ===========================================================================
# Gate 2: --build-type components vs dist changes tool set
# ===========================================================================

@test "preflight components build-type includes exactly 8 core tools" {
  run _run_preflight --json --build-type components
  echo "${output}" | python3 -c "
import json, sys
data = json.load(sys.stdin)
names = [t['name'] for t in data['tools']]
expected = {'gcc', 'make', 'meson', 'ninja', 'glslang', 'mingw-w64-gcc', 'pkg-config', 'git'}
assert set(names) == expected, f'got: {names}'
assert data['build_type'] == 'components'
"
}

@test "preflight dist build-type includes flex, bison, autoconf in addition to core 8" {
  run _run_preflight --json --build-type dist
  echo "${output}" | python3 -c "
import json, sys
data = json.load(sys.stdin)
names = set(t['name'] for t in data['tools'])
for extra in ['flex', 'bison', 'autoconf']:
    assert extra in names, f'missing dist-only tool: {extra}'
assert data['build_type'] == 'dist'
assert len(data['tools']) == 11
"
}

@test "preflight --tool overrides build-type tool list" {
  run _run_preflight --tool meson,ninja
  echo "${output}" | python3 -c "
import json, sys
data = json.load(sys.stdin)
names = [t['name'] for t in data['tools']]
assert names == ['meson', 'ninja'], f'got: {names}'
"
}

@test "preflight --tool with unknown name exits 2 and no JSON" {
  run "${REAL_PYTHON3}" "${PREFLIGHT}" \
    --package-map "${PKG_MAP}" \
    --os-release "${FAKE_OS_RELEASE}" \
    --tool meson,foobar 2>/dev/null
  [ "${status}" -eq 2 ]
}

# ===========================================================================
# Gate 3: Overlay merge — user override wins
# ===========================================================================

@test "overlay merge: user distro.tool entry replaces shipped entry" {
  local overlay_dir="${TEST_HOME}/overlays"
  mkdir -p "${overlay_dir}"
  cat > "${overlay_dir}/custom.json" <<'EOF'
{
  "distros": {
    "fedora": {
      "tools": {
        "meson": {
          "package_name": "meson-custom-overlay",
          "install_cmd_template": "sudo dnf install --custom {packages}",
          "source_build_fallback": "pip-install-meson"
        }
      }
    }
  }
}
EOF

  run python3 "${PREFLIGHT}" \
    --package-map "${PKG_MAP}" \
    --overlay-dir "${overlay_dir}" \
    --os-release "${FAKE_OS_RELEASE}" \
    --json --build-type components 2>/dev/null

  echo "${output}" | python3 -c "
import json, sys
data = json.load(sys.stdin)
assert len(data['overlays_loaded']) == 1, f'expected 1 overlay, got: {data[\"overlays_loaded\"]}'
meson_row = next(t for t in data['tools'] if t['name'] == 'meson')
cmd = meson_row['distro_install_cmd']
assert 'meson-custom-overlay' in cmd, f'overlay did not win: {cmd}'
assert '--custom' in cmd, f'custom template not applied: {cmd}'
"
}

@test "overlay merge: invalid JSON overlay is logged to overlay_errors, shipped map preserved" {
  local overlay_dir="${TEST_HOME}/overlays-bad"
  mkdir -p "${overlay_dir}"
  printf 'this is not json' > "${overlay_dir}/broken.json"

  run python3 "${PREFLIGHT}" \
    --package-map "${PKG_MAP}" \
    --overlay-dir "${overlay_dir}" \
    --os-release "${FAKE_OS_RELEASE}" \
    --json --build-type components 2>/dev/null

  # Should still exit 0 (all tools OK) or 1 (some missing), not crash
  [ "${status}" -eq 0 ] || [ "${status}" -eq 1 ]

  echo "${output}" | python3 -c "
import json, sys
data = json.load(sys.stdin)
assert len(data['overlay_errors']) == 1, f'expected 1 overlay error, got: {data[\"overlay_errors\"]}'
err = data['overlay_errors'][0]
assert 'broken.json' in err['path']
assert err['message']
# shipped meson entry still present (not wiped by bad overlay)
meson_row = next(t for t in data['tools'] if t['name'] == 'meson')
assert meson_row['distro_install_cmd'] is not None
"
}

@test "overlay _floors override changes the effective floor" {
  local overlay_dir="${TEST_HOME}/overlays-floor"
  mkdir -p "${overlay_dir}"
  # Set meson floor to a high value so our 1.2.0 stub still passes but
  # an unreachable floor (99.0.0) would fail
  cat > "${overlay_dir}/high-floor.json" <<'EOF'
{
  "_floors": {
    "meson": "99.0.0"
  }
}
EOF

  run python3 "${PREFLIGHT}" \
    --package-map "${PKG_MAP}" \
    --overlay-dir "${overlay_dir}" \
    --os-release "${FAKE_OS_RELEASE}" \
    --json --tool meson 2>/dev/null

  # With floor=99.0.0, meson 1.2.0 must fail
  echo "${output}" | python3 -c "
import json, sys
data = json.load(sys.stdin)
meson_row = next(t for t in data['tools'] if t['name'] == 'meson')
assert meson_row['min_version'] == '99.0.0', f'floor override not applied: {meson_row[\"min_version\"]}'
assert meson_row['ok'] is False
assert meson_row['reason'] == 'version_too_old'
"
}

# ===========================================================================
# Gate 4: Missing distro → tier-3 only, no crash
# ===========================================================================

@test "unrecognized distro: recognized=false, no crash, fallback install hints present" {
  local fake_release="${TEST_HOME}/os-release-unknown"
  cat > "${fake_release}" <<'EOF'
ID=voidlinux
VERSION_ID=rolling
PRETTY_NAME="Void Linux"
EOF

  run python3 "${PREFLIGHT}" \
    --package-map "${PKG_MAP}" \
    --overlay-dir "${TEST_HOME}/no-overlays" \
    --os-release "${fake_release}" \
    --json --build-type components 2>/dev/null

  # Must not crash (exit 0 or 1 only)
  [ "${status}" -eq 0 ] || [ "${status}" -eq 1 ]

  echo "${output}" | python3 -c "
import json, sys
data = json.load(sys.stdin)
assert data['distro']['id'] == 'voidlinux'
assert data['distro']['recognized'] is False
# All tools must still have an install_cmd (from fallback section)
for t in data['tools']:
    assert t['distro_install_cmd'] is not None, f'no install_cmd for {t[\"name\"]}'
# Source-build fallbacks still present for meson/glslang/mingw
slugs = {t['name']: t['source_build_fallback'] for t in data['tools']}
assert slugs.get('meson') == 'pip-install-meson'
assert slugs.get('glslang') == 'wb-build-glslang'
assert slugs.get('mingw-w64-gcc') == 'build-mingw-from-source'
"
}

@test "missing os-release entirely: distro.id=unknown, no crash" {
  run python3 "${PREFLIGHT}" \
    --package-map "${PKG_MAP}" \
    --overlay-dir "${TEST_HOME}/no-overlays" \
    --os-release "${TEST_HOME}/nonexistent-os-release" \
    --json --tool gcc 2>/dev/null

  [ "${status}" -eq 0 ] || [ "${status}" -eq 1 ]
  echo "${output}" | python3 -c "
import json, sys
data = json.load(sys.stdin)
assert data['distro']['id'] == 'unknown'
assert data['distro']['recognized'] is False
"
}

# ===========================================================================
# Additional: distro recognition + install_cmd format
# ===========================================================================

@test "recognized fedora distro: meson install cmd contains dnf" {
  run _run_preflight --json --tool meson
  echo "${output}" | python3 -c "
import json, sys
data = json.load(sys.stdin)
assert data['distro']['id'] == 'fedora'
assert data['distro']['recognized'] is True
meson = next(t for t in data['tools'] if t['name'] == 'meson')
assert 'dnf' in meson['distro_install_cmd'], f'expected dnf in: {meson[\"distro_install_cmd\"]}'
"
}

@test "preflight --version prints version and exits 0" {
  # Use REAL_PYTHON3 to avoid the fake python3 stub in FAKE_BIN
  run "${REAL_PYTHON3}" "${PREFLIGHT}" --version
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"wb-preflight.py"* ]]
}

@test "preflight --pretty produces tabular output (not JSON)" {
  # Use REAL_PYTHON3; _run_preflight also goes through REAL_PYTHON3 via the helper
  run "${REAL_PYTHON3}" "${PREFLIGHT}" \
    --package-map "${PKG_MAP}" \
    --overlay-dir "${TEST_HOME}/no-overlays" \
    --os-release "${FAKE_OS_RELEASE}" \
    --pretty --build-type components
  [ "${status}" -eq 0 ] || [ "${status}" -eq 1 ]
  # pretty output starts with 'Distro:', not '{'
  [[ "${output}" == *"Distro:"* ]]
  [[ "${output}" != "{"* ]]
}

@test "JSON shape: distro_install_cmd is non-null for recognized distro tools" {
  run _run_preflight --json --build-type components
  echo "${output}" | python3 -c "
import json, sys
data = json.load(sys.stdin)
assert data['distro']['recognized'] is True
for t in data['tools']:
    assert t['distro_install_cmd'] is not None, f'null install_cmd for {t[\"name\"]}'
"
}

@test "JSON shape: source_build_fallback_cmd is non-null for meson/glslang/mingw" {
  run _run_preflight --json --build-type components
  echo "${output}" | python3 -c "
import json, sys
data = json.load(sys.stdin)
slugs = {t['name']: t for t in data['tools']}
for tool in ['meson', 'glslang', 'mingw-w64-gcc']:
    t = slugs[tool]
    assert t['source_build_fallback'] is not None, f'{tool} missing fallback slug'
    assert t['source_build_fallback_cmd'] is not None, f'{tool} missing fallback cmd'
    assert t['source_build_fallback_label'] is not None, f'{tool} missing fallback label'
"
}
