#!/usr/bin/env bash

input="$(cat)"
tool="$(printf '%s' "$input" | jq -r '.tool_name // empty' 2>/dev/null)"
cmd="$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null)"

[ "$tool" = "Bash" ] || exit 0
[ -n "$cmd" ] || exit 0

deny() {
  jq -nc --arg r "$1" \
    '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'
  exit 0
}

reason="CLAUDE_SESSION_ID is not a shell variable. The session id is in \$CLAUDE_CODE_SESSION_ID, or in hook stdin JSON via .session_id."

# Match variable expansion ($CLAUDE_SESSION_ID, ${CLAUDE_SESSION_ID})
# or env lookup (printenv CLAUDE_SESSION_ID).
case "$cmd" in
  *\$CLAUDE_SESSION_ID*|*\$\{CLAUDE_SESSION_ID\}*) deny "$reason" ;;
  *printenv*CLAUDE_SESSION_ID*) deny "$reason" ;;
esac

exit 0
