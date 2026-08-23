#!/usr/bin/env bash

mode="$1"
input="$(cat)"

command -v jq >/dev/null 2>&1 || exit 0

session_id="$(printf '%s' "$input" | jq --raw-output '.session_id // empty')"
[ -n "$session_id" ] || exit 0

STATE_DIR="${TICKET_STATE_DIR:-$HOME/.local/state/claude-ticket-sessions}"
marker="$STATE_DIR/$session_id.skill-guidance"

if [ "$mode" = "record" ]; then
  skill="$(printf '%s' "$input" | jq --raw-output '.tool_input.skill // empty')"
  case "${skill##*:}" in
  writing-great-skills)
    mkdir -p "$STATE_DIR"
    : > "$marker"
    ;;
  esac
  exit 0
fi

writes_a_skill_file() {
  printf '%s' "$1" | grep --quiet --extended-regexp '>[[:space:]]*[^[:space:]|;&]*SKILL\.md' && return 0
  printf '%s' "$1" | grep --quiet --extended-regexp '(sed|perl)[[:space:]][^|;&]*(--in-place|-i)[^|;&]*SKILL\.md' && return 0
  printf '%s' "$1" | grep --quiet --extended-regexp '(tee|cp|mv|install)[[:space:]][^|;&]*SKILL\.md' && return 0
  return 1
}

tool_name="$(printf '%s' "$input" | jq --raw-output '.tool_name // empty')"
case "$tool_name" in
Edit | Write)
  file_path="$(printf '%s' "$input" | jq --raw-output '.tool_input.file_path // empty')"
  case "${file_path##*/}" in
  SKILL.md) ;;
  *) exit 0 ;;
  esac
  refusal_subject="$file_path"
  ;;
Bash)
  command_line="$(printf '%s' "$input" | jq --raw-output '.tool_input.command // empty')"
  writes_a_skill_file "$command_line" || exit 0
  refusal_subject="the SKILL.md this command writes"
  ;;
*) exit 0 ;;
esac

[ -f "$marker" ] && exit 0

reason="Skill edit denied in ${refusal_subject} — the writing-great-skills skill has not run in this session. Invoke it, draft the change from what it says, then retry. There is no escape hatch — do not ask, do not work around this deny."

jq --null-input --compact-output --arg r "$reason" \
  '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'
exit 0
