#!/usr/bin/env bash

WATCHER="$(cd "$(dirname "$0")/../.." && pwd)/pr-watch-checks"
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

pass=0
fail=0

assert_eq() {
  local label="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then
    printf "  OK  %s\n" "$label"
    pass=$((pass + 1))
  else
    printf "  KO  %s — expected '%s', got '%s'\n" "$label" "$expected" "$actual"
    fail=$((fail + 1))
  fi
}

assert_contains() {
  local label="$1" expected="$2" output="$3"
  if printf '%s' "$output" | grep --quiet --fixed-strings "$expected"; then
    printf "  OK  %s\n" "$label"
    pass=$((pass + 1))
  else
    printf "  KO  %s — expected '%s' in output '%s'\n" "$label" "$expected" "$output"
    fail=$((fail + 1))
  fi
}

BIN="$TMPDIR/bin"
FIXTURE="$TMPDIR/fixture"
mkdir -p "$BIN" "$FIXTURE"

PULL_REQUEST="https://github.com/owner/repo/pull/7"

cat > "$BIN/gh" <<'STUB'
#!/usr/bin/env bash
case "$*" in
  "auth status")
    [ -n "${PR_CHECKS_TEST_AUTHENTICATED:-}" ] || exit 1
    exit 0
    ;;
esac
case "$*" in
  *--watch*)
    printf '%s\n' "$(cat "$PR_CHECKS_FIXTURE/watch-output")"
    exit "$(cat "$PR_CHECKS_FIXTURE/watch-status")"
    ;;
  *--json*)
    cat "$PR_CHECKS_FIXTURE/buckets"
    exit 0
    ;;
esac
exit 1
STUB

chmod +x "$BIN/gh"

run_watch() {
  local watch_status="$1" watch_output="$2" buckets="$3"

  printf '%s' "$watch_status" > "$FIXTURE/watch-status"
  printf '%s' "$watch_output" > "$FIXTURE/watch-output"
  printf '%s' "$buckets" > "$FIXTURE/buckets"

  PATH="$BIN:$PATH" \
  PR_CHECKS_FIXTURE="$FIXTURE" \
  PR_CHECKS_TEST_AUTHENTICATED="yes" \
    bash "$WATCHER" "$PULL_REQUEST" 2>&1
}

all_passed='[{"name":"build","bucket":"pass"},{"name":"lint","bucket":"pass"},{"name":"test","bucket":"pass"}]'
some_failed='[{"name":"build","bucket":"fail"},{"name":"lint","bucket":"fail"},{"name":"test","bucket":"pass"}]'
one_cancelled='[{"name":"build","bucket":"cancel"},{"name":"lint","bucket":"pass"}]'
one_skipped='[{"name":"build","bucket":"pass"},{"name":"docs","bucket":"skipping"}]'

printf "Test group: every check passing is one line naming the count\n"

output="$(run_watch 0 "All checks were successful" "$all_passed")"
assert_eq "one line only" "1" "$(printf '%s' "$output" | grep --count . | tr -d ' ')"
assert_contains "names the total" "all 3 checks passed" "$output"
assert_contains "names the pull request" "$PULL_REQUEST" "$output"
assert_eq "asks for nothing" "0" \
  "$(printf '%s' "$output" | grep --count --fixed-strings "invoke" | tr -d ' ')"

output="$(run_watch 0 "All checks were successful" "$one_skipped")"
assert_contains "a skipped check is not a failure" "all 2 checks passed" "$output"

printf "\nTest group: a failing check names which ones and the skill that reopens dev\n"

output="$(run_watch 1 "Some checks were not successful" "$some_failed")"
assert_contains "names how many of how many" "2 of 3 checks failed" "$output"
assert_contains "names each failing check" "build, lint" "$output"
assert_contains "names the skill that reopens dev" "/cockpit:ticket:3:dev" "$output"
assert_eq "one line only" "1" "$(printf '%s' "$output" | grep --count . | tr -d ' ')"

output="$(run_watch 1 "Some checks were not successful" "$one_cancelled")"
assert_contains "a cancelled check counts as failed" "1 of 2 checks failed" "$output"
assert_contains "and is named" "build" "$output"

printf "\nTest group: a repo with no checks says so rather than going quiet\n"

output="$(run_watch 1 "no checks reported on the 'main' branch" "[]")"
assert_contains "says there was nothing to wait for" "no checks reported" "$output"
assert_eq "names no failure" "0" \
  "$(printf '%s' "$output" | grep --count --fixed-strings "failed" | tr -d ' ')"

printf "\nTest group: checks that finished but cannot be read is a failure, not a pass\n"

output="$(run_watch 0 "All checks were successful" "")"
status=$?
assert_contains "says the checks could not be read" "could not be read" "$output"
assert_eq "exits non-zero even though the watch succeeded" "1" "$status"

printf "\nTest group: a machine that cannot answer is loud, not silent\n"

output="$(PATH="$BIN:$PATH" PR_CHECKS_FIXTURE="$FIXTURE" bash "$WATCHER" "$PULL_REQUEST" 2>&1)"
status=$?
assert_contains "announces the missing login" "gh is not authenticated" "$output"
assert_eq "exits non-zero" "1" "$status"

output="$(PATH="$BIN:$PATH" PR_CHECKS_FIXTURE="$FIXTURE" \
  PR_CHECKS_TEST_AUTHENTICATED="yes" bash "$WATCHER" 2>&1)"
status=$?
assert_contains "a call with no pull request says how to call it" "usage: pr-watch-checks" "$output"
assert_eq "exits non-zero" "1" "$status"

printf "\n%d passed, %d failed\n" "$pass" "$fail"
[ "$fail" -eq 0 ]
