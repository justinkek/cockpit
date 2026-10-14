#!/usr/bin/env bash

HOOKS_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CLAUDE_DIR="$(cd "$HOOKS_DIR/.." && pwd)"
PLUGIN_DIR="$(cd "$CLAUDE_DIR/../../marketplace/plugins/cockpit" && pwd)"
STATUS_SKILL="$PLUGIN_DIR/skills/ticket:x:status/SKILL.md"

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

line_of() {
  awk -v needle="$1" 'index($0, needle) { print NR; exit }' "$STATUS_SKILL"
}

assert_names() {
  local label="$1" needle="$2"
  if grep --quiet --fixed-strings "$needle" "$STATUS_SKILL"; then
    assert_ok "$label"
  else
    assert_ko "$label" "no '$needle' in $STATUS_SKILL"
  fi
}

assert_before() {
  local label="$1" first="$2" second="$3"
  local first_line second_line
  first_line="$(line_of "$first")"
  second_line="$(line_of "$second")"
  if [ -n "$first_line" ] && [ -n "$second_line" ] && [ "$first_line" -lt "$second_line" ]; then
    assert_ok "$label"
  else
    assert_ko "$label" "'$first' at line ${first_line:-none}, '$second' at line ${second_line:-none}"
  fi
}

printf "Test group: the column is recorded before the Done close-out\n"

assert_before "the walk runs before the column record" \
  'board-card" walk <id>' '**Record column**'
assert_before "the column record runs before the close-out" \
  '**Record column**' '**On `Done` only**'
assert_before "and before the model record" \
  '**Record column**' '**Record model**'

printf "\nTest group: the gates hand the branch to the publish\n"

gates_line="$(grep --fixed-strings '**Run the machine gates**' "$STATUS_SKILL")"
if printf '%s' "$gates_line" | grep --quiet --fixed-strings 'invoke `/cockpit:ticket:4:ready-for-cr`'; then
  assert_ok "step 7 invokes the publish"
else
  assert_ko "step 7 invokes the publish" "the machine gates step names no invocation of /cockpit:ticket:4:ready-for-cr"
fi

if grep --quiet --fixed-strings 'on their own' "$STATUS_SKILL"; then
  assert_ko "nothing claims the gates publish on their own" "the skill still says something fires on its own"
else
  assert_ok "nothing claims the gates publish on their own"
fi

assert_names "an unfixed defect is what stops the publish" 'an unfixed defect stops the publish'

printf "\nTest group: the In TR gate counts a layer toggle as a step\n"

assert_names "a details toggle is a step" 'a checklist item or a `<details>` layer toggle'

printf "\nTest group: leaving In BR and In TR is a person's call\n"

assert_names "the stop names who leaves them" '**In BR and In TR are left by a person.**'

printf "\n%d passed, %d failed\n" "$pass" "$fail"
[ "$fail" -eq 0 ]
