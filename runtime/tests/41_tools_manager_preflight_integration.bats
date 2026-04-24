#!/usr/bin/env bats
# runtime/tests/41_tools_manager_preflight_integration.bats
# W6a preflight + dialog integration tests (7 cases from W6.md §W6a, point 2)
#
#   1. wb-preflight.py without managed install → source=null for missing tools
#   2. With stub glslangValidator in managed dir → ok=true, source=managed
#   3. With cached manifest listing glslang → managed_fallback.available=true
#   4. Without manifest cache → managed_fallback.available=false (probe is pure)
#   5. Dialog with managed_fallback.available=true → "Install <tool> via manager"
#      button appears in yad ARGV log
#   6. rc=60 → tools-manager-install:glslang slug dispatched (fake manager, no network)
#   7. rc=61 → tools-manager-check slug invoked (fake manager, no network)

load "lib/common.bash"

PREFLIGHT="${BATS_TEST_DIRNAME}/../libexec/wb-preflight.py"
PKG_MAP="${BATS_TEST_DIRNAME}/../share/wb-preflight-packages.json"
WB_GUI_LIB="${BATS_TEST_DIRNAME}/../src/wb-gui-lib"
WB_LIB="${BATS_TEST_DIRNAME}/../src/wb-lib"
FAKE_YAD_DIR="${BATS_TEST_DIRNAME}/fixtures/fake-yad"
MANAGER="${BATS_TEST_DIRNAME}/../libexec/wb-tools-manager.py"

# ---------------------------------------------------------------------------
# Multi-response helpers (mirrored from 39_build_env_frontend.bats)
# ---------------------------------------------------------------------------
_mk_responses_dir() {
  local d="${TEST_DIR}/responses_$$"
  mkdir -p "${d}"
  rm -f "${d}/.counter"
  echo "${d}"
}

_write_response() {
  local dir="${1}" n="${2}" content="${3}" rc="${4:-0}"
  local pad
  pad="$(printf '%03d' "${n}")"
  printf '%s' "${content}" > "${dir}/${pad}"
  printf '%s' "${rc}"      > "${dir}/${pad}.rc"
}

# ---------------------------------------------------------------------------
# setup / teardown
# ---------------------------------------------------------------------------

setup() {
  TEST_DIR="$(mktemp -d)"
  export TEST_DIR

  export WB_HOME="${TEST_DIR}/wb-home"
  mkdir -p "${WB_HOME}"

  # Managed tools directory (redirected to tmp for isolation)
  export WB_MANAGED_TOOLS_DIR="${TEST_DIR}/managed-tools"
  mkdir -p "${WB_MANAGED_TOOLS_DIR}"

  # Fake tool stubs — controlled PATH that does NOT include system tools.
  # We use a stripped PATH containing only our fake-bin so system-installed
  # tools (e.g. /usr/bin/glslangValidator) do not shadow our stubs.
  FAKE_BIN="${TEST_DIR}/fake-bin"
  mkdir -p "${FAKE_BIN}"

  # Save the original PATH for teardown
  export ORIG_PATH="${PATH}"

  _make_stub() {
    local name="${1}" ver="${2}"
    cat > "${FAKE_BIN}/${name}" <<STUB
#!/usr/bin/env bash
echo "${name} version ${ver}"
exit 0
STUB
    chmod +x "${FAKE_BIN}/${name}"
  }
  _make_stub gcc              "12.3.0"
  _make_stub g++              "12.3.0"
  _make_stub make             "4.3"
  _make_stub meson            "1.2.0"
  _make_stub ninja            "1.11.1"
  _make_stub pkg-config       "1.8.1"
  _make_stub pkgconf           "1.8.1"
  _make_stub git              "2.41.0"
  # Deliberately NO glslangValidator and NO x86_64-w64-mingw32-gcc stubs.
  #
  # The system has /usr/bin/glslangValidator installed. We cannot block it via
  # PATH because bats tests need system utilities (touch, etc.). Instead, we use
  # a preflight-specific PATH override: when running preflight in tests 1-4,
  # we pass PATH="${FAKE_BIN}" (no /usr/bin) to the python3 subprocess.
  # This is safe because wb-preflight.py itself only uses python stdlib + PATH
  # for tool discovery, not for its own interpreter dependencies.
  # PREFLIGHT_PATH: restricted PATH for preflight tool-discovery tests.
  # Contains FAKE_BIN + a "system-safe" directory that has python3 but NOT
  # glslangValidator. We create a wrapper dir with symlinks for needed system
  # utilities but explicitly omitting glslang.
  SAFE_SYS_BIN="${TEST_DIR}/safe-sys-bin"
  mkdir -p "${SAFE_SYS_BIN}"
  local _t _bin
  for _t in python3 jq tar zstd sha256sum date basename dirname stat flock \
             find rm mkdir ln cp chmod cat printf sed grep awk touch id; do
    _bin="$(command -v "${_t}" 2>/dev/null || true)"
    if [[ -n "${_bin}" ]]; then
      ln -sfn "${_bin}" "${SAFE_SYS_BIN}/${_t}"
    fi
  done
  export PREFLIGHT_PATH="${FAKE_BIN}:${SAFE_SYS_BIN}"

  export PATH="${FAKE_BIN}:${PATH}"

  # Fake os-release
  FAKE_OS_RELEASE="${TEST_DIR}/os-release-fedora"
  cat > "${FAKE_OS_RELEASE}" <<'EOF'
ID=fedora
VERSION_ID=40
PRETTY_NAME="Fedora Linux 40 (Workstation Edition)"
ID_LIKE=rhel
EOF
  export FAKE_OS_RELEASE

  # yad test infrastructure
  export WB_TEST_YAD_LOG="${TEST_DIR}/yad.log"
  export WB_TEST_YAD_RESPONSE="${TEST_DIR}/yad_response.txt"
  export WB_TEST_YAD_RESPONSE_RC="0"
  export WB_TEST_YAD_RESPONSES_DIR=""
  touch "${WB_TEST_YAD_LOG}"
  printf '' > "${WB_TEST_YAD_RESPONSE}"
}

teardown() {
  export PATH="${ORIG_PATH:-${PATH}}"
  rm -rf "${TEST_DIR}"
}

# Helper: run preflight with standard test args.
# Uses PREFLIGHT_PATH (FAKE_BIN only) so system tools like /usr/bin/glslangValidator
# are not on PATH during tool discovery — allowing us to control which tools appear
# as installed vs. missing without relying on the system state.
_run_preflight() {
  PATH="${PREFLIGHT_PATH}" python3 "${PREFLIGHT}" \
    --package-map "${PKG_MAP}" \
    --overlay-dir "${TEST_DIR}/no-overlays" \
    --os-release "${FAKE_OS_RELEASE}" \
    "$@" 2>/dev/null
}

# Run preflight with the managed-capable package map (managed_fallback=true for glslang)
_run_preflight_managed() {
  PATH="${PREFLIGHT_PATH}" WB_MANAGED_TOOLS_DIR="${WB_MANAGED_TOOLS_DIR}" \
  python3 "${PREFLIGHT}" \
    --package-map "${TEST_DIR}/pkg-map-managed.json" \
    --overlay-dir "${TEST_DIR}/no-overlays" \
    --os-release "${FAKE_OS_RELEASE}" \
    "$@" 2>/dev/null
}

# Create a package map with managed_fallback=true for glslang (used in tests 3/4)
_setup_managed_pkg_map() {
  python3 - "${PKG_MAP}" "${TEST_DIR}/pkg-map-managed.json" <<'PYEOF'
import json, sys
with open(sys.argv[1]) as f:
    data = json.load(f)
# Add managed_fallback=true for glslang in all distros and fallback
for distro_id, ddata in data.get("distros", {}).items():
    tools = ddata.setdefault("tools", {})
    tools.setdefault("glslang", {})["managed_fallback"] = True
fb = data.setdefault("fallback", {}).setdefault("tools", {})
fb.setdefault("glslang", {})["managed_fallback"] = True
with open(sys.argv[2], "w") as f:
    json.dump(data, f, indent=2)
PYEOF
}

# ===========================================================================
# Case 1: wb-preflight.py without managed install → source=null for missing tools
# ===========================================================================

@test "preflight: tools missing from both PATH and managed dir have source=null" {
  # No stubs for glslang/mingw; no managed install either.
  # Ensure managed dir has no current symlink.
  rm -rf "${WB_MANAGED_TOOLS_DIR}/glslang" "${WB_MANAGED_TOOLS_DIR}/mingw-w64-gcc"

  run _run_preflight --json --tool glslang,mingw-w64-gcc

  # Should exit 1 (tools missing)
  [ "${status}" -eq 1 ]

  echo "${output}" | python3 -c "
import json, sys
data = json.load(sys.stdin)
tools = {t['name']: t for t in data['tools']}

glslang = tools.get('glslang', {})
assert glslang.get('ok') is False, f'expected ok=false for glslang, got: {glslang}'
assert glslang.get('source') is None or glslang.get('source') == 'null' or glslang.get('source') == '', \
    f'expected source=null for missing glslang, got: {glslang.get(\"source\")}'
assert glslang.get('found') is False, f'expected found=false for glslang, got: {glslang}'

mingw = tools.get('mingw-w64-gcc', {})
assert mingw.get('ok') is False, f'expected ok=false for mingw, got: {mingw}'
# source must be null/None (not found anywhere)
src = mingw.get('source')
assert src is None or src == '' or src == 'null', \
    f'expected null source for missing mingw, got: {src}'
print('source=null for missing tools OK')
"
}

# ===========================================================================
# Case 2: stub glslangValidator in managed dir → ok=true, source=managed
# ===========================================================================

@test "preflight: managed glslangValidator at current/bin/ → ok=true source=managed" {
  # Install a fake glslangValidator into the managed directory structure.
  # Layout: <managed_root>/glslang/15.0.0/bin/glslangValidator
  #         <managed_root>/glslang/current -> 15.0.0  (symlink)
  local glslang_ver_dir="${WB_MANAGED_TOOLS_DIR}/glslang/15.0.0"
  local managed_bin_dir="${glslang_ver_dir}/bin"
  mkdir -p "${managed_bin_dir}"
  cat > "${managed_bin_dir}/glslangValidator" <<'EOF'
#!/bin/sh
echo "glslangValidator 15.0.0"
exit 0
EOF
  chmod +x "${managed_bin_dir}/glslangValidator"

  # Create the 'current' symlink pointing to 15.0.0
  ln -sfn "15.0.0" "${WB_MANAGED_TOOLS_DIR}/glslang/current"

  run _run_preflight --json --tool glslang

  # Must exit 0 (tool found via managed path)
  [ "${status}" -eq 0 ]

  echo "${output}" | python3 -c "
import json, sys
data = json.load(sys.stdin)
tools = {t['name']: t for t in data['tools']}
g = tools.get('glslang', {})
assert g.get('ok') is True, f'expected ok=true, got: {g}'
assert g.get('source') == 'managed', f'expected source=managed, got: {g.get(\"source\")}'
assert g.get('found') is True, f'expected found=true, got: {g}'
print(f'glslang ok=true source=managed version={g.get(\"version\")}')
"
}

# ===========================================================================
# Case 3: cached manifest listing glslang → managed_fallback.available=true
# ===========================================================================

@test "preflight: with manifest.cache.json listing glslang → managed_fallback.available=true" {
  # NOTE: This test requires managed_fallback=true in the package map for glslang.
  # The shipped wb-preflight-packages.json does NOT have this set (production gap —
  # flagged in the W6a report for W6b to escalate). We use a modified package map.
  _setup_managed_pkg_map

  # Stage a manifest cache declaring glslang with flavors
  cat > "${WB_MANAGED_TOOLS_DIR}/manifest.cache.json" <<'EOF'
{
  "schema_version": 1,
  "manifest_url": "https://github.com/palginpav/wine-bleeding/releases/latest/download/manifest.json",
  "generated_utc": "2026-04-24T11:45:00Z",
  "tools": {
    "glslang": {
      "display_name": "glslang shader compiler",
      "latest_version": "15.0.0",
      "versions": {
        "15.0.0": {
          "flavors": [
            {
              "glibc_min": "2.31",
              "glibc_max": null,
              "arch": "x86_64",
              "url": "https://example.com/glslang.tar.zst",
              "sha256": "a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2",
              "size_bytes": 28134221
            }
          ]
        }
      }
    }
  }
}
EOF

  # No glslang stub on PATH, no managed binary installed
  run _run_preflight_managed --json --tool glslang

  [ "${status}" -eq 1 ]   # glslang missing → overall_ok=false

  echo "${output}" | python3 -c "
import json, sys
data = json.load(sys.stdin)
tools = {t['name']: t for t in data['tools']}
g = tools.get('glslang', {})
assert g.get('ok') is False, f'expected ok=false (not installed), got: {g}'
fb = g.get('managed_fallback', {})
assert fb.get('available') is True, f'expected managed_fallback.available=true, got: {fb}'
lv = fb.get('latest_version')
assert lv == '15.0.0', f'expected latest_version=15.0.0, got: {lv}'
print(f'managed_fallback.available=true latest_version={lv} OK')
"
}

# ===========================================================================
# Case 4: without manifest cache → managed_fallback.available=false (pure probe)
# ===========================================================================

@test "preflight: without manifest.cache.json → managed_fallback.available=false (no network)" {
  # NOTE: Same managed_fallback=true package map required to see the field populated.
  _setup_managed_pkg_map

  # Ensure no cache file exists
  rm -f "${WB_MANAGED_TOOLS_DIR}/manifest.cache.json"

  # No glslang on PATH
  run _run_preflight_managed --json --tool glslang

  [ "${status}" -eq 1 ]

  echo "${output}" | python3 -c "
import json, sys
data = json.load(sys.stdin)
tools = {t['name']: t for t in data['tools']}
g = tools.get('glslang', {})
fb = g.get('managed_fallback', {})
assert fb.get('available') is False, f'expected managed_fallback.available=false (no cache), got: {fb}'
print('managed_fallback.available=false without cache OK')
"
}

# ===========================================================================
# Case 5: dialog with managed_fallback.available=true → "Install via manager"
#         button appears in yad ARGV log
# ===========================================================================

@test "preflight dialog: Install via manager button appears when managed_fallback.available=true" {
  # Build a fixture preflight JSON with glslang missing but managed fallback available
  local fixture_json="${TEST_DIR}/fixture-managed.json"
  cat > "${fixture_json}" <<'EOF'
{
  "schema_version": 1,
  "preflight_version": "1.1.0",
  "timestamp_utc": "2026-04-24T12:00:00Z",
  "overall_ok": false,
  "distro": {
    "id": "fedora",
    "id_like": ["rhel"],
    "version_id": "40",
    "pretty_name": "Fedora Linux 40 (Workstation Edition)",
    "recognized": true,
    "refresh_cmd": "sudo dnf update"
  },
  "build_type": "components",
  "managed_tools_dir": "/tmp/managed-tools-test",
  "overlays_loaded": [],
  "overlay_errors": [],
  "tools": [
    {
      "name": "gcc",
      "found": true,
      "path": "/usr/bin/gcc",
      "version": "12.3.0",
      "min_version": "9.0.0",
      "ok": true,
      "reason": "ok",
      "source": "system",
      "distro_install_cmd": "sudo dnf install gcc",
      "source_build_fallback": null,
      "source_build_fallback_label": null,
      "source_build_fallback_cmd": null,
      "source_build_fallbacks": [],
      "managed_fallback": {"available": false, "latest_version": null, "manifest_url": ""},
      "notes": null
    },
    {
      "name": "glslang",
      "found": false,
      "path": null,
      "version": null,
      "min_version": "14.0.0",
      "ok": false,
      "reason": "not_found",
      "source": null,
      "distro_install_cmd": "sudo dnf install glslang",
      "source_build_fallback": "wb-build-glslang",
      "source_build_fallback_label": "Build glslang from source (~15 min)",
      "source_build_fallback_cmd": "tools/build-glslang.sh",
      "source_build_fallbacks": ["install-via-manager", "wb-build-glslang"],
      "managed_fallback": {
        "available": true,
        "latest_version": "15.0.0",
        "manifest_url": "https://github.com/palginpav/wine-bleeding/releases/latest/download/manifest.json"
      },
      "notes": null
    }
  ]
}
EOF

  # Fake-yad: return rc=1 (Cancel) on the first invocation
  export WB_TEST_YAD_RESPONSE_RC=1
  printf '' > "${WB_TEST_YAD_RESPONSE}"

  run bash -c "
    export PATH='${FAKE_YAD_DIR}:${PATH}'
    export WB_HOME='${WB_HOME}'
    export WB_TEST_YAD_LOG='${WB_TEST_YAD_LOG}'
    export WB_TEST_YAD_RESPONSE='${WB_TEST_YAD_RESPONSE}'
    export WB_TEST_YAD_RESPONSE_RC='${WB_TEST_YAD_RESPONSE_RC}'
    source '${WB_LIB}/wb-paths.sh'
    source '${WB_LIB}/wb-log.sh'
    source '${WB_LIB}/wb-json.sh'
    source '${WB_GUI_LIB}/wb-gui-dialogs.sh'

    _dialog_rc=0
    wb_gui_dialog_preflight_table 'Component Builder' '${fixture_json}' 'components' || _dialog_rc=\$?
    echo \"dialog_rc=\${_dialog_rc}\"
  "

  # yad was called (returned rc=1 from fake-yad)
  local log
  log="$(cat "${WB_TEST_YAD_LOG}")"
  [[ -n "${log}" ]]

  # The "Install glslang via manager" button must appear in the yad ARGV
  [[ "${log}" == *"Install glslang via manager"* ]] || \
    [[ "${log}" == *"via manager"* ]] || \
    [[ "${log}" == *"60"* ]]

  # "Check for updates" button must also be present (managed_tools_dir non-empty)
  [[ "${log}" == *"Check for updates"* ]] || [[ "${log}" == *"61"* ]]
}

# ===========================================================================
# Case 6: rc=60 → tools-manager-install:glslang slug dispatched (fake manager)
# ===========================================================================

@test "dialog rc=60 dispatches tools-manager-install:glslang slug via wb_gui_build_env_run_source_build" {
  # Install a FAKE wb-tools-manager.py on PATH that records its args and exits 0
  local fake_mgr_dir="${TEST_DIR}/fake-mgr-dir"
  mkdir -p "${fake_mgr_dir}"
  local fake_mgr_log="${TEST_DIR}/fake-mgr-calls.log"

  # The fake manager script: record args, exit 0
  cat > "${fake_mgr_dir}/wb-tools-manager-fake.py" <<FAKEEOF
#!/usr/bin/env python3
import sys, os
call_log = os.environ.get("FAKE_MGR_LOG", "/dev/null")
with open(call_log, "a") as f:
    f.write(" ".join(sys.argv[1:]) + "\n")
sys.exit(0)
FAKEEOF
  chmod +x "${fake_mgr_dir}/wb-tools-manager-fake.py"

  # Override the WB_TOOLS_DIR so _wgbe_tools_manager_bin finds our fake manager
  # wb-gui-build-env.sh resolves wb-tools-manager.py relative to its own dir (libexec/)
  # We override by placing a fake script named wb-tools-manager.py in the libexec subdir
  # alongside wb-gui-build-env.sh's resolution path.
  # Easiest: put a fake manager in the same dir as the real manager and point
  # _wgbe_tools_manager_bin using an env var trick. Since the function is hardcoded,
  # we monkey-patch _wgbe_tools_manager_bin in the test shell.

  run bash -c "
    export PATH='${FAKE_YAD_DIR}:${PATH}'
    export WB_HOME='${WB_HOME}'
    export WB_TEST_YAD_LOG='${WB_TEST_YAD_LOG}'
    export FAKE_MGR_LOG='${fake_mgr_log}'
    source '${WB_LIB}/wb-paths.sh'
    source '${WB_LIB}/wb-log.sh'
    source '${WB_LIB}/wb-json.sh'
    source '${WB_GUI_LIB}/wb-gui-dialogs.sh'
    source '${WB_GUI_LIB}/wb-gui-build-env.sh'

    # Monkey-patch _wgbe_tools_manager_bin to return our fake manager
    _wgbe_tools_manager_bin() {
      echo '${fake_mgr_dir}/wb-tools-manager-fake.py'
      return 0
    }

    # Monkey-patch _wgbe_managed_tools_dir to avoid real path resolution
    _wgbe_managed_tools_dir() {
      echo '${WB_MANAGED_TOOLS_DIR}'
    }

    # Invoke the install dispatch directly with the slug
    _slug_rc=0
    wb_gui_build_env_run_source_build 'tools-manager-install:glslang' || _slug_rc=\$?
    echo \"slug_rc=\${_slug_rc}\"
  "

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"slug_rc=0"* ]]

  # Verify the fake manager was called with 'install glslang'
  [ -f "${fake_mgr_log}" ]
  local calls
  calls="$(cat "${fake_mgr_log}")"
  [[ "${calls}" == *"install glslang"* ]] || [[ "${calls}" == *"install"*"glslang"* ]]
}

# ===========================================================================
# Case 7: rc=61 → tools-manager-check slug invokes manager's check --json
# ===========================================================================

@test "dialog rc=61 dispatches tools-manager-check slug which calls manager check --json" {
  local fake_mgr_dir="${TEST_DIR}/fake-mgr-dir-61"
  mkdir -p "${fake_mgr_dir}"
  local fake_mgr_log="${TEST_DIR}/fake-mgr-calls-61.log"

  # Fake manager: echo valid check --json output on stdout, exit 0 (no updates)
  cat > "${fake_mgr_dir}/wb-tools-manager-fake.py" <<'FAKEEOF'
#!/usr/bin/env python3
import sys, os, json

call_log = os.environ.get("FAKE_MGR_LOG", "/dev/null")
with open(call_log, "a") as f:
    f.write(" ".join(sys.argv[1:]) + "\n")

# If called with "check --json", emit a valid check response (no updates) and exit 0
args = sys.argv[1:]
if "check" in args and "--json" in args:
    result = {
        "schema_version": 1,
        "tools": {
            "glslang": {
                "installed": False,
                "version": None,
                "latest_version": "15.0.0",
                "state": "not-installed",
                "update_available": False,
                "compatible_flavor_available": True,
                "display_name": "glslang shader compiler"
            }
        }
    }
    print(json.dumps(result))
    sys.exit(0)

# Default: exit 0
sys.exit(0)
FAKEEOF
  chmod +x "${fake_mgr_dir}/wb-tools-manager-fake.py"

  run bash -c "
    export PATH='${FAKE_YAD_DIR}:${PATH}'
    export WB_HOME='${WB_HOME}'
    export WB_TEST_YAD_LOG='${WB_TEST_YAD_LOG}'
    export FAKE_MGR_LOG='${fake_mgr_log}'
    source '${WB_LIB}/wb-paths.sh'
    source '${WB_LIB}/wb-log.sh'
    source '${WB_LIB}/wb-json.sh'
    source '${WB_GUI_LIB}/wb-gui-dialogs.sh'
    source '${WB_GUI_LIB}/wb-gui-build-env.sh'

    # Monkey-patch _wgbe_tools_manager_bin to return our fake manager
    _wgbe_tools_manager_bin() {
      echo '${fake_mgr_dir}/wb-tools-manager-fake.py'
      return 0
    }

    # Invoke the check dispatch directly with the slug
    _check_out=\$(wb_gui_build_env_run_source_build 'tools-manager-check')
    _check_rc=\$?
    echo \"check_rc=\${_check_rc}\"
    echo \"check_out=\${_check_out}\"
  "

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"check_rc=0"* ]]

  # Verify the fake manager was called with 'check --json'
  [ -f "${fake_mgr_log}" ]
  local calls
  calls="$(cat "${fake_mgr_log}")"
  [[ "${calls}" == *"check"*"--json"* ]] || [[ "${calls}" == *"check --json"* ]]
}
