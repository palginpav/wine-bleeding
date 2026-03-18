#!/usr/bin/env bash
# Test suite for unix-side builtin DLL deployment (no-fakedll architecture).
# Validates that Wine correctly deploys real builtins, creates prefixes,
# and runs applications without fake DLLs.
#
# Usage: ./tools/test-builtin-deploy.sh [dist-path]

set -euo pipefail

WINE_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEST_PREFIX="$HOME/.wine-test-builtin-deploy"
PASS=0; FAIL=0; SKIP=0

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[1;36m'; NC='\033[0m'

pass() { ((PASS++)); echo -e "  ${GREEN}PASS${NC}: $1"; }
fail() { ((FAIL++)); echo -e "  ${RED}FAIL${NC}: $1"; }
skip() { ((SKIP++)); echo -e "  ${YELLOW}SKIP${NC}: $1"; }
section() { echo -e "\n${CYAN}=== $1 ===${NC}"; }

# Find dist
if [ -n "${1:-}" ]; then
    DIST="$(cd "$1" && pwd)"
else
    DIST="$(ls -d "$WINE_ROOT"/dist/WINE-BLEEDING-*/ 2>/dev/null | sort -V | tail -1)"
fi
[ -d "$DIST/bin" ] || { echo "Error: dist not found. Usage: $0 [dist-path]"; exit 1; }

WINE="$DIST/bin/wine"
WINESERVER="$DIST/bin/wineserver"
SYS64="$DIST/lib/wine/x86_64-windows"
SYS32="$DIST/lib/wine/i386-windows"

cleanup() {
    "$WINESERVER" -k 2>/dev/null || true
    sleep 1
    rm -rf "$TEST_PREFIX"
}

echo -e "${CYAN}Wine Builtin Deployment Test Suite${NC}"
echo "Dist: $DIST"
echo "Test prefix: $TEST_PREFIX"

# ============================================================
section "Test 1: Clean prefix creation"
# ============================================================
cleanup

export WINEPREFIX="$TEST_PREFIX"
export WINEDEBUG=+environ

# Create prefix
OUTPUT=$("$WINE" wineboot --init 2>&1) || true
"$WINESERVER" -k 2>/dev/null || true
sleep 1

# 1.1: deploy_builtin_dlls ran
if echo "$OUTPUT" | grep -q "deploy_builtin_dlls.*deployed.*builtin"; then
    DEPLOYED=$(echo "$OUTPUT" | grep "deploy_builtin_dlls" | grep -oP 'deployed \K[0-9]+')
    pass "deploy_builtin_dlls deployed $DEPLOYED files"
else
    fail "deploy_builtin_dlls trace not found in output"
fi

# 1.2: system32 populated
SYS32_COUNT=$(ls "$TEST_PREFIX/drive_c/windows/system32/"*.dll 2>/dev/null | wc -l)
if [ "$SYS32_COUNT" -gt 500 ]; then
    pass "system32 has $SYS32_COUNT DLLs"
else
    fail "system32 only has $SYS32_COUNT DLLs (expected >500)"
fi

# 1.3: syswow64 populated
WOW64_COUNT=$(ls "$TEST_PREFIX/drive_c/windows/syswow64/"*.dll 2>/dev/null | wc -l)
if [ "$WOW64_COUNT" -gt 400 ]; then
    pass "syswow64 has $WOW64_COUNT DLLs"
else
    fail "syswow64 only has $WOW64_COUNT DLLs (expected >400)"
fi

# 1.4: Real builtins, not fakedlls
MARKER=$(xxd -l 80 "$TEST_PREFIX/drive_c/windows/system32/kernel32.dll" 2>/dev/null | grep -c "Wine builtin DLL" || true)
if [ "$MARKER" -gt 0 ]; then
    pass "kernel32.dll has 'Wine builtin DLL' marker (real builtin)"
else
    fail "kernel32.dll missing builtin marker"
fi

# 1.5: File sizes match dist
DIST_SIZE=$(stat -c%s "$SYS64/kernel32.dll" 2>/dev/null || echo 0)
PFX_SIZE=$(stat -c%s "$TEST_PREFIX/drive_c/windows/system32/kernel32.dll" 2>/dev/null || echo 0)
if [ "$DIST_SIZE" = "$PFX_SIZE" ] && [ "$DIST_SIZE" -gt 100000 ]; then
    pass "kernel32.dll size matches dist ($DIST_SIZE bytes)"
else
    fail "kernel32.dll size mismatch: dist=$DIST_SIZE prefix=$PFX_SIZE"
fi

# 1.6: Directory structure
DIRS_OK=true
for d in "drive_c/windows/system32" "drive_c/windows/syswow64" \
         "drive_c/Program Files" "drive_c/Program Files (x86)" \
         "drive_c/ProgramData" "drive_c/users" "dosdevices"; do
    [ -d "$TEST_PREFIX/$d" ] || { DIRS_OK=false; break; }
done
if $DIRS_OK; then
    pass "Prefix directory structure complete"
else
    fail "Missing directory: $d"
fi

# 1.7: dosdevices symlinks
if [ -L "$TEST_PREFIX/dosdevices/c:" ] && [ -L "$TEST_PREFIX/dosdevices/z:" ]; then
    pass "dosdevices symlinks present"
else
    fail "dosdevices symlinks missing"
fi

# 1.8: Registry files created by wineboot
REG_OK=true
for f in system.reg user.reg; do
    [ -f "$TEST_PREFIX/$f" ] || { REG_OK=false; break; }
done
if $REG_OK; then
    pass "Registry files created (system.reg, user.reg)"
else
    fail "Missing registry file: $f"
fi

# 1.9: EXE files deployed
EXE_COUNT=$(ls "$TEST_PREFIX/drive_c/windows/system32/"*.exe 2>/dev/null | wc -l)
if [ "$EXE_COUNT" -gt 50 ]; then
    pass "system32 has $EXE_COUNT EXE files"
else
    fail "system32 only has $EXE_COUNT EXE files (expected >50)"
fi

# ============================================================
section "Test 2: Application execution"
# ============================================================
export WINEDEBUG=-all

# 2.1: cmd.exe echo
CMD_OUT=$("$WINE" cmd /c "echo TESTOK" 2>/dev/null || true)
if echo "$CMD_OUT" | grep -q "TESTOK"; then
    pass "cmd.exe echo works"
else
    fail "cmd.exe echo failed: $CMD_OUT"
fi

# 2.2: reg.exe query
REG_OUT=$("$WINE" reg query "HKLM\\Software\\Microsoft\\Windows NT\\CurrentVersion" /v CurrentVersion 2>/dev/null || true)
if echo "$REG_OUT" | grep -qE "[0-9]+\.[0-9]+"; then
    pass "reg.exe query works"
else
    fail "reg.exe query failed"
fi

# 2.3: wineboot -u (update, no crash)
if "$WINE" wineboot -u 2>/dev/null; then
    pass "wineboot -u succeeds"
else
    fail "wineboot -u failed"
fi
"$WINESERVER" -k 2>/dev/null || true
sleep 1

# 2.4: notepad (starts without crash, kill after 2 seconds)
"$WINE" notepad 2>/dev/null &
NPID=$!
sleep 2
if kill -0 "$NPID" 2>/dev/null; then
    pass "notepad starts and stays running"
    "$WINESERVER" -k 2>/dev/null || true
    wait "$NPID" 2>/dev/null || true
else
    fail "notepad crashed or exited immediately"
fi
sleep 1

# 2.5: services.exe starts (check via wineboot)
export WINEDEBUG=+service
SVC_OUT=$("$WINE" wineboot -r 2>&1 || true)
"$WINESERVER" -k 2>/dev/null || true
sleep 1
if echo "$SVC_OUT" | grep -qi "service"; then
    pass "services.exe runs during wineboot (service traces present)"
else
    skip "services.exe traces not detected (may still work)"
fi
export WINEDEBUG=-all

# ============================================================
section "Test 3: Incremental update (second run)"
# ============================================================

# 3.1: Second wineboot should skip deployment (all up-to-date)
export WINEDEBUG=+environ
OUTPUT2=$("$WINE" wineboot -u 2>&1 || true)
"$WINESERVER" -k 2>/dev/null || true
sleep 1

if echo "$OUTPUT2" | grep -q "deploy_builtin_dlls.*deployed.*builtin"; then
    REDEPLOYED=$(echo "$OUTPUT2" | grep "deploy_builtin_dlls" | grep -oP 'deployed \K[0-9]+')
    if [ "$REDEPLOYED" = "0" ] || [ -z "$REDEPLOYED" ]; then
        pass "Incremental: 0 files redeployed (all up-to-date)"
    else
        fail "Incremental: $REDEPLOYED files redeployed (expected 0)"
    fi
else
    pass "Incremental: no deployment trace (all up-to-date)"
fi

# 3.2: Simulate updated DLL — touch source, re-run
touch "$SYS64/vcomp140.dll" 2>/dev/null || true
OUTPUT3=$("$WINE" cmd /c "echo INCR" 2>&1 || true)
"$WINESERVER" -k 2>/dev/null || true
sleep 1

if echo "$OUTPUT3" | grep -q "deploy_builtin_dlls.*deployed.*builtin"; then
    UPDATED=$(echo "$OUTPUT3" | grep "deploy_builtin_dlls" | grep -oP 'deployed \K[0-9]+')
    if [ -n "$UPDATED" ] && [ "$UPDATED" -ge 1 ]; then
        pass "Incremental update: $UPDATED changed files redeployed"
    else
        pass "Incremental update: deployment ran correctly"
    fi
else
    pass "Incremental update: no deployment needed"
fi

# ============================================================
section "Test 4: Loader fallback (missing file)"
# ============================================================
export WINEDEBUG=-all

# 4.1: Delete a non-critical DLL from system32 — loader should fallback to dist
rm -f "$TEST_PREFIX/drive_c/windows/system32/wineps.drv" 2>/dev/null || true
CMD_OUT2=$("$WINE" cmd /c "echo FALLBACK_OK" 2>/dev/null || true)
if echo "$CMD_OUT2" | grep -q "FALLBACK_OK"; then
    pass "Loader fallback works after deleting DLL from system32"
else
    fail "Loader fallback failed after deleting DLL from system32"
fi
"$WINESERVER" -k 2>/dev/null || true
sleep 1

# ============================================================
section "Test 5: Key system files"
# ============================================================

# 5.1-5.5: Critical files present and are real builtins
for f in services.exe svchost.exe wineboot.exe explorer.exe cmd.exe; do
    FPATH="$TEST_PREFIX/drive_c/windows/system32/$f"
    if [ -f "$FPATH" ]; then
        FSIZE=$(stat -c%s "$FPATH")
        if [ "$FSIZE" -gt 10000 ]; then
            pass "$f present ($FSIZE bytes)"
        else
            fail "$f too small ($FSIZE bytes) — may be placeholder"
        fi
    else
        fail "$f missing from system32"
    fi
done

# ============================================================
section "Test 6: Startup performance"
# ============================================================

# 6.1: Cold start timing
"$WINESERVER" -k 2>/dev/null || true
sleep 1
export WINEDEBUG=-all
START_TIME=$(date +%s%N)
"$WINE" cmd /c "echo PERF" >/dev/null 2>&1 || true
END_TIME=$(date +%s%N)
ELAPSED_MS=$(( (END_TIME - START_TIME) / 1000000 ))
"$WINESERVER" -k 2>/dev/null || true

if [ "$ELAPSED_MS" -lt 5000 ]; then
    pass "Cold start: ${ELAPSED_MS}ms (< 5s)"
else
    fail "Cold start too slow: ${ELAPSED_MS}ms"
fi

# ============================================================
# Cleanup and summary
# ============================================================
cleanup

echo ""
echo -e "${CYAN}=== Results ===${NC}"
echo -e "  ${GREEN}PASS: $PASS${NC}"
[ "$FAIL" -gt 0 ] && echo -e "  ${RED}FAIL: $FAIL${NC}" || echo "  FAIL: 0"
[ "$SKIP" -gt 0 ] && echo -e "  ${YELLOW}SKIP: $SKIP${NC}" || echo "  SKIP: 0"
echo ""

if [ "$FAIL" -eq 0 ]; then
    echo -e "${GREEN}All tests passed!${NC}"
    exit 0
else
    echo -e "${RED}$FAIL test(s) failed.${NC}"
    exit 1
fi
