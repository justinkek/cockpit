#!/usr/bin/env bash

HOOKS_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CLAUDE_DIR="$(cd "$HOOKS_DIR/.." && pwd)"
PLUGIN_DIR="$(cd "$CLAUDE_DIR/../../marketplace/plugins/cockpit" && pwd)"
AGENTS_DIR="$(cd "$CLAUDE_DIR/.." && pwd)"

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

assert_names_unwrapped() {
  local label="$1" file="$2" needle="$3"
  if tr '\n' ' ' < "$file" | grep --quiet --fixed-strings "$needle"; then
    printf "  OK  %s\n" "$label"
    pass=$((pass + 1))
  else
    printf "  KO  %s — no '%s' in %s\n" "$label" "$needle" "$file"
    fail=$((fail + 1))
  fi
}

printf "Test group: each per-project section is read from one file\n"

assert_names "the extra reviews list" \
  "$CLAUDE_DIR/templates/status-machine-gates.md" '`## Extra reviews` in its `./AGENTS.md`'
assert_names "the columns a project skips" \
  "$PLUGIN_DIR/skills/ticket:x:status/SKILL.md" 'read `./AGENTS.md` for `## Ticket walk skip`'
assert_names "the sprint opt-out that reads the same section" \
  "$CLAUDE_DIR/templates/sprint-auto-assign.md" '`## Ticket walk skip` section in `./AGENTS.md`'
assert_names "the hook that greps the file rather than naming it in prose" \
  "$PLUGIN_DIR/scripts/hooks/remind-ticket-status.sh" 'conventions_file="./AGENTS.md"'

printf "\nTest group: no repo opts out of the branch guard\n"

assert_names "the commit skill says nothing turns it off" \
  "$PLUGIN_DIR/skills/ticket:4:commit/SKILL.md" 'No project opts out of this'
assert_names "and the pull request skill says the same" \
  "$PLUGIN_DIR/skills/ticket:4:ready-for-cr/SKILL.md" 'Nothing in a project'

optout="$(grep --recursive --files-with-matches --fixed-strings '## Commit to main' "$AGENTS_DIR" "$(dirname "$AGENTS_DIR")/AGENTS.md" 2>/dev/null \
  | grep --invert-match --fixed-strings "$(basename "$0")")"

if [ -z "$optout" ]; then
  printf "  OK  no file still carries the opt-out section\n"
  pass=$((pass + 1))
else
  printf "  KO  these still carry the opt-out section:\n%s\n" "$optout"
  fail=$((fail + 1))
fi

printf "\nTest group: the other file holds nothing but a line naming this one\n"

stray="$(grep --recursive --fixed-strings './CLAUDE.md' "$AGENTS_DIR" \
  --exclude="$(basename "$0")" \
  | grep --invert-match --fixed-strings 'one line naming it')"

if [ -z "$stray" ]; then
  printf "  OK  no instruction reads a project's conventions from the other file\n"
  pass=$((pass + 1))
else
  printf "  KO  these read a project's conventions from the other file:\n%s\n" "$stray"
  fail=$((fail + 1))
fi

printf "\nTest group: a skill that creates the conventions file creates the pointer too\n"

for skill in "$AGENTS_DIR"/shared/skills/launchpad:*/SKILL.md; do
  assert_names "$(basename "$(dirname "$skill")")" \
    "$skill" 'write `./CLAUDE.md` as one line naming it'
done

printf "\n%d passed, %d failed\n" "$pass" "$fail"
[ "$fail" -eq 0 ]
