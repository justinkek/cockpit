#!/usr/bin/env bash

AGENTS="$(cd "$(dirname "$0")/../../.." && pwd)"
REPO="$(dirname "$AGENTS")"
TEMPLATE="raise-a-decision.md"
ASK_PATTERN="[Aa]sk the user|[Aa]sk which|[Aa]sk whether|[Ww]ait for the user"

BRANCHES_THAT_TAKE_A_DEFAULT="agents/claude/templates/sprint-auto-assign.md
marketplace/plugins/cockpit/skills/ticket:1:br/SKILL.md
marketplace/plugins/cockpit/skills/epic:0:register/SKILL.md
marketplace/plugins/cockpit/skills/general:problem-solving/SKILL.md
marketplace/plugins/cockpit/skills/daily-mail/SKILL.md"

BRANCHES_THAT_RAISE_ON_THE_TICKET="agents/claude/templates/sprint-auto-assign.md
marketplace/plugins/cockpit/skills/ticket:1:br/SKILL.md
marketplace/plugins/cockpit/skills/epic:0:register/SKILL.md
marketplace/plugins/cockpit/skills/ticket:0:register/SKILL.md
marketplace/plugins/cockpit/skills/general:problem-solving/SKILL.md"

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

printf "Test group: no branch that stopped asking has kept the ask\n"

while IFS= read -r branch; do
  asks="no"
  grep --extended-regexp --quiet "$ASK_PATTERN" "$REPO/$branch" && asks="yes"
  assert_eq "$branch" "no" "$asks"
done <<< "$BRANCHES_THAT_TAKE_A_DEFAULT"

printf "\nTest group: each branch with a ticket to write on names the template\n"

while IFS= read -r branch; do
  names="no"
  grep --fixed-strings --quiet "$TEMPLATE" "$REPO/$branch" && names="yes"
  assert_eq "$branch" "yes" "$names"
done <<< "$BRANCHES_THAT_RAISE_ON_THE_TICKET"

printf "\nTest group: the template says what to do once the comment is posted\n"

carries="no"
grep --fixed-strings --quiet "## Then carry on" "$AGENTS/claude/templates/$TEMPLATE" && carries="yes"
assert_eq "raise-a-decision.md carries the section" "yes" "$carries"

printf "\nTest group: the template says how an answered decision is closed\n"

answered="no"
grep --line-regexp --fixed-strings --quiet "## Once it is answered" "$AGENTS/claude/templates/$TEMPLATE" && answered="yes"
assert_eq "raise-a-decision.md carries the heading the board rules name" "yes" "$answered"

answered_section="$(awk '/^## Once it is answered$/ { inside = 1; next } /^## / { inside = 0 } inside' "$AGENTS/claude/templates/$TEMPLATE")"

closes="no"
printf '%s\n' "$answered_section" | grep --fixed-strings --quiet 'board-card" resolve <card-id> <thread-id>' && closes="yes"
assert_eq "and that section resolves the thread" "yes" "$closes"

amends="no"
printf '%s\n' "$answered_section" | grep --fixed-strings --quiet -- '--section <heading>' && amends="yes"
assert_eq "and amends the section from a fresh read first" "yes" "$amends"

pointed="no"
grep --fixed-strings --quiet "\`## Once it is answered\`" "$AGENTS/shared/board.AGENTS.md" && pointed="yes"
assert_eq "board.AGENTS.md names the heading" "yes" "$pointed"

printf "\nTest group: registration settles the ticket type without asking\n"

asks_for_type="no"
grep --extended-regexp --quiet "ask when ambiguous|[Aa]sk .*[Tt]ype" \
  "$REPO/marketplace/plugins/cockpit/skills/ticket:0:register/SKILL.md" && asks_for_type="yes"
assert_eq "no ask about the type survives" "no" "$asks_for_type"

printf "\n%d passed, %d failed\n" "$pass" "$fail"
[ "$fail" -eq 0 ]
