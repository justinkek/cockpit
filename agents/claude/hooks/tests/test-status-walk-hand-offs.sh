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

text_of() {
  awk -v needle="$1" 'index($0, needle) { print; exit }' "$STATUS_SKILL"
}

assert_names() {
  local label="$1" needle="$2"
  if grep --quiet --fixed-strings "$needle" "$STATUS_SKILL"; then
    assert_ok "$label"
  else
    assert_ko "$label" "no '$needle' in $STATUS_SKILL"
  fi
}

assert_absent() {
  local label="$1" needle="$2"
  if grep --quiet --fixed-strings "$needle" "$STATUS_SKILL"; then
    assert_ko "$label" "'$needle' is still in $STATUS_SKILL"
  else
    assert_ok "$label"
  fi
}

assert_line_names() {
  local label="$1" anchor="$2" needle="$3"
  if text_of "$anchor" | grep --quiet --fixed-strings "$needle"; then
    assert_ok "$label"
  else
    assert_ko "$label" "the line holding '$anchor' names no '$needle'"
  fi
}

assert_line_omits() {
  local label="$1" anchor="$2" needle="$3"
  if text_of "$anchor" | grep --quiet --fixed-strings "$needle"; then
    assert_ko "$label" "the line holding '$anchor' still names '$needle'"
  else
    assert_ok "$label"
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

printf "Test group: the column is recorded in the walk's own call\n"

assert_line_names "the walk and the column record are one command" \
  'board-card" walk <id>' '&& "$HOME/.cockpit/scripts/ticket-register-column" "<target>"'
assert_absent "no column record runs as a call of its own" '"<landed-column>"'
assert_before "the record is in place before the close-out" \
  'board-card" walk <id>' '**On `Done` only**'
assert_before "and before the model record" \
  'board-card" walk <id>' '**Record model**'

done_exception='**One exception: `Done`.**'
done_line="$(text_of "$done_exception")"
record_at="$(awk -v haystack="$done_line" 'BEGIN { print index(haystack, "ticket-register-column\" \"Done\"") }')"
close_out_at="$(awk -v haystack="$done_line" 'BEGIN { print index(haystack, "run the close-out") }')"
if [ "$record_at" -gt 0 ] && [ "$close_out_at" -gt "$record_at" ]; then
  assert_ok "a card found at Done is recorded before its close-out"
else
  assert_ko "a card found at Done is recorded before its close-out" "record at ${record_at}, close-out at ${close_out_at}"
fi

printf "\nTest group: the publish runs once, after the parent is brought along\n"

assert_line_names "the publish step invokes ready-for-cr" \
  '**Publish**' 'invoke `/cockpit:ticket:4:ready-for-cr`'
assert_line_omits "the gates step no longer invokes it" \
  '**Run the machine gates**' 'invoke `/cockpit:ticket:4:ready-for-cr`'
assert_before "the gates run before the roll-up" \
  '**Run the machine gates**' '**Bring the parent along**'
assert_before "the roll-up runs before the publish" \
  '**Bring the parent along**' '**Publish**'
assert_before "the publish runs before the report" \
  '**Publish**' '**Report**'
assert_line_names "a walk ready-for-cr started does not publish again" \
  '**Publish**' 'when `/cockpit:ticket:4:ready-for-cr` step 1 started this walk'
assert_line_names "a split parent's roll-up runs no gates" \
  '**Run the machine gates**' 'A split parent that step 8'
assert_line_names "the close-the-loop bullet points at the publish step" \
  '**Close the loop**' 'step 9 of the walk then invokes'
assert_absent "nothing claims the gates publish on their own" 'on their own'

printf "\nTest group: what holds the publish is stated once, in the gates template\n"

assert_line_names "the publish step names the template that decides" \
  '**Publish**' '`status-machine-gates.md` says holds the publish'
assert_absent "the skill does not restate the divergence rule" 'unfixed divergence'

printf "\nTest group: the In TR gate counts a layer toggle as a step\n"

assert_names "a details toggle is a step" 'a checklist item or a `<details>` layer toggle'

printf "\nTest group: leaving In BR and In TR is a person's call\n"

in_x='**In BR and In TR are left by a person.**'
assert_names "the stop names who leaves them" "$in_x"
assert_line_names "a skill the person asked for is the ask" "$in_x" 'asking for a skill whose walk does'
assert_line_names "the edit gate's send to dev is not" "$in_x" 'the edit gate sending the session to `/cockpit:ticket:3:dev`'
assert_line_names "the split parent's roll-up is the named exemption" "$in_x" "split parent walked by step 8's roll-up"
assert_line_omits "the pointer carries no summary of the contract" "$in_x" 'is the approval'

printf "\n%d passed, %d failed\n" "$pass" "$fail"
[ "$fail" -eq 0 ]
