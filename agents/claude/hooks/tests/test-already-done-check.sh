#!/usr/bin/env bash

HOOKS_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CLAUDE_DIR="$(cd "$HOOKS_DIR/.." && pwd)"
SKILLS_DIR="$(cd "$CLAUDE_DIR/../../marketplace/plugins/cockpit/skills" && pwd)"
TEMPLATE="$CLAUDE_DIR/templates/already-done-check.md"
COPILOT_FINDING="$CLAUDE_DIR/templates/copilot-finding.md"

pass=0
fail=0

squash() {
  awk '{ $1 = $1; printf "%s ", $0 }' "$1"
}

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

holds() {
  if squash "$1" | grep --quiet --fixed-strings -- "$2"; then
    printf 'yes'
  else
    printf 'no'
  fi
}

found_section="$(awk '/^## What you found$/ { inside = 1; next } /^## / { inside = 0 } inside' "$TEMPLATE")"

printf "Test group: every stage that runs the check names it\n"

for skill in "ticket:1:br" "ticket:2:tr" "ticket:3:dev"; do
  assert_eq "$skill" "yes" "$(holds "$SKILLS_DIR/$skill/SKILL.md" 'templates/already-done-check.md')"
done

printf "\nTest group: a hit blocks the card the way a copilot finding does\n"

assert_eq "already-done-check.md sets the flag through blocked-flag.md" "yes" "$(holds "$TEMPLATE" 'templates/blocked-flag.md')"
assert_eq "copilot-finding.md sets it through the same template" "yes" "$(holds "$COPILOT_FINDING" 'templates/blocked-flag.md')"

printf "\nTest group: dev that copilot claimed is not treated as attended\n"

unattended_line="$(printf '%s\n' "$found_section" | grep --fixed-strings 'Nobody reads the chat')"
names_copilot="no"
printf '%s' "$unattended_line" | grep --quiet --fixed-strings '/cockpit:ticket:0:copilot' && names_copilot="yes"
assert_eq "the unattended branch names a session copilot started" "yes" "$names_copilot"

names_in_dev="no"
printf '%s' "$unattended_line" | grep --quiet --fixed-strings '`In Dev`' && names_in_dev="yes"
assert_eq "and a card it claimed in In Dev" "yes" "$names_in_dev"

waits_unasked="no"
printf '%s\n' "$found_section" | grep --ignore-case --word-regexp 'wait' | grep --invert-match --quiet --fixed-strings 'they started' && waits_unasked="yes"
assert_eq "every line that waits says a person started the session" "no" "$waits_unasked"

attended_line="$(printf '%s\n' "$found_section" | grep --fixed-strings 'A person reads the chat')"
names_register="no"
printf '%s' "$attended_line" | grep --quiet --fixed-strings '/cockpit:ticket:0:register' && names_register="yes"
assert_eq "a BR register started from the person's own message is attended" "yes" "$names_register"

assert_eq "the bare report-and-wait has not come back" "no" "$(holds "$TEMPLATE" 'Report the finding and wait')"

printf "\nTest group: a run that finds its own finding posts nothing new\n"

assert_eq "the template says a finding already on the card is not posted again" "yes" "$(holds "$TEMPLATE" 'not posted again')"

printf "\nTest group: the quote asked for exists at BR, where no Then does\n"

assert_eq "a hit is quoted against the outcome, not the Then" "no" "$(holds "$TEMPLATE" 'answers the Then')"
assert_eq "the BR outcome is the Context" "yes" "$(holds "$TEMPLATE" '`## Context`')"

printf "\n%d passed, %d failed\n" "$pass" "$fail"
[ "$fail" -eq 0 ]
