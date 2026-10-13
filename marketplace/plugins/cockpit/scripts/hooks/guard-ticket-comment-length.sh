#!/usr/bin/env bash

input="$(cat)"

command -v jq >/dev/null 2>&1 || exit 0

. "${CLAUDE_SHARED_DIR:-$HOME/.claude-shared}/hooks/hook-argv-lib.sh"

[ "$(printf '%s' "$input" | jq --raw-output '.tool_name // empty')" = "Bash" ] || exit 0
cmd="$(printf '%s' "$input" | jq --raw-output '.tool_input.command // empty')"
printf '%s' "$cmd" | grep --quiet 'board-card' || exit 0
[ "$(hook_argv_after "$cmd" board-card | sed -n 1p)" = "comment" ] || exit 0

body="$(hook_heredoc_body "$cmd")"
[ -n "$body" ] || exit 0

opening="$(printf '%s\n' "$body" | grep --max-count 1 '[^[:space:]]')"
case "$opening" in
  *'**Blocked**'*|*'Back from '*|*'**On:**'*|'**[suggestion]**'*) exit 0 ;;
esac

CHARACTER_CEILING=200
length="$(printf '%s' "$body" | awk '{ total += length } END { print total + 0 }')"
[ "$length" -gt "$CHARACTER_CEILING" ] || exit 0

reason="This ticket comment runs $length characters against a ceiling of $CHARACTER_CEILING. Name what changed on the ticket; the reasoning is already on the page. The shape a reply takes is in ~/.claude-shared/templates/ticket-comment-reply.md."
jq --null-input --compact-output --arg r "$reason" \
  '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'
exit 0
