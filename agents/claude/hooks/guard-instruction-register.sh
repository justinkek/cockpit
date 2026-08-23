#!/usr/bin/env bash

set -f
input="$(cat)"

command -v jq >/dev/null 2>&1 || exit 0

tool_name="$(printf '%s' "$input" | jq --raw-output '.tool_name // empty')"
case "$tool_name" in
  Edit|Write) ;;
  *) exit 0 ;;
esac

REASON_FORMS='so I can|so that|so as to|in order that|This is to |that is why|which is why|the whole reason|^Why: '

holds_instructions() {
  case "$1" in
    *.md) ;;
    *) return 1 ;;
  esac
  case "$1" in
    *AGENTS.md|*CLAUDE.md|*SKILL.md) return 0 ;;
    *agents/*) return 0 ;;
  esac
  return 1
}

scan() {
  [ -n "$1" ] || return 0
  printf '%s\n' "$1" \
    | grep --only-matching --extended-regexp "$REASON_FORMS" \
    | sort --unique
}

file_path="$(printf '%s' "$input" | jq --raw-output '.tool_input.file_path // empty')"
holds_instructions "$file_path" || exit 0

added="$(printf '%s' "$input" | jq --raw-output '.tool_input.new_string // .tool_input.content // empty')"
removed="$(printf '%s' "$input" | jq --raw-output '.tool_input.old_string // empty')"

[ -n "$added" ] || exit 0

offences="$(comm -23 <(scan "$added") <(scan "$removed"))"

[ -n "$offences" ] || exit 0

offending_forms="$(printf '%s\n' "$offences" | tr '\n' ',' | sed 's/,$//')"

reason="Reason clause denied in ${file_path} — newly added form(s): ${offending_forms}. An instruction states the rule and never why the rule was wanted: keep the instruction, delete the clause, then retry. A clause naming what does not count as following the rule is not a reason - rewrite it to read as the rule it is rather than deleting it. There is no escape hatch — do not ask, do not work around this deny."

jq -nc --arg r "$reason" \
  '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'
exit 0
