#!/usr/bin/env bash

HOOKS_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CLAUDE_DIR="$(cd "$HOOKS_DIR/.." && pwd)"
REPO_DIR="$(cd "$CLAUDE_DIR/../.." && pwd)"
TR="$CLAUDE_DIR/skills/cockpit:ticket:2:tr/SKILL.md"
CONVENTIONS="$REPO_DIR/CLAUDE.md"

pass=0
fail=0

squash() {
  awk '{ $1 = $1; printf "%s ", $0 }' "$1"
}

assert_names() {
  local label="$1" file="$2" needle="$3"
  if squash "$file" | grep --quiet --fixed-strings "$needle"; then
    printf "  OK  %s\n" "$label"
    pass=$((pass + 1))
  else
    printf "  KO  %s — no '%s' in %s\n" "$label" "$needle" "$file"
    fail=$((fail + 1))
  fi
}

printf "Test group: the tree the tech steps open with\n"

assert_names "the tr skill writes it as a diff code block" \
  "$TR" 'A diff code block opens the section'
assert_names "and marks each file new, removed or edited" \
  "$TR" '`+` new, `-` removed or `!` edited'
assert_names "and takes the sentence from the step summary above the In path toggle" \
  "$TR" 'the step summary above its `In <path>` toggle is that sentence'
assert_names "and gives a directory line a leading space so the markers line up" \
  "$TR" 'Directory lines carry a leading space'
assert_names "and joins every file line to the folder above it" \
  "$TR" 'Every file line is joined to the folder above it'
assert_names "and carries the column down past a folder with entries to come" \
  "$TR" 'carries `│` down the column its own join sat in'
assert_names "and refuses a file line reaching its name on indentation alone" \
  "$TR" 'reaching its name on indentation alone is refused'
assert_names "and heads each tree in a rule of equals signs" \
  "$TR" '120 character rule of `=`'
assert_names "and heads a one-thing ticket's single tree too" \
  "$TR" 'A ticket doing one thing has one tree'
assert_names "and writes one line per file" \
  "$TR" 'One line per file'
assert_names "and starts every sentence in a tree at one column" \
  "$TR" 'starts at the same column'

printf "\nTest group: the sequence flow below it\n"

assert_names "the tr skill draws it only for a change spanning calls" \
  "$TR" 'drawn only when the change spans more than one call'
assert_names "and writes it as a mermaid block carrying title and autonumber" \
  "$TR" 'a `mermaid` one carrying `title` and'
assert_names "and shades a call it adds green" \
  "$TR" 'rgb(220, 245, 220)'
assert_names "and a call it removes red" \
  "$TR" 'rgb(255, 225, 225)'
assert_names "and leaves an unchanged call unshaded" \
  "$TR" 'no shading for one that already happens'
assert_names "and draws a changed call twice, red above green" \
  "$TR" 'drawn twice - the old one red, above the new one in green'
assert_names "and resets the counter between the pair" \
  "$TR" '`autonumber 1` between them resets the counter'
assert_names "and reads each label as the middle of a sentence" \
  "$TR" "Each arrow's label is the middle of a sentence"
assert_names "and gives a self-call the whole predicate" \
  "$TR" 'has no receiver to append'
assert_names "and carries one unshaded call each side of the shaded run" \
  "$TR" 'immediately before the shaded run and the one'
assert_names "and names a lane for what it is" \
  "$TR" 'A lane is named for what it is'

printf "\nTest group: how a tech step summary is written\n"

assert_names "the tr skill lists the verbs a summary opens on" \
  "$TR" '`add`, `replace`, `remove`, `rename`, `move`'
assert_names "and asks it to name the thing" \
  "$TR" '**Name the thing.**'
assert_names "and refuses it a reason clause" \
  "$TR" 'No `so ...` clause'
assert_names "and names the guard that holds the checkable half" \
  "$TR" 'guard-tech-steps.sh'
assert_names "and says which half stays a rule" \
  "$TR" 'not machine-checkable and stay rules here'

printf "\nTest group: the skill builds them before it writes the section\n"

assert_names "the workflow writes the tree then the flow" \
  "$TR" '**Write the tree, then the sequence flow**'
assert_names "and does it before the write to the ticket" \
  "$TR" 'this runs before the write below, not after it'
assert_names "the self-check reads the tree back" \
  "$TR" 'The tree is the first thing under the heading'
assert_names "and reads every summary back" \
  "$TR" 'Every summary opens on one of the five verbs'

printf "\nTest group: this repo says where the rules live\n"

assert_names "the conventions name the drawings" \
  "$CONVENTIONS" '## The drawings that open the tech steps'

printf "\n%d passed, %d failed\n" "$pass" "$fail"
[ "$fail" -eq 0 ]
