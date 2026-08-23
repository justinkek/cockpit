#!/usr/bin/env bash

HOOKS_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CLAUDE_DIR="$(cd "$HOOKS_DIR/.." && pwd)"
AGENTS_DIR="$(cd "$CLAUDE_DIR/.." && pwd)"

COMMIT_SKILL="$CLAUDE_DIR/skills/cockpit:ticket:4:commit/SKILL.md"
CLEANUP_SKILL="$CLAUDE_DIR/skills/cockpit:ticket:4:cr:cleanup-commits/SKILL.md"

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

printf "Test group: the commit skill names every conventional commit type\n"

type_list_line="$(grep --extended-regexp '^ +- Types: ' "$COMMIT_SKILL")"

for type in feat fix perf refactor style chore docs test build ci revert; do
  if printf '%s' "$type_list_line" | grep --quiet --extended-regexp "[ ,]$type(,|$)"; then
    printf "  OK  %s\n" "$type"
    pass=$((pass + 1))
  else
    printf "  KO  %s — not in '%s'\n" "$type" "$type_list_line"
    fail=$((fail + 1))
  fi
done

printf "\nTest group: no other file writes a type list of its own\n"

rival_lists="$(grep --recursive --line-number --extended-regexp '[Tt]ypes: feat' "$AGENTS_DIR" \
  --exclude-dir=worktrees \
  --exclude="$(basename "$0")" \
  | grep --invert-match --fixed-strings 'cockpit:ticket:4:commit/SKILL.md')"

if [ -z "$rival_lists" ]; then
  printf "  OK  the list is written once\n"
  pass=$((pass + 1))
else
  printf "  KO  these write a type list of their own:\n%s\n" "$rival_lists"
  fail=$((fail + 1))
fi

printf "\nTest group: the cleanup skill reads the list from the commit skill\n"

assert_names "the pointer" "$CLEANUP_SKILL" 'the types are the ones the `cockpit:ticket:4:commit` skill lists'

printf "\n%d passed, %d failed\n" "$pass" "$fail"
[ "$fail" -eq 0 ]
