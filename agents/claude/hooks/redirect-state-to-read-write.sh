#!/usr/bin/env bash

input="$(cat)"

if command -v jq >/dev/null 2>&1; then
  cmd="$(printf '%s' "$input" | jq -r '.tool_input.command // empty')"
else
  cmd="$(printf '%s' "$input" | sed -n 's/.*"command"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')"
fi

[ -n "$cmd" ] || exit 0

printf '%s' "$cmd" | grep -q '\.local/state/' || exit 0

printf '%s' "$cmd" | grep -q 'ticket-register' && exit 0

# Allow pure mkdir commands (no read/write of file contents)
printf '%s' "$cmd" | grep -qE '^mkdir[[:space:]]' && exit 0

# Allow trusted scripts — .local/state/ in their arguments is not a file operation
printf '%s' "$cmd" | grep -qE '\.claude-shared/' && exit 0

if command -v jq >/dev/null 2>&1; then
  jq -nc '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:"Use the Read or Write tool for files under ~/.local/state/, not Bash. The Read/Write allowlist covers this path; Bash triggers unnecessary permission prompts."}}'
else
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"Use the Read or Write tool for files under ~/.local/state/, not Bash."}}\n'
fi
