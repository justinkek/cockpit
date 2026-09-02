#!/usr/bin/env bash

LOCK="$(cd "$(dirname "$0")/../.." && pwd)/ticket-claim-lock"
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT
export TICKET_CLAIM_LOCK_DIR="$TMPDIR/claims"

PAGE="3b38f377-6f4f-811a-977d-e66660f87d04"
BARE="3b38f3776f4f811a977de66660f87d04"

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

run() { CLAUDE_SESSION_ID="$1" bash "$LOCK" "$2" "$3" >/dev/null 2>&1; echo $?; }

printf "Test group: one winner\n"

assert_eq "first take succeeds" 0 "$(run session-a take "$PAGE")"
assert_eq "second session is refused" 1 "$(run session-b take "$PAGE")"
assert_eq "the holder may re-take its own lock" 0 "$(run session-a take "$PAGE")"

printf "\nTest group: the id's spelling does not create a second lock\n"

assert_eq "bare id is the same lock" 1 "$(run session-b take "$BARE")"

printf "\nTest group: only the holder releases\n"

assert_eq "a stranger cannot release" 1 "$(run session-b release "$PAGE")"
assert_eq "the holder can" 0 "$(run session-a release "$PAGE")"
assert_eq "and the card is free again" 0 "$(run session-b take "$PAGE")"

printf "\nTest group: owner reports who holds it\n"

assert_eq "names the holder" "session-b" \
  "$(CLAUDE_SESSION_ID=session-c bash "$LOCK" owner "$PAGE" 2>/dev/null)"

# "Nobody holds it" is an answer. Exiting non-zero would make a free card
# indistinguishable from a broken check, and a caller would have to guess.
assert_eq "an unheld card answers quietly" 0 \
  "$(CLAUDE_SESSION_ID=session-c bash "$LOCK" owner 3b38f3776f4f8000000000000000beef >/dev/null 2>&1; echo $?)"
assert_eq "and prints nothing" "" \
  "$(CLAUDE_SESSION_ID=session-c bash "$LOCK" owner 3b38f3776f4f8000000000000000beef 2>/dev/null)"

CLAUDE_SESSION_ID=session-b bash "$LOCK" release "$PAGE" >/dev/null 2>&1

printf "\nTest group: a real race has exactly one winner\n"

race_page="3b38f3776f4f8000000000000000face"
results="$TMPDIR/results"
: > "$results"
for s in a b c d e f g h; do
  ( CLAUDE_SESSION_ID="racer-$s" bash "$LOCK" take "$race_page" >/dev/null 2>&1 \
      && echo won >> "$results" ) &
done
wait

assert_eq "exactly one of eight parallel takes won" "1" "$(grep -c won "$results" | tr -d ' ')"

printf "\nTest group: release-all lets go of this session's locks only\n"

mine_a="3b38f3776f4f8000000000000000aaa1"
mine_b="3b38f3776f4f8000000000000000aaa2"
theirs="3b38f3776f4f8000000000000000bbb1"
run session-mine take "$mine_a" >/dev/null
run session-mine take "$mine_b" >/dev/null
run session-other take "$theirs" >/dev/null

assert_eq "release-all exits 0" 0 \
  "$(CLAUDE_SESSION_ID=session-mine bash "$LOCK" release-all >/dev/null 2>&1; echo $?)"
assert_eq "its first lock is gone" 0 "$(run session-else take "$mine_a")"
assert_eq "its second lock is gone" 0 "$(run session-else take "$mine_b")"
assert_eq "another session's lock is untouched" 1 "$(run session-else take "$theirs")"

# A session with no id must not sweep locks it cannot prove are its own.
assert_eq "an unknown session releases nothing" 1 \
  "$(env -u CLAUDE_SESSION_ID -u CLAUDE_CODE_SESSION_ID bash "$LOCK" release-all >/dev/null 2>&1; CLAUDE_SESSION_ID=intruder bash "$LOCK" take "$theirs" >/dev/null 2>&1; echo $?)"

printf "\nTest group: the session id comes from the shell the agent runs in\n"

harness="3b38f3776f4f8000000000000000cafe"
harness_run() {
  env -u CLAUDE_SESSION_ID CLAUDE_CODE_SESSION_ID="$1" bash "$LOCK" "$2" "$3" >/dev/null 2>&1
  echo $?
}

assert_eq "a session named only by the harness takes its lock" 0 \
  "$(harness_run harness-a take "$harness")"
assert_eq "and re-takes its own lock" 0 \
  "$(harness_run harness-a take "$harness")"
assert_eq "another harness session is refused" 1 \
  "$(harness_run harness-b take "$harness")"
assert_eq "CLAUDE_SESSION_ID wins when both are set" 0 \
  "$(CLAUDE_SESSION_ID=harness-a CLAUDE_CODE_SESSION_ID=harness-b bash "$LOCK" release "$harness" >/dev/null 2>&1; echo $?)"
assert_eq "take refuses when neither names a session" 2 \
  "$(env -u CLAUDE_SESSION_ID -u CLAUDE_CODE_SESSION_ID bash "$LOCK" take "$harness" >/dev/null 2>&1; echo $?)"

printf "\nTest group: a bad argument is refused, not guessed at\n"

assert_eq "rejects a non-id" 2 "$(run session-a take "not a page id")"
assert_eq "rejects a missing action" 2 "$(CLAUDE_SESSION_ID=x bash "$LOCK" >/dev/null 2>&1; echo $?)"

printf "\n%d passed, %d failed\n" "$pass" "$fail"
[ "$fail" -eq 0 ]
