#!/usr/bin/env bash

input="$(cat)"

if command -v jq >/dev/null 2>&1; then
  tool="$(printf '%s' "$input" | jq --raw-output '.tool_name // empty')"
else
  tool="$(printf '%s' "$input" | sed -n 's/.*"tool_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')"
fi

case "$tool" in
  mcp__*) ;;
  *) exit 0 ;;
esac

server="${tool#mcp__}"
server="${server%%__*}"
action="${tool##*__}"
action="$(printf '%s' "$action" | tr '[:upper:]' '[:lower:]')"

case "$(printf '%s' "$server" | tr '[:upper:]' '[:lower:]')" in
  *notion*) ;;
  *)
    case "$action" in notion-*) ;; *) exit 0 ;; esac
    ;;
esac

action="${action#notion-}"
action="${action#api-}"

case "$action" in
  get-*|get_*|list-*|list_*|fetch*|search*|query-*|query_*|read-*|read_*|retrieve-*|retrieve_*|download-*|download_*|wait-*|check-*|show-*) exit 0 ;;
esac

printf '%s' "$action" | grep --quiet --extended-regexp '(^|[-_])(create|update|move|duplicate|delete|upload|restore|comment|comments|append|insert|replace|archive|post|patch|put|send|spawn|stop|convert)([-_]|$)' || exit 0

reason="Notion is read-only: $tool writes to it, and nothing in this flow may. The cockpit board is local - make this change with \$HOME/.cockpit/scripts/board-card (create, set, section, comment, move, walk) instead."
if command -v jq >/dev/null 2>&1; then
  jq --null-input --compact-output --arg reason "$reason" \
    '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$reason}}'
else
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"%s"}}\n' "$reason"
fi
exit 0
