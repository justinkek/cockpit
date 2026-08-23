#!/usr/bin/env bash

HOOKS_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CLAUDE_DIR="$(cd "$HOOKS_DIR/.." && pwd)"
TEMPLATE="$CLAUDE_DIR/templates/page-comments.md"
SKILLS_DIR="$CLAUDE_DIR/skills"

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

assert_absent() {
  local label="$1" file="$2" needle="$3"
  if squash "$file" | grep --quiet --fixed-strings "$needle"; then
    printf "  KO  %s — '%s' is still in %s\n" "$label" "$needle" "$file"
    fail=$((fail + 1))
  else
    printf "  OK  %s\n" "$label"
    pass=$((pass + 1))
  fi
}

printf "Test group: every stage an agent runs opens on the comments\n"

for skill in \
  "cockpit:ticket:1:br" \
  "cockpit:ticket:2:tr" \
  "cockpit:ticket:3:dev" \
  "cockpit:ticket:x:back-from-column" \
  "cockpit:epic:1:fd" \
  "cockpit:epic:2:td"; do
  assert_names "$skill reads them" \
    "$SKILLS_DIR/$skill/SKILL.md" 'templates/page-comments.md'
done

assert_names "and dev reads them before it edits anything" \
  "$SKILLS_DIR/cockpit:ticket:3:dev/SKILL.md" 'open comments before the first edit'

printf "\nTest group: one read, taken once, at the start\n"

assert_names "the template takes one read" \
  "$TEMPLATE" 'One read sees everything open: `notion-get-comments`'
assert_names "and asks it for every block" \
  "$TEMPLATE" 'the `page_id` and `include_all_blocks: true`'
assert_absent "and leaves the resolved threads out" \
  "$TEMPLATE" 'include_resolved'
assert_names "and says an anchor inside a code block comes back too" \
  "$TEMPLATE" 'an anchor on a line inside a code block among them'
assert_names "and refuses the fetch summary as a second read" \
  "$TEMPLATE" 'is not a second read'
assert_absent "and takes no further read before a write" \
  "$TEMPLATE" 'immediately before the write'

printf "\n%d passed, %d failed\n" "$pass" "$fail"
[ "$fail" -eq 0 ]
