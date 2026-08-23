#!/usr/bin/env bash

input="$(cat)"

if command -v jq >/dev/null 2>&1; then
  tool="$(printf '%s' "$input" | jq -r '.tool_name // empty')"
  cwd="$(printf '%s'  "$input" | jq -r '.cwd // empty')"
  path="$(printf '%s' "$input" | jq -r '.tool_input.file_path // .tool_input.path // empty')"
else
  tool="$(printf '%s' "$input" | sed -n 's/.*"tool_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')"
  cwd="$(printf '%s'  "$input" | sed -n 's/.*"cwd"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')"
  path="$(printf '%s' "$input" | sed -n 's/.*"file_path"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')"
  [ -n "$path" ] || path="$(printf '%s' "$input" | sed -n 's/.*"path"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')"
fi

[ -n "$path" ] || exit 0

cwd="${cwd:-$PWD}"

emit() {
  if command -v jq >/dev/null 2>&1; then
    jq -nc --arg d "$1" --arg r "$2" \
      '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:$d,permissionDecisionReason:$r}}'
  else
    printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"%s","permissionDecisionReason":"%s"}}\n' "$1" "$2"
  fi
}

case "$tool" in
  Edit|Write) op="write" ;;
  *)          op="read" ;;
esac

policy="$(cd "$(dirname "$0")" && pwd -P)/../../shared/hooks/confine-to-repo-policy.sh"

if [ ! -x "$policy" ]; then
  emit deny "Shared policy script missing: confine-to-repo-policy.sh. Failing closed."
  exit 0
fi

decision="$("$policy" "$op" "$path" "$cwd" "$tool")"

case "$decision" in
  deny\ *) emit deny "${decision#deny }" ;;
  ask\ *)  emit ask  "${decision#ask }" ;;
  "")      exit 0 ;;
  *)       emit deny "Unexpected policy output. Failing closed." ;;
esac
exit 0
