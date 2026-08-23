#!/usr/bin/env bash

AGENTS="$(cd "$(dirname "$0")/../../.." && pwd)"
REPO="$(dirname "$AGENTS")"
CACHE_PATH="state/cockpit/cache.json"
QUERY_SCRIPT="cockpit-cache-query"

SKILLS_THAT_REWRITE_THE_WHOLE_CACHE="agents/claude/skills/cockpit:cache/SKILL.md
agents/shared/skills/cockpit:ticket:0:register/SKILL.md"

SKILLS_THAT_READ_ONE_KEY="agents/shared/skills/cockpit:ticket:0:register/SKILL.md
agents/claude/skills/cockpit:epic:0:register/SKILL.md
agents/claude/skills/cockpit:ticket:0:new/SKILL.md
agents/claude/skills/cockpit:ticket:0:copilot/SKILL.md
agents/claude/skills/cockpit:ticket:2:tr/SKILL.md
agents/claude/skills/cockpit:ticket:x:status/SKILL.md"

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

printf "Test group: only a skill that rewrites the cache names its path\n"

found=""
while IFS= read -r hit; do
  [ -n "$hit" ] || continue
  found="$found${hit#"$REPO"/}
"
done <<< "$(grep --recursive --files-with-matches --fixed-strings "$CACHE_PATH" "$AGENTS"/*/skills)"

assert_eq "the two that write it back are exactly the two that open it" \
  "$(printf '%s' "$SKILLS_THAT_REWRITE_THE_WHOLE_CACHE" | sort)" \
  "$(printf '%s' "$found" | sort)"

assert_eq "and the register skill opens it at its one write step, nowhere else" "1" \
  "$(grep --count --fixed-strings "$CACHE_PATH" "$REPO/agents/shared/skills/cockpit:ticket:0:register/SKILL.md")"

printf "\nTest group: every reader asks the script for its key\n"

while IFS= read -r reader; do
  found="no"
  grep --quiet --fixed-strings "$QUERY_SCRIPT" "$REPO/$reader" && found="yes"
  assert_eq "$reader" "yes" "$found"
done <<< "$SKILLS_THAT_READ_ONE_KEY"

printf "\n%d passed, %d failed\n" "$pass" "$fail"
[ "$fail" -eq 0 ]
