#!/usr/bin/env bats

load "lib/common.bash"

WB="${BATS_TEST_DIRNAME}/../src/wb"

@test "wb --version prints wb <VERSION> matching runtime/VERSION" {
  local expected
  expected="$(tr -d '[:space:]' < "${BATS_TEST_DIRNAME}/../VERSION")"
  run "${WB}" --version
  [ "${status}" -eq 0 ]
  [ "${output}" = "wb ${expected}" ]
}

@test "wb help exits 0 and prints a non-empty line" {
  run "${WB}" help
  [ "${status}" -eq 0 ]
  [ -n "${output}" ]
}

@test "wb nonexistent-subcommand exits non-zero" {
  run "${WB}" nonexistent-subcommand
  [ "${status}" -ne 0 ]
}

# ===========================================================================
# _wb_validate_path_arg: Unicode-path acceptance regression
# Absolute paths with Cyrillic / CJK / accented Latin must NOT be rejected
# (real users have locale-named directories like ~/Загрузки/, ~/桌面/,
# ~/Téléchargements/). Shell metacharacters, path traversal, and quote-likes
# stay rejected. Relative names (single-segment slugs like prefix names)
# remain ASCII-strict because they're project-internal identifiers.
# ===========================================================================
@test "wb _wb_validate_path_arg accepts Unicode absolute paths" {
  # NOTE: _wb_validate_path_arg uses 'exit 1' on rejection (correct production
  # semantics — wb top-level command). For tests we run each call in its own
  # subshell '( ... )' so 'exit' just terminates the subshell and we can
  # inspect $?.
  run bash -c "
    eval \"\$(awk '/^_wb_validate_path_arg\(\)/,/^}\$/' '${WB}')\"
    ( _wb_validate_path_arg test '/home/palgin/Загрузки/setup.exe' ) 2>/dev/null || exit 11
    ( _wb_validate_path_arg test '/home/u/桌面/installer.exe'        ) 2>/dev/null || exit 12
    ( _wb_validate_path_arg test '/home/u/Téléchargements/x.exe'   ) 2>/dev/null || exit 13
    ( _wb_validate_path_arg test '/home/u/My Apps/Setup.exe'       ) 2>/dev/null || exit 14
    ( _wb_validate_path_arg test 'myprefix'                        ) 2>/dev/null || exit 15

    # Reject — must fail (subshell exits non-zero)
    if ( _wb_validate_path_arg test '/home/u/../etc/passwd' ) 2>/dev/null; then exit 21; fi
    if ( _wb_validate_path_arg test '/path/\$evil.exe'      ) 2>/dev/null; then exit 22; fi
    if ( _wb_validate_path_arg test '/path;rm.exe'          ) 2>/dev/null; then exit 23; fi
    if ( _wb_validate_path_arg test 'myпрефикс'             ) 2>/dev/null; then exit 24; fi
  "
  if [ "${status}" -ne 0 ]; then
    printf 'rc=%s\nout=%s\n' "${status}" "${output}" >&2
  fi
  [ "${status}" -eq 0 ]
}
