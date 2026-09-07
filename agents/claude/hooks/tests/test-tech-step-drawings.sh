#!/usr/bin/env bash

HOOKS_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CLAUDE_DIR="$(cd "$HOOKS_DIR/.." && pwd)"
PLUGIN_DIR="$(cd "$CLAUDE_DIR/../../marketplace/plugins/cockpit" && pwd)"
REPO_DIR="$(cd "$CLAUDE_DIR/../.." && pwd)"
TR="$PLUGIN_DIR/skills/ticket:2:tr/SKILL.md"
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

printf "Test group: the skill points at the rules rather than restating them\n"

assert_names "the tr skill names the plugin's rules file" \
  "$TR" 'Read `rules/tech-steps.md` from the tech-ref plugin'
assert_names "and adds the one layer the plugin has no row for" \
  "$TR" 'the Notion cockpit - schema, properties, automations'

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
