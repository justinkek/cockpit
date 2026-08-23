#!/usr/bin/env bash

input="$(cat)"

if command -v jq >/dev/null 2>&1; then
  path="$(printf '%s' "$input" | jq -r '.tool_input.file_path // empty')"
  cwd="$(printf '%s'  "$input" | jq -r '.cwd // empty')"
else
  path="$(printf '%s' "$input" | sed -n 's/.*"file_path"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')"
  cwd="$(printf '%s'  "$input" | sed -n 's/.*"cwd"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')"
fi

[ -n "$path" ] || exit 0

cwd="${cwd:-$PWD}"
repo="$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null)"
[ -n "$repo" ] || exit 0
repo="$(cd "$repo" 2>/dev/null && pwd -P || printf '%s' "$repo")"

case "$path" in
  "~")   path="$HOME" ;;
  "~/"*) path="$HOME/${path#\~/}" ;;
esac
case "$path" in /*) ;; *) path="$cwd/$path" ;; esac

case "$path" in
  "$repo"|"$repo"/*) exit 0 ;;
esac

filename="$(basename "$path")"
case "$filename" in
  *.html|*.svg|*.png|*.jpg|*.jpeg|*.gif|*.webp|*.pdf) ;;
  *) exit 0 ;;
esac

if command -v jq >/dev/null 2>&1; then
  jq -nc --arg r "Artifacts belong in .artifacts/ inside the repo. Write to $repo/.artifacts/$filename instead." \
    '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'
else
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"Artifacts belong in .artifacts/ inside the repo. Write to %s/.artifacts/%s instead."}}\n' "$repo" "$filename"
fi
exit 0
