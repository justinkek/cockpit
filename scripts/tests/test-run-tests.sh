#!/usr/bin/env bash

scripts_directory() {
  cd "$(dirname "$0")" && cd "$(pwd -P)/.." && pwd
}

RUNNER="$(scripts_directory)/run-tests"

pass=0
fail=0

assert_ok() {
  printf "  OK  %s\n" "$1"
  pass=$((pass + 1))
}

assert_ko() {
  printf "  KO  %s — %s\n" "$1" "$2"
  fail=$((fail + 1))
}

assert_reports() {
  local label="$1" expected="$2" output="$3"
  case "$output" in
  *"$expected"*) assert_ok "$label" ;;
  *) assert_ko "$label" "no '$expected' in: $(printf '%s' "$output" | tr '\n' ' ')" ;;
  esac
}

assert_exits() {
  local label="$1" expected="$2" actual="$3"
  if [ "$actual" -eq "$expected" ]; then
    assert_ok "$label"
  else
    assert_ko "$label" "exited $actual, not $expected"
  fi
}

write_test() {
  local target="$1" verdict="$2"
  mkdir -p "$(dirname "$target")"
  printf '#!/usr/bin/env bash\nprintf "  a case\\n"\n' >"$target"
  [ "$verdict" = "ko" ] && printf 'exit 1\n' >>"$target"
  return 0
}

build_sandbox() {
  local sandbox
  sandbox="$(mktemp -d)"
  mkdir -p "$sandbox/scripts/tests" "$sandbox/agents/claude/hooks/tests"
  cp "$RUNNER" "$sandbox/scripts/run-tests"
  git -C "$sandbox" init --quiet
  printf '%s\n' "$sandbox"
}

track_everything() {
  git -C "$1" add --all
}

run_runner() {
  (cd "$1" && bash scripts/run-tests 2>&1)
}

printf "Test group: what it reports\n"

sandbox="$(build_sandbox)"
write_test "$sandbox/scripts/tests/test-one.sh" ok
write_test "$sandbox/agents/claude/hooks/tests/test-two.sh" ok
track_everything "$sandbox"
output="$(run_runner "$sandbox")"
assert_reports "every test passing is counted" "2 passed, 0 failed" "$output"
assert_reports "and both tests directories are reached" "agents/claude/hooks/tests/test-two.sh" "$output"

sandbox="$(build_sandbox)"
write_test "$sandbox/scripts/tests/test-one.sh" ok
write_test "$sandbox/scripts/tests/test-two.sh" ko
track_everything "$sandbox"
output="$(run_runner "$sandbox")"
assert_reports "a failing test is counted apart" "1 passed, 1 failed" "$output"
assert_reports "and the failing path is named" "KO  scripts/tests/test-two.sh" "$output"
assert_reports "and the failing test's own output is repeated" "a case" "$output"

sandbox="$(build_sandbox)"
write_test "$sandbox/scripts/tests/test-a name with spaces.sh" ok
track_everything "$sandbox"
output="$(run_runner "$sandbox")"
assert_reports "a path carrying spaces is one test, not several" "1 passed, 0 failed" "$output"

printf "\nTest group: what it exits\n"

sandbox="$(build_sandbox)"
write_test "$sandbox/scripts/tests/test-one.sh" ok
track_everything "$sandbox"
run_runner "$sandbox" >/dev/null
assert_exits "a run with no failure" 0 "$?"

sandbox="$(build_sandbox)"
write_test "$sandbox/scripts/tests/test-one.sh" ko
track_everything "$sandbox"
run_runner "$sandbox" >/dev/null
assert_exits "a run with a failure" 1 "$?"

printf "\nTest group: what the glob reaches\n"

sandbox="$(build_sandbox)"
write_test "$sandbox/scripts/tests/test-one.sh" ok
output="$(run_runner "$sandbox")"
assert_reports "a test nobody has staged yet still runs" "1 passed, 0 failed" "$output"

sandbox="$(build_sandbox)"
write_test "$sandbox/scripts/tests/test-one.sh" ok
printf 'scripts/tests/test-one.sh\n' >"$sandbox/.gitignore"
output="$(run_runner "$sandbox")"
assert_reports "an ignored test is left out" "no test found" "$output"

sandbox="$(build_sandbox)"
run_runner "$sandbox" >/dev/null
assert_exits "a run that found no test at all" 1 "$?"

sandbox="$(build_sandbox)"
write_test "$sandbox/tools/tests/test-one.sh" ok
track_everything "$sandbox"
output="$(run_runner "$sandbox")"
assert_reports "a tests directory nothing names is reached" "1 passed, 0 failed" "$output"

sandbox="$(build_sandbox)"
write_test "$sandbox/tests/test-one.sh" ok
track_everything "$sandbox"
output="$(run_runner "$sandbox")"
assert_reports "a tests directory at the repo root is reached" "1 passed, 0 failed" "$output"

printf "\n%d passed, %d failed\n" "$pass" "$fail"
[ "$fail" -eq 0 ]
