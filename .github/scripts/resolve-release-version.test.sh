#!/usr/bin/env bash
# Tests for resolve-release-version.sh. Run: bash .github/scripts/resolve-release-version.test.sh
set -u

SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/resolve-release-version.sh"
OFFSET=100000
failures=0
passes=0

# assert_resolves <name> <pubspec_version> <run_number> <tags (newline-separated)> <expected_name> <expected_code>
assert_resolves() {
  local name="$1" pubspec="$2" run="$3" tags="$4" want_name="$5" want_code="$6"
  local want actual
  want=$(printf 'version_name=%s\nversion_code=%s\ntag=v%s' "$want_name" "$want_code" "$want_name")
  actual=$(printf '%s' "$tags" | bash "$SCRIPT" "$pubspec" "$OFFSET" "$run" 2>&1)
  if [[ "$actual" == "$want" ]]; then
    passes=$((passes + 1))
  else
    failures=$((failures + 1))
    printf 'FAIL %s\n  expected:\n%s\n  actual:\n%s\n' "$name" "$want" "$actual"
  fi
}

# assert_fails <name> <pubspec_version>
assert_fails() {
  local name="$1" pubspec="$2"
  if printf '' | bash "$SCRIPT" "$pubspec" "$OFFSET" 1 >/dev/null 2>&1; then
    failures=$((failures + 1))
    printf 'FAIL %s\n  expected a non-zero exit for %s\n' "$name" "$pubspec"
  else
    passes=$((passes + 1))
  fi
}

assert_resolves no_tags_keeps_pubspec_name '1.10.0+100165' 70 '' 1.10.0 100166
assert_resolves bumps_past_legacy_tag '1.10.0+100165' 70 'v1.10.0+100165' 1.10.1 100166
assert_resolves bumps_past_mixed_tag_styles '1.10.0+100165' 70 $'v1.10.0\nv1.10.1+100170\nv1.10.2' 1.10.3 100171
assert_resolves run_number_baseline_wins '1.10.0+100165' 300 '' 1.10.0 100300
assert_resolves legacy_tag_code_wins '1.10.0+100165' 70 'v1.9.0+100170' 1.10.0 100171
assert_resolves taken_name_matching_is_exact '1.10.0+100165' 70 $'v11.10.0\nv1.10.0-beta\nv1x10x0' 1.10.0 100166
assert_resolves pubspec_without_build_number '1.10.0' 5 '' 1.10.0 100005
many_tags=$(printf 'v1.10.0\n'; for i in $(seq 1 20000); do printf 'v0.0.%d\n' "$i"; done)
assert_resolves large_tag_list_still_detects_taken_name '1.10.0+100165' 70 "$many_tags" 1.10.1 100166
assert_fails rejects_invalid_name '1.10+5'
assert_fails rejects_invalid_build_number '1.10.0+abc'

printf '%d passed, %d failed\n' "$passes" "$failures"
[[ "$failures" -eq 0 ]]
