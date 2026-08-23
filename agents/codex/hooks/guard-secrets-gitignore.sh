#!/usr/bin/env bash
#
# guard-secrets-gitignore.sh — Codex adapter for env-secret + gitignore policy.
#
# PreToolUse guard for Codex's apply_patch tool. Extracts file paths from the
# unified diff in tool_input.command, evaluates each against the shared policy,
# and denies the entire patch if any path triggers a secret or gitignore gate.

input="$(cat)"

if command -v jq >/dev/null 2>&1; then
  cwd="$(printf '%s'  "$input" | jq -r '.cwd // empty')"
  command_text="$(printf '%s' "$input" | jq -r '.tool_input.command // empty')"
else
  cwd="$(printf '%s'  "$input" | sed -n 's/.*"cwd"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')"
  command_text="$(printf '%s' "$input" | sed -n 's/.*"command"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')"
fi

[ -n "$command_text" ] || exit 0

cwd="${cwd:-$PWD}"

emit() {
  if command -v jq >/dev/null 2>&1; then
    jq -nc --arg d "$1" --arg r "$2" \
      '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:$d,permissionDecisionReason:$r}}'
  else
    printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"%s","permissionDecisionReason":"%s"}}\n' "$1" "$2"
  fi
}

policy="$(cd "$(dirname "$0")" && pwd -P)/../../shared/hooks/guard-secrets-policy.sh"

if [ ! -x "$policy" ]; then
  emit deny "Shared policy script missing: guard-secrets-policy.sh. Failing closed."
  exit 0
fi

paths="$(printf '%s' "$command_text" | grep -E '^\+\+\+ b/' | sed 's|^+++ b/||')"

if [ -z "$paths" ]; then
  emit deny "Could not extract file paths from apply_patch command. Failing closed."
  exit 0
fi

while IFS= read -r rel_path; do
  [ -n "$rel_path" ] || continue
  case "$rel_path" in
    /*) abs_path="$rel_path" ;;
    *)  abs_path="$cwd/$rel_path" ;;
  esac

  decision="$("$policy" "write" "$abs_path" "${cwd:-.}" "apply_patch")"

  case "$decision" in
    deny\ *) emit deny "${decision#deny }"; exit 0 ;;
    ask\ *)  emit ask  "${decision#ask }";  exit 0 ;;
    "")      ;;
    *)       emit deny "Unexpected policy output. Failing closed."; exit 0 ;;
  esac
done <<< "$paths"

exit 0
