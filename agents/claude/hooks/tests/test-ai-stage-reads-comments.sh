#!/usr/bin/env bash

HOOKS_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CLAUDE_DIR="$(cd "$HOOKS_DIR/.." && pwd)"
PLUGIN_DIR="$(cd "$CLAUDE_DIR/../../marketplace/plugins/cockpit" && pwd)"
TEMPLATE="$CLAUDE_DIR/templates/page-comments.md"
SKILLS_DIR="$PLUGIN_DIR/skills"

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
  "ticket:1:br" \
  "ticket:2:tr" \
  "ticket:3:dev" \
  "ticket:x:back-from-column" \
  "epic:1:fd" \
  "epic:2:td"; do
  assert_names "$skill reads them" \
    "$SKILLS_DIR/$skill/SKILL.md" 'templates/page-comments.md'
done

assert_names "and dev reads them before it edits anything" \
  "$SKILLS_DIR/ticket:3:dev/SKILL.md" 'open comments before the first edit'

printf "\nTest group: one read, taken once, at the start\n"

assert_names "the template takes one read" \
  "$TEMPLATE" 'One read sees everything open:'
assert_names "and that read is the board's own" \
  "$TEMPLATE" 'board-card" comments <card-id>'
assert_names "and page and line-anchored comments come back alike" \
  "$TEMPLATE" 'Page comments and line-anchored ones come back alike'
assert_names "and leaves the resolved threads out" \
  "$TEMPLATE" 'so `--all` is never passed here'
assert_absent "and takes no further read before a write" \
  "$TEMPLATE" 'immediately before the write'

printf "\n%d passed, %d failed\n" "$pass" "$fail"
[ "$fail" -eq 0 ]
