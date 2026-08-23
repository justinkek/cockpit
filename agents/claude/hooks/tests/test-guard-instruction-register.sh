#!/usr/bin/env bash

HOOK="$(cd "$(dirname "$0")/.." && pwd)/guard-instruction-register.sh"

pass=0
fail=0

run_edit() {
  jq --null-input --compact-output --arg path "$1" --arg old "$2" --arg new "$3" \
    '{tool_name:"Edit",tool_input:{file_path:$path,old_string:$old,new_string:$new}}' | "$HOOK" 2>/dev/null
}

run_write() {
  jq --null-input --compact-output --arg path "$1" --arg content "$2" \
    '{tool_name:"Write",tool_input:{file_path:$path,content:$content}}' | "$HOOK" 2>/dev/null
}

run_bash() {
  jq --null-input --compact-output --arg command "$1" \
    '{tool_name:"Bash",tool_input:{command:$command}}' | "$HOOK" 2>/dev/null
}

assert_denies() {
  local label="$1" output="$2"
  if printf '%s' "$output" | grep --quiet --fixed-strings '"permissionDecision":"deny"'; then
    printf "  OK  %s\n" "$label"
    pass=$((pass + 1))
  else
    printf "  KO  %s — expected a deny, got '%s'\n" "$label" "$output"
    fail=$((fail + 1))
  fi
}

assert_silent() {
  local label="$1" output="$2"
  if [ -z "$output" ]; then
    printf "  OK  %s\n" "$label"
    pass=$((pass + 1))
  else
    printf "  KO  %s — expected silence, got '%s'\n" "$label" "$output"
    fail=$((fail + 1))
  fi
}

printf "Test group: a newly added reason clause is denied\n"

assert_denies "so I can, in the shared core" \
  "$(run_edit /repo/agents/shared/base.AGENTS.md "" "- Prefix points with a tag so I can tell at a glance.")"
assert_denies "so that, in a skill" \
  "$(run_edit /repo/agents/claude/skills/x/SKILL.md "" "Poll the stamp so that the board stays honest.")"
assert_denies "This is to, in a template" \
  "$(run_edit /repo/agents/claude/templates/ticket-page.md "" "This is to help the reader scan it.")"
assert_denies "a Why paragraph" \
  "$(run_edit /repo/agents/shared/base.AGENTS.md "" "Why: every token is attributed to the ticket.")"
assert_denies "which is why" \
  "$(run_write /repo/agents/claude/templates/board-ids.md "The id is unrecorded, which is why the script exits 3.")"
assert_denies "a project CLAUDE.md outside the agents tree" \
  "$(run_edit /repo/CLAUDE.md "" "Pin the version so that the build is reproducible.")"

printf "\nTest group: the rule itself passes\n"

assert_silent "the same instruction with the clause removed" \
  "$(run_edit /repo/agents/shared/base.AGENTS.md "" "- Prefix points with a tag.")"
assert_silent "a consequence clause naming what follows" \
  "$(run_edit /repo/agents/shared/base.AGENTS.md "" "A skipped column cannot be repaired, so the first pass must be correct.")"
assert_silent "a counter-case naming what does not count" \
  "$(run_edit /repo/agents/shared/base.AGENTS.md "" "A reply that moves on without naming an option is not an answer to it.")"

printf "\nTest group: only newly added text counts\n"

assert_silent "a clause carried through an edit untouched" \
  "$(run_edit /repo/agents/claude/skills/x/SKILL.md "one line so that it holds" "two lines so that it holds")"
assert_denies "a clause added beside one already there" \
  "$(run_edit /repo/agents/claude/skills/x/SKILL.md "one line so that it holds" "one line so that it holds, and This is to explain it")"

printf "\nTest group: files the guard leaves alone\n"

assert_silent "a repo README" \
  "$(run_edit /repo/README.md "" "Built this way so that it stays portable.")"
assert_silent "a shell script under the agents tree" \
  "$(run_edit /repo/agents/claude/hooks/some-hook.sh "" "  # so that it exits early")"
assert_silent "a Bash command" \
  "$(run_bash 'echo "so that"')"

printf "\n%d passed, %d failed\n" "$pass" "$fail"
[ "$fail" -eq 0 ]
