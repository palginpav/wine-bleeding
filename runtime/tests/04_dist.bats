#!/usr/bin/env bats

load "lib/common.bash"

WB="${BATS_TEST_DIRNAME}/../src/wb"
WB_LIB="${BATS_TEST_DIRNAME}/../src/wb-lib"
FIXTURE_DIST="${BATS_TEST_DIRNAME}/fixtures/fake-dist"
SCHEMA_FILE="${BATS_TEST_DIRNAME}/../share/schemas/wb_dist_meta.schema.json"

setup() {
  TEST_HOME="$(mktemp -d)"
  export TEST_HOME
  export WB_HOME="${TEST_HOME}"
  mkdir -p "${WB_HOME}/dist"
}

teardown() {
  rm -rf "${TEST_HOME}"
}

_source_dist() {
  source "${WB_LIB}/wb-paths.sh"
  source "${WB_LIB}/wb-log.sh"
  source "${WB_LIB}/wb-json.sh"
  source "${WB_LIB}/wb-dist.sh"
}

_make_dist() {
  local name="$1"
  local dist_path="${WB_HOME}/dist/${name}"
  cp -a "${FIXTURE_DIST}/." "${dist_path}"
  echo "${dist_path}"
}

# 1. wb_dist_list on empty tree → empty output, exit 0
@test "dist_list: empty dist dir returns empty output and exits 0" {
  run bash -c "
    source '${WB_LIB}/wb-paths.sh'
    source '${WB_LIB}/wb-log.sh'
    source '${WB_LIB}/wb-json.sh'
    source '${WB_LIB}/wb-dist.sh'
    wb_dist_list
  " WB_HOME="${WB_HOME}" 2>/dev/null
  [ "${status}" -eq 0 ]
  [ -z "${output}" ]
}

# 2. wb_dist_list with 2 dists and 1 alias → only 2 real dists (alias excluded)
@test "dist_list: excludes WINE-BLEEDING alias symlink, emits only real dirs" {
  _make_dist "WINE-BLEEDING-01012026" >/dev/null
  _make_dist "WINE-BLEEDING-15012026" >/dev/null
  ln -sfn "${WB_HOME}/dist/WINE-BLEEDING-15012026" "${WB_HOME}/dist/WINE-BLEEDING"

  run bash -c "
    source '${WB_LIB}/wb-paths.sh'
    source '${WB_LIB}/wb-log.sh'
    source '${WB_LIB}/wb-json.sh'
    source '${WB_LIB}/wb-dist.sh'
    wb_dist_list
  " WB_HOME="${WB_HOME}" 2>/dev/null
  [ "${status}" -eq 0 ]
  [ "$(echo "${output}" | wc -l)" -eq 2 ]
  echo "${output}" | grep -q "WINE-BLEEDING-01012026"
  echo "${output}" | grep -q "WINE-BLEEDING-15012026"
  ! echo "${output}" | grep -qx "WINE-BLEEDING"
}

# 3. wb_dist_resolve_alias with alias present → correct target
@test "dist_resolve_alias: returns absolute path to alias target" {
  _make_dist "WINE-BLEEDING-01012026" >/dev/null
  ln -sfn "${WB_HOME}/dist/WINE-BLEEDING-01012026" "${WB_HOME}/dist/WINE-BLEEDING"

  run bash -c "
    source '${WB_LIB}/wb-paths.sh'
    source '${WB_LIB}/wb-log.sh'
    source '${WB_LIB}/wb-json.sh'
    source '${WB_LIB}/wb-dist.sh'
    wb_dist_resolve_alias
  " WB_HOME="${WB_HOME}" 2>/dev/null
  [ "${status}" -eq 0 ]
  [ "${output}" = "${WB_HOME}/dist/WINE-BLEEDING-01012026" ]
}

# 4. wb_dist_resolve_alias with alias absent → empty output, exit 0
@test "dist_resolve_alias: no alias returns empty and exit 0" {
  run bash -c "
    source '${WB_LIB}/wb-paths.sh'
    source '${WB_LIB}/wb-log.sh'
    source '${WB_LIB}/wb-json.sh'
    source '${WB_LIB}/wb-dist.sh'
    wb_dist_resolve_alias
  " WB_HOME="${WB_HOME}" 2>/dev/null
  [ "${status}" -eq 0 ]
  [ -z "${output}" ]
}

# 5. wb_dist_meta_write on fake-dist fixture creates valid JSON
@test "dist_meta_write: creates valid JSON manifest" {
  local dist_path
  dist_path="$(_make_dist "WINE-BLEEDING-18042026")"

  run bash -c "
    source '${WB_LIB}/wb-paths.sh'
    source '${WB_LIB}/wb-log.sh'
    source '${WB_LIB}/wb-json.sh'
    source '${WB_LIB}/wb-dist.sh'
    wb_dist_meta_write '${dist_path}'
  " WB_HOME="${WB_HOME}" 2>/dev/null
  [ "${status}" -eq 0 ]
  [ -f "${dist_path}/.wb_dist_meta" ]
  run jq empty "${dist_path}/.wb_dist_meta"
  [ "${status}" -eq 0 ]
}

# 6. wb_dist_meta_read reads each required key
@test "dist_meta_read: reads required keys from manifest" {
  local dist_path
  dist_path="$(_make_dist "WINE-BLEEDING-18042026")"

  bash -c "
    source '${WB_LIB}/wb-paths.sh'
    source '${WB_LIB}/wb-log.sh'
    source '${WB_LIB}/wb-json.sh'
    source '${WB_LIB}/wb-dist.sh'
    wb_dist_meta_write '${dist_path}'
  " WB_HOME="${WB_HOME}" 2>/dev/null

  run bash -c "
    source '${WB_LIB}/wb-paths.sh'
    source '${WB_LIB}/wb-log.sh'
    source '${WB_LIB}/wb-json.sh'
    source '${WB_LIB}/wb-dist.sh'
    wb_dist_meta_read '${dist_path}' '.dist_name'
  " WB_HOME="${WB_HOME}" 2>/dev/null
  [ "${status}" -eq 0 ]
  [ "${output}" = "WINE-BLEEDING-18042026" ]

  run bash -c "
    source '${WB_LIB}/wb-paths.sh'
    source '${WB_LIB}/wb-log.sh'
    source '${WB_LIB}/wb-json.sh'
    source '${WB_LIB}/wb-dist.sh'
    wb_dist_meta_read '${dist_path}' '.wine_full_version'
  " WB_HOME="${WB_HOME}" 2>/dev/null
  [ "${status}" -eq 0 ]
  [ "${output}" = "wine-11.4" ]

  run bash -c "
    source '${WB_LIB}/wb-paths.sh'
    source '${WB_LIB}/wb-log.sh'
    source '${WB_LIB}/wb-json.sh'
    source '${WB_LIB}/wb-dist.sh'
    wb_dist_meta_read '${dist_path}' '.components.dxvk.version'
  " WB_HOME="${WB_HOME}" 2>/dev/null
  [ "${status}" -eq 0 ]
  [ "${output}" = "2.7.1-509" ]
}

# 7. wb_dist_set_alias atomic swap: concurrent reads never see ENOENT
@test "dist_set_alias: concurrent reads never see missing symlink during swap" {
  _make_dist "WINE-BLEEDING-A" >/dev/null
  _make_dist "WINE-BLEEDING-B" >/dev/null
  ln -sfn "${WB_HOME}/dist/WINE-BLEEDING-A" "${WB_HOME}/dist/WINE-BLEEDING"

  local errors_file="${TEST_HOME}/enoent_errors"
  touch "${errors_file}"

  # Background reader: loop reading the symlink, record any failures
  bash -c "
    for i in \$(seq 1 200); do
      target=\"\$(readlink '${WB_HOME}/dist/WINE-BLEEDING' 2>&1)\"
      if [ \$? -ne 0 ]; then
        echo \"ENOENT at iteration \${i}: \${target}\" >> '${errors_file}'
      fi
    done
  " &
  local reader_pid=$!

  # Foreground: perform many swaps
  local i
  for (( i=0; i<20; i++ )); do
    bash -c "
      source '${WB_LIB}/wb-paths.sh'
      source '${WB_LIB}/wb-log.sh'
      source '${WB_LIB}/wb-json.sh'
      source '${WB_LIB}/wb-dist.sh'
      wb_dist_set_alias '${WB_HOME}/dist/WINE-BLEEDING-A'
      wb_dist_set_alias '${WB_HOME}/dist/WINE-BLEEDING-B'
    " WB_HOME="${WB_HOME}" 2>/dev/null
  done

  wait "${reader_pid}" 2>/dev/null || true
  local error_count
  error_count="$(wc -l < "${errors_file}")"
  [ "${error_count}" -eq 0 ]
}

# 8. wb_dist_set_alias: sync -f runs (dir mtime advances after sync)
@test "dist_set_alias: sync completes without error" {
  _make_dist "WINE-BLEEDING-18042026" >/dev/null

  run bash -c "
    source '${WB_LIB}/wb-paths.sh'
    source '${WB_LIB}/wb-log.sh'
    source '${WB_LIB}/wb-json.sh'
    source '${WB_LIB}/wb-dist.sh'
    wb_dist_set_alias '${WB_HOME}/dist/WINE-BLEEDING-18042026'
  " WB_HOME="${WB_HOME}" 2>/dev/null
  [ "${status}" -eq 0 ]
  [ -L "${WB_HOME}/dist/WINE-BLEEDING" ]
}

# 9. wb runtime list: tabular output has correct columns
@test "wb runtime list: tabular output has NAME ACTIVE SIZE BUILD_DATE columns" {
  _make_dist "WINE-BLEEDING-18042026" >/dev/null
  bash -c "
    source '${WB_LIB}/wb-paths.sh'
    source '${WB_LIB}/wb-log.sh'
    source '${WB_LIB}/wb-json.sh'
    source '${WB_LIB}/wb-dist.sh'
    wb_dist_meta_write '${WB_HOME}/dist/WINE-BLEEDING-18042026'
  " WB_HOME="${WB_HOME}" 2>/dev/null

  run bash -c "WB_HOME='${WB_HOME}' '${WB}' runtime list" 2>/dev/null
  [ "${status}" -eq 0 ]
  echo "${output}" | grep -q "NAME"
  echo "${output}" | grep -q "WINE-BLEEDING-18042026"
}

# 10. wb runtime info <NAME>: prints valid JSON
@test "wb runtime info: prints valid JSON for a known dist" {
  local dist_path
  dist_path="$(_make_dist "WINE-BLEEDING-18042026")"
  bash -c "
    source '${WB_LIB}/wb-paths.sh'
    source '${WB_LIB}/wb-log.sh'
    source '${WB_LIB}/wb-json.sh'
    source '${WB_LIB}/wb-dist.sh'
    wb_dist_meta_write '${dist_path}'
  " WB_HOME="${WB_HOME}" 2>/dev/null

  run bash -c "WB_HOME='${WB_HOME}' '${WB}' runtime info WINE-BLEEDING-18042026" 2>/dev/null
  [ "${status}" -eq 0 ]
  echo "${output}" | jq -e '.dist_name == "WINE-BLEEDING-18042026"'
}

# 11. wb runtime install <fake-tarball>: succeeds, .wb_dist_meta present
@test "wb runtime install: extracts tarball and writes .wb_dist_meta" {
  local tarball="${TEST_HOME}/WINE-BLEEDING-18042026.tar.gz"
  local staging="${TEST_HOME}/staging/WINE-BLEEDING-18042026"
  mkdir -p "${staging}"
  cp -a "${FIXTURE_DIST}/." "${staging}"
  tar -czf "${tarball}" -C "${TEST_HOME}/staging" "WINE-BLEEDING-18042026"

  run bash -c "WB_HOME='${WB_HOME}' '${WB}' runtime install '${tarball}'" 2>/dev/null
  [ "${status}" -eq 0 ]
  [ -d "${WB_HOME}/dist/WINE-BLEEDING-18042026" ]
  [ -f "${WB_HOME}/dist/WINE-BLEEDING-18042026/.wb_dist_meta" ]
  jq empty "${WB_HOME}/dist/WINE-BLEEDING-18042026/.wb_dist_meta"
}

# 12. wb runtime install REJECTS tarball with absolute-path entry
@test "wb runtime install: rejects tarball with absolute path entry" {
  local tarball="${TEST_HOME}/bad-abs.tar.gz"
  local staging="${TEST_HOME}/staging_abs"
  mkdir -p "${staging}"
  echo "malicious" > "${staging}/passwd"
  # Create tarball with an absolute-path entry using --transform
  tar -czf "${tarball}" -C "${staging}" --transform 's|^passwd|/etc/passwd|' "passwd" 2>/dev/null || \
    tar -P -czf "${tarball}" -C / etc/passwd 2>/dev/null || true

  run bash -c "WB_HOME='${WB_HOME}' '${WB}' runtime install '${tarball}'" 2>/dev/null
  [ "${status}" -ne 0 ]
  echo "${output}${stderr:-}" | grep -qi "REJECTED\|absolute\|rejected"
}

# 13. wb runtime install REJECTS tarball with .. path traversal
@test "wb runtime install: rejects tarball with path traversal (..) entry" {
  local tarball="${TEST_HOME}/bad-traversal.tar.gz"
  local staging="${TEST_HOME}/staging_traversal/WINE-BLEEDING-18042026"
  mkdir -p "${staging}"
  echo "evil" > "${staging}/safe.txt"
  tar -czf "${tarball}" -C "${TEST_HOME}/staging_traversal" \
    --transform 's|WINE-BLEEDING-18042026/safe.txt|WINE-BLEEDING-18042026/../../../evil.txt|' \
    "WINE-BLEEDING-18042026/safe.txt" 2>/dev/null || true

  run bash -c "WB_HOME='${WB_HOME}' '${WB}' runtime install '${tarball}'" 2>/dev/null
  [ "${status}" -ne 0 ]
}

# 14. wb runtime install REJECTS tarball with absolute symlink
@test "wb runtime install: rejects tarball with absolute symlink" {
  local tarball="${TEST_HOME}/bad-abslink.tar.gz"
  local staging="${TEST_HOME}/staging_abslink/WINE-BLEEDING-18042026"
  mkdir -p "${staging}"
  # Archive the symlink itself, not its target (no -h).
  ln -s /etc/passwd "${staging}/evil_link"
  tar -czf "${tarball}" -C "${TEST_HOME}/staging_abslink" "WINE-BLEEDING-18042026"

  run bash -c "WB_HOME='${WB_HOME}' '${WB}' runtime install '${tarball}'" 2>/dev/null
  [ "${status}" -ne 0 ]
}

# 14b. wb runtime install REJECTS tarball with relative-escape symlink (..)
@test "wb runtime install: rejects tarball with relative-escape symlink" {
  local tarball="${TEST_HOME}/bad-escape.tar.gz"
  local staging="${TEST_HOME}/staging_escape/WINE-BLEEDING-18042026"
  mkdir -p "${staging}"
  ln -s ../../outside_target "${staging}/escape_link"
  tar -czf "${tarball}" -C "${TEST_HOME}/staging_escape" "WINE-BLEEDING-18042026"

  run bash -c "WB_HOME='${WB_HOME}' '${WB}' runtime install '${tarball}'" 2>/dev/null
  [ "${status}" -ne 0 ]
}

# 15. wb runtime install REJECTS tarball producing multiple top-level dirs
@test "wb runtime install: rejects tarball with multiple top-level directories" {
  local tarball="${TEST_HOME}/bad-multitop.tar.gz"
  local staging="${TEST_HOME}/staging_multi"
  mkdir -p "${staging}/WINE-BLEEDING-18042026" "${staging}/other-dir"
  echo "a" > "${staging}/WINE-BLEEDING-18042026/file.txt"
  echo "b" > "${staging}/other-dir/file.txt"
  tar -czf "${tarball}" -C "${staging}" "WINE-BLEEDING-18042026" "other-dir"

  run bash -c "WB_HOME='${WB_HOME}' '${WB}' runtime install '${tarball}'" 2>/dev/null
  [ "${status}" -ne 0 ]
  echo "${output}${stderr:-}" | grep -qi "REJECTED\|multiple\|rejected"
}

# 16. wb runtime activate <NAME> re-points alias, readlink returns new target
@test "wb runtime activate: re-points alias to specified dist" {
  _make_dist "WINE-BLEEDING-A" >/dev/null
  _make_dist "WINE-BLEEDING-B" >/dev/null
  ln -sfn "${WB_HOME}/dist/WINE-BLEEDING-A" "${WB_HOME}/dist/WINE-BLEEDING"

  run bash -c "WB_HOME='${WB_HOME}' '${WB}' runtime activate WINE-BLEEDING-B" 2>/dev/null
  [ "${status}" -eq 0 ]

  local target
  target="$(readlink -f "${WB_HOME}/dist/WINE-BLEEDING")"
  [ "${target}" = "${WB_HOME}/dist/WINE-BLEEDING-B" ]
}

# 17. wb runtime prune --keep 2 --yes: leaves 2 newest, never deletes alias target
@test "wb runtime prune: keeps newest N dists, never deletes alias target" {
  local d
  for d in "WINE-BLEEDING-01012026" "WINE-BLEEDING-02012026" "WINE-BLEEDING-03012026" "WINE-BLEEDING-04012026"; do
    _make_dist "${d}" >/dev/null
    bash -c "
      source '${WB_LIB}/wb-paths.sh'
      source '${WB_LIB}/wb-log.sh'
      source '${WB_LIB}/wb-json.sh'
      source '${WB_LIB}/wb-dist.sh'
      wb_dist_meta_write '${WB_HOME}/dist/${d}'
    " WB_HOME="${WB_HOME}" 2>/dev/null
    sleep 1
  done

  # Alias points to oldest — must survive prune
  ln -sfn "${WB_HOME}/dist/WINE-BLEEDING-01012026" "${WB_HOME}/dist/WINE-BLEEDING"

  run bash -c "WB_HOME='${WB_HOME}' '${WB}' runtime prune --keep 2 --yes" 2>/dev/null
  [ "${status}" -eq 0 ]

  # Alias target must still exist
  [ -d "${WB_HOME}/dist/WINE-BLEEDING-01012026" ]
  # Newest 2 non-alias dists must survive: 04 and 03
  [ -d "${WB_HOME}/dist/WINE-BLEEDING-04012026" ]
  [ -d "${WB_HOME}/dist/WINE-BLEEDING-03012026" ]
}

# 18. Schema validation: generated .wb_dist_meta passes check-jsonschema
@test "schema: generated .wb_dist_meta passes check-jsonschema" {
  if ! command -v check-jsonschema >/dev/null 2>&1; then
    skip "check-jsonschema not available"
  fi

  local dist_path
  dist_path="$(_make_dist "WINE-BLEEDING-18042026")"
  bash -c "
    source '${WB_LIB}/wb-paths.sh'
    source '${WB_LIB}/wb-log.sh'
    source '${WB_LIB}/wb-json.sh'
    source '${WB_LIB}/wb-dist.sh'
    wb_dist_meta_write '${dist_path}'
  " WB_HOME="${WB_HOME}" 2>/dev/null

  run check-jsonschema --schemafile "${SCHEMA_FILE}" "${dist_path}/.wb_dist_meta"
  [ "${status}" -eq 0 ]
}
