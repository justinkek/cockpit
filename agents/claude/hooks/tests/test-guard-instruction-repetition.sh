#!/usr/bin/env bash

HOOKS="$(cd "$(dirname "$0")/.." && pwd)"
HOOK="$HOOKS/guard-instruction-repetition.sh"
REPO="$(cd "$HOOKS/../../.." && pwd)"

HELD="Search the words the behaviour would be written in, not the ticket's own wording - whoever put it in place phrased it their way, not the way the ticket was raised."
HOLDER="agents/claude/templates/already-done-check.md"
FENCED="$(printf '```\n%s\n```\n' "$HELD")"
WRAPPED="$(printf 'Search the words the behaviour would be written in, not the\nticket'"'"'s own wording - whoever put it in place phrased it their way, not\nthe way the ticket was raised.\n')"

PROBE="$REPO/.claude/worktrees/probe-$$"
trap 'rm -rf "$PROBE"' EXIT
mkdir -p "$PROBE/agents/shared" "$PROBE/agents/claude/templates"
printf 'A sentence that lives only in this probe worktree and nowhere in the checkout around it.\n' \
  > "$PROBE/agents/claude/templates/probe.md"

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

assert_names_holder() {
  local label="$1" output="$2"
  if printf '%s' "$output" | grep --quiet --fixed-strings "$HOLDER"; then
    printf "  OK  %s\n" "$label"
    pass=$((pass + 1))
  else
    printf "  KO  %s — expected '%s' to be named, got '%s'\n" "$label" "$HOLDER" "$output"
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

printf "Test group: a sentence another instruction file already holds is denied\n"

assert_denies "lifted from a template into the core" \
  "$(run_edit "$REPO/agents/shared/base.AGENTS.md" "" "$HELD")"
assert_denies "carried into a new skill" \
  "$(run_write "$REPO/agents/claude/skills/x/SKILL.md" "$HELD")"
assert_denies "rewrapped across different line breaks" \
  "$(run_edit "$REPO/agents/shared/base.AGENTS.md" "" "$WRAPPED")"
assert_denies "held by a sibling inside the same worktree" \
  "$(run_edit "$PROBE/agents/shared/base.AGENTS.md" "" "A sentence that lives only in this probe worktree and nowhere in the checkout around it.")"

printf "\nTest group: the refusal names the file that already holds it\n"

assert_names_holder "the holder is named" \
  "$(run_edit "$REPO/agents/shared/base.AGENTS.md" "" "$HELD")"

printf "\nTest group: what the guard lets through\n"

assert_silent "the file that already holds it, edited" \
  "$(run_edit "$REPO/$HOLDER" "" "$HELD")"
assert_silent "a worktree file whose sentence only the main checkout holds" \
  "$(run_edit "$PROBE/agents/shared/base.AGENTS.md" "" "$HELD")"
assert_silent "a sentence under the character floor" \
  "$(run_edit "$REPO/agents/shared/base.AGENTS.md" "" "Prefer numbered lists.")"
assert_silent "a sentence carried through an edit untouched" \
  "$(run_edit "$REPO/agents/shared/base.AGENTS.md" "$HELD" "$HELD")"
assert_silent "the same sentence inside a fenced code block" \
  "$(run_edit "$REPO/agents/shared/base.AGENTS.md" "" "$FENCED")"
assert_silent "a sentence nothing else has written" \
  "$(run_edit "$REPO/agents/shared/base.AGENTS.md" "" "A brand new sentence that nothing anywhere in this repository has written down before.")"
assert_silent "the repo root instructions, whose CLAUDE.md is a symlink to them" \
  "$(run_edit "$REPO/AGENTS.md" "" "$(sed -n '3,12p' "$REPO/AGENTS.md")")"
assert_silent "an existing file rewritten whole with what it already says" \
  "$(run_write "$REPO/marketplace/plugins/cockpit/skills/ticket:2:tr/SKILL.md" "$(cat "$REPO/marketplace/plugins/cockpit/skills/ticket:2:tr/SKILL.md")")"

printf "\nTest group: files and tools the guard leaves alone\n"

assert_silent "a repo README" \
  "$(run_edit "$REPO/README.md" "" "$HELD")"
assert_silent "a shell script under the agents tree" \
  "$(run_edit "$REPO/agents/claude/hooks/some-hook.sh" "" "$HELD")"
assert_silent "a Bash command" \
  "$(run_bash "echo '$HELD'")"

printf "\n%d passed, %d failed\n" "$pass" "$fail"
[ "$fail" -eq 0 ]
