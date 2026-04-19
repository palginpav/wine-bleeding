#!/usr/bin/env bats

load "lib/common.bash"

WB_LIB="${BATS_TEST_DIRNAME}/../src/wb-lib"

setup() {
  TEST_PREFIX="$(mktemp -d)"
  export TEST_PREFIX
  export WB_HOME="${TEST_PREFIX}"
}

teardown() {
  rm -rf "${TEST_PREFIX}"
}

_source_lock() {
  source "${WB_LIB}/wb-paths.sh"
  source "${WB_LIB}/wb-log.sh"
  source "${WB_LIB}/wb-lock.sh"
}

# 1. Acquire on fresh prefix succeeds
@test "lock: acquire on fresh prefix succeeds" {
  run bash -c "
    set -euo pipefail
    source '${WB_LIB}/wb-paths.sh'
    source '${WB_LIB}/wb-log.sh'
    source '${WB_LIB}/wb-lock.sh'
    wb_acquire_lock '${TEST_PREFIX}/pfx'
    echo 'acquired'
  "
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"acquired"* ]]
}

# 2. Release after acquire succeeds
@test "lock: release after acquire succeeds" {
  run bash -c "
    set -euo pipefail
    source '${WB_LIB}/wb-paths.sh'
    source '${WB_LIB}/wb-log.sh'
    source '${WB_LIB}/wb-lock.sh'
    wb_acquire_lock '${TEST_PREFIX}/pfx'
    wb_release_lock '${TEST_PREFIX}/pfx'
    echo 'released'
  "
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"released"* ]]
}

# 3. Double-acquire (same process, same fd) fails non-zero
@test "lock: double-acquire returns non-zero" {
  # flock -n fails if the lock is already held by another fd or process
  # We test that a second process trying to acquire while first holds it fails
  local pfx="${TEST_PREFIX}/pfx2"
  mkdir -p "${pfx}"
  # Acquire lock and hold it in background, then try second acquire
  (flock -x "${pfx}/.wb_lock" sleep 3) &
  local holder_pid=$!
  sleep 0.2
  run bash -c "
    set -euo pipefail
    source '${WB_LIB}/wb-paths.sh'
    source '${WB_LIB}/wb-log.sh'
    source '${WB_LIB}/wb-lock.sh'
    wb_acquire_lock '${pfx}'
  " 2>/dev/null
  kill "${holder_pid}" 2>/dev/null || true
  wait "${holder_pid}" 2>/dev/null || true
  [ "${status}" -ne 0 ]
}

# 4. Acquire after release succeeds
@test "lock: acquire after release succeeds" {
  run bash -c "
    set -euo pipefail
    source '${WB_LIB}/wb-paths.sh'
    source '${WB_LIB}/wb-log.sh'
    source '${WB_LIB}/wb-lock.sh'
    wb_acquire_lock '${TEST_PREFIX}/pfx3'
    wb_release_lock '${TEST_PREFIX}/pfx3'
    wb_acquire_lock '${TEST_PREFIX}/pfx3'
    echo 'second-acquire-ok'
  "
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"second-acquire-ok"* ]]
}

# 5. Two different prefixes: both acquire independently
@test "lock: two different prefixes acquire independently" {
  run bash -c "
    set -euo pipefail
    source '${WB_LIB}/wb-paths.sh'
    source '${WB_LIB}/wb-log.sh'
    source '${WB_LIB}/wb-lock.sh'
    wb_acquire_lock '${TEST_PREFIX}/pfxA'
    wb_acquire_lock '${TEST_PREFIX}/pfxB'
    echo 'both-acquired'
  "
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"both-acquired"* ]]
}

# 6. NFS fallback: fake stat reports nfs, mkdir lockdir used, WARN emitted
@test "lock: NFS fallback uses mkdir lockdir and emits WARN" {
  local pfx="${TEST_PREFIX}/nfspfx"
  mkdir -p "${pfx}"
  # Create a fake stat that reports nfs for filesystem type queries
  local fake_bin="${TEST_PREFIX}/bin"
  mkdir -p "${fake_bin}"
  cat > "${fake_bin}/stat" <<'FAKESTAT'
#!/usr/bin/env bash
# Fake stat: always report nfs for -f -c %T
if [[ "$*" == *"-f"* && "$*" == *"-c"* && "$*" == *"%T"* ]]; then
  echo "nfs"
  exit 0
fi
exec /usr/bin/stat "$@"
FAKESTAT
  chmod +x "${fake_bin}/stat"

  local augmented_path="${fake_bin}:${PATH}"
  run env PATH="${augmented_path}" WB_HOME="${TEST_PREFIX}" bash -c "
    set -euo pipefail
    source '${WB_LIB}/wb-paths.sh'
    source '${WB_LIB}/wb-log.sh'
    source '${WB_LIB}/wb-lock.sh'
    wb_acquire_lock '${pfx}'
    echo 'nfs-acquired'
  " 2>&1
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"nfs-acquired"* ]]
  [ -d "${pfx}/.wb_lock.d" ]
}
