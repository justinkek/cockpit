#!/usr/bin/env bash

REPO="$(cd "$(dirname "$0")/../../../.." && pwd)"
REGISTER="$REPO/marketplace/plugins/cockpit/skills/cockpit:ticket:0:register/SKILL.md"
NEW="$REPO/marketplace/plugins/cockpit/skills/cockpit:ticket:0:new/SKILL.md"

pass=0
fail=0

assert_names() {
  local path="$1" phrase="$2"
  if grep --quiet --fixed-strings "$phrase" "$path"; then
    printf "  OK  %s names '%s'\n" "${path#"$REPO/"}" "$phrase"
    pass=$((pass + 1))
  else
    printf "  KO  %s does not name '%s'\n" "${path#"$REPO/"}" "$phrase"
    fail=$((fail + 1))
  fi
}

assert_absent() {
  local path="$1" phrase="$2"
  if grep --quiet --fixed-strings "$phrase" "$path"; then
    printf "  KO  %s still carries '%s'\n" "${path#"$REPO/"}" "$phrase"
    fail=$((fail + 1))
  else
    printf "  OK  %s no longer carries '%s'\n" "${path#"$REPO/"}" "$phrase"
    pass=$((pass + 1))
  fi
}

printf "Test group: neither path takes a populated relation on trust\n"

assert_absent "$REGISTER" "If it is populated, continue immediately"
assert_absent "$NEW" "Default to the same epic for the new ticket."

printf "\nTest group: both read the status off the cache, never off the epic page\n"

for path in "$REGISTER" "$NEW"; do
  assert_names "$path" "cockpit-cache-query\" epic-statuses"
  assert_names "$path" "Epic Done"
  assert_absent "$path" "notion-fetch the epic"
done

printf "\nTest group: register replaces a closed epic rather than reporting and leaving it\n"

assert_names "$REGISTER" "by points 1 to 4 above"
assert_names "$REGISTER" "for step 4.1 to write"
assert_names "$REGISTER" "when point 5 picked a replacement"
assert_names "$REGISTER" "raise-a-decision.md"

printf "\nTest group: a cache that predates the epic is not read as a closed one\n"

assert_names "$REGISTER" "the cache predates the epic"
assert_names "$REGISTER" "/cockpit:cache"

printf "\n%d passed, %d failed\n" "$pass" "$fail"
[ "$fail" -eq 0 ]
