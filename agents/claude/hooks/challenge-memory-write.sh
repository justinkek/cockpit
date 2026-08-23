#!/usr/bin/env bash

input="$(cat)"

if command -v jq >/dev/null 2>&1; then
  tool="$(printf '%s' "$input" | jq -r '.tool_name // empty')"
  fp="$(printf '%s' "$input" | jq -r '.tool_input.file_path // empty')"
  cmd="$(printf '%s' "$input" | jq -r '.tool_input.command // empty')"
else
  tool="$(printf '%s' "$input" | sed -n 's/.*"tool_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')"
  fp="$(printf '%s' "$input" | sed -n 's/.*"file_path"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')"
  cmd="$(printf '%s' "$input" | sed -n 's/.*"command"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')"
fi

is_memory_path() {
  case "$1" in
    *.claude-*/*/memory/*) return 0 ;;
    *) return 1 ;;
  esac
}

case "$tool" in
  Edit|Write) is_memory_path "$fp"  || exit 0 ;;
  Bash)       is_memory_path "$cmd" || exit 0 ;;
  *)          exit 0 ;;
esac

reason="Memory access denied. The auto-memory system is disabled — route content to the correct dotfiles location instead: shared rules or behavior instructions → ~/.agents-shared/base.AGENTS.md; project conventions → ./AGENTS.md. If it fits neither, it probably does not need to be persisted. Do not retry or work around this deny."

if command -v jq >/dev/null 2>&1; then
  jq -nc --arg r "$reason" \
    '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'
else
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"%s"}}\n' "$reason"
fi
exit 0
