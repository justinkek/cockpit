#!/usr/bin/env bash

AGENTS="$(cd "$(dirname "$0")/../../.." && pwd)"
REPO="$(dirname "$AGENTS")"
REGISTER="$REPO/marketplace/plugins/cockpit/skills/cockpit:ticket:0:register/SKILL.md"
COPILOT="$REPO/marketplace/plugins/cockpit/skills/cockpit:ticket:0:copilot/SKILL.md"
WATCHER="$REPO/marketplace/plugins/cockpit/scripts/ticket-watch-column"
BR_SKILL="/cockpit:ticket:1:br"

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

line_of() {
  local hit
  hit="$(grep --line-number --fixed-strings "$1" "$2" | head -n 1)"
  printf '%s' "${hit%%:*}"
}

printf "Test group: the register skill hands the card it advanced to the BR skill\n"

names="no"
grep --fixed-strings --quiet "$BR_SKILL" "$REGISTER" && names="yes"
assert_eq "register names $BR_SKILL" "yes" "$names"

printf "\nTest group: the hand-off comes after the steps that hold the card\n"

hand_off_line="$(line_of "$BR_SKILL" "$REGISTER")"

assert_hand_off_follows() {
  local label="$1" earlier
  earlier="$(line_of "$2" "$REGISTER")"
  local follows="no"
  if [ -n "$hand_off_line" ] && [ -n "$earlier" ] && [ "$hand_off_line" -gt "$earlier" ]; then
    follows="yes"
  fi
  assert_eq "hand-off follows $label" "yes" "$follows"
}

assert_hand_off_follows "the claim" "ticket-claim-lock"
assert_hand_off_follows "the column record" "ticket-register-column"
assert_hand_off_follows "the watcher arming" "ticket-watch-column"

printf "\nTest group: every path sending a BR by-AI column somewhere sends it to the same skill\n"

for path in "$COPILOT" "$WATCHER"; do
  agrees="no"
  grep --fixed-strings --quiet "$BR_SKILL" "$path" && agrees="yes"
  assert_eq "${path#"$REPO/"} names $BR_SKILL" "yes" "$agrees"
done

printf "\n%d passed, %d failed\n" "$pass" "$fail"
[ "$fail" -eq 0 ]
