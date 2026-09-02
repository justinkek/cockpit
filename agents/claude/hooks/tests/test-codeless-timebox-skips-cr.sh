#!/usr/bin/env bash

HOOKS_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CLAUDE_DIR="$(cd "$HOOKS_DIR/.." && pwd)"
PLUGIN_DIR="$(cd "$CLAUDE_DIR/../../marketplace/plugins/cockpit" && pwd)"
CONTRACT="$CLAUDE_DIR/templates/cockpit-operating-contract.md"
STATUS_SKILL="$PLUGIN_DIR/skills/ticket:x:status/SKILL.md"

pass=0
fail=0

assert_names() {
  local label="$1" file="$2" needle="$3"
  if grep --quiet --fixed-strings "$needle" "$file"; then
    printf "  OK  %s\n" "$label"
    pass=$((pass + 1))
  else
    printf "  KO  %s — no '%s' in %s\n" "$label" "$needle" "$file"
    fail=$((fail + 1))
  fi
}

printf "Test group: the contract sends a codeless timebox past CR\n"

assert_names "CR reviews the code, not the answer" \
  "$CONTRACT" 'CR reviews the code it produced'
assert_names "and a codeless one goes straight to Ready for FR" \
  "$CONTRACT" 'walks from In Dev straight to Ready for FR'

printf "\nTest group: the walk removes the CR columns and says how it knows\n"

assert_names "the section exists" \
  "$STATUS_SKILL" '## A timebox that produced no code'
assert_names "it names the branch read" \
  "$STATUS_SKILL" 'git log main..HEAD --oneline'
assert_names "it records the call on the card" \
  "$STATUS_SKILL" 'Timebox output'

for column in "In CR by AI" "Ready for CR" "In CR"; do
  assert_names "it removes $column" "$STATUS_SKILL" "\`$column\`"
done

printf "\n%d passed, %d failed\n" "$pass" "$fail"
[ "$fail" -eq 0 ]
