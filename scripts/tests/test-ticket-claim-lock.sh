#!/usr/bin/env bash

REPO="$(cd "$(dirname "$0")" && cd "$(pwd -P)/../.." && pwd)"
SCRIPT="$REPO/agents/claude/ticket-claim-lock"
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

pass=0
fail=0

export TICKET_CLAIM_LOCK_DIR="$TMPDIR/claims"
PAGE="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"

run_lock_as() {
  local session="$1"
  shift
  output="$(
    unset CLAUDE_SESSION_ID CLAUDE_CODE_SESSION_ID
    if [ -n "$session" ]; then
      export CLAUDE_SESSION_ID="$session"
    fi
    "$SCRIPT" "$@" 2>&1
  )"
  status=$?
}

assert_status() {
  local label="$1" expected="$2"
  if [ "$status" -eq "$expected" ]; then
    printf "  OK  %s\n" "$label"
    pass=$((pass + 1))
  else
    printf "  KO  %s - exit %s, expected %s (output: %s)\n" "$label" "$status" "$expected" "$output"
    fail=$((fail + 1))
  fi
}

assert_claim() {
  local label="$1" expected="$2" actual="absent"
  if [ -d "$TICKET_CLAIM_LOCK_DIR/$PAGE" ]; then
    actual="present"
  fi
  if [ "$actual" = "$expected" ]; then
    printf "  OK  %s\n" "$label"
    pass=$((pass + 1))
  else
    printf "  KO  %s - claim %s, expected %s\n" "$label" "$actual" "$expected"
    fail=$((fail + 1))
  fi
}

printf "Test group: only the session holding a claim may release it\n"

run_lock_as first take "$PAGE"
assert_status "the first session takes it" 0

run_lock_as second release "$PAGE"
assert_status "another session is refused" 1
assert_claim "and the claim survives the refusal" present

run_lock_as first release "$PAGE"
assert_status "the session holding it releases it" 0
assert_claim "and the claim is gone" absent

printf "\nTest group: a session with no id can free only a claim nobody owns\n"

run_lock_as first take "$PAGE"
run_lock_as "" release "$PAGE"
assert_status "an unresolved session id cannot free a held claim" 1
assert_claim "and the claim survives that too" present

run_lock_as first release "$PAGE"
mkdir -p "$TICKET_CLAIM_LOCK_DIR/$PAGE"
run_lock_as "" release "$PAGE"
assert_status "an unresolved session id frees a claim left with no owner" 0
assert_claim "and that claim is gone" absent

printf "\n%d passed, %d failed\n" "$pass" "$fail"
[ "$fail" -eq 0 ]
