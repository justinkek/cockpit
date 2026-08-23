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

emit() {
  if command -v jq >/dev/null 2>&1; then
    jq -nc --arg r "$1" \
      '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'
  else
    printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"%s"}}\n' "$1"
  fi
}

reason="Profile directories (~/.claude*/) are sync-generated outputs. Read from the dotfiles repo (agents/claude/) or ~/.claude-shared/ instead."

# ~/.claude-shared is a symlink into the dotfiles repo — always allowed.
# ~/.claude-logs is not sync-generated — always allowed.
# ~/.agents-shared is a symlink into the dotfiles repo — always allowed.
# <profile>/projects/ holds session transcripts, which the sync neither writes
# nor regenerates — the reason this hook gives for denying does not cover them,
# and a hook that parses a transcript cannot be written without reading one.
is_allowed() {
  case "$1" in
    "$HOME"/.claude-shared|"$HOME"/.claude-shared/*) return 0 ;;
    "$HOME"/.claude-logs|"$HOME"/.claude-logs/*) return 0 ;;
    "$HOME"/.agents-shared|"$HOME"/.agents-shared/*) return 0 ;;
  esac
  is_transcript "$1"
}

is_transcript() {
  local rest="${1#"$HOME"/}" profile
  profile="${rest%%/*}"
  case "$profile" in
    .claude|.claude-*) ;;
    *) return 1 ;;
  esac
  case "${rest#"$profile"/}" in
    projects/*) return 0 ;;
  esac
  return 1
}

is_profile_dir() {
  case "$1" in
    "$HOME"/.claude|"$HOME"/.claude/*) return 0 ;;
    "$HOME"/.claude-*|"$HOME"/.claude-*/*) return 0 ;;
  esac
  return 1
}

if [ "$tool" = "Read" ]; then
  [ -n "$fp" ] || exit 0
  is_allowed "$fp" && exit 0
  is_profile_dir "$fp" && emit "$reason"
  exit 0
fi

if [ "$tool" = "Bash" ]; then
  [ -n "$cmd" ] || exit 0
  home_pattern="(\\\$HOME|~|$(printf '%s' "$HOME" | sed 's/[][\.*^$\/]/\\&/g'))"
  printf '%s' "$cmd" | grep --quiet --extended-regexp "$home_pattern"'/\.claude(/|[[:space:]]|"|'"'"'|$)' || \
  printf '%s' "$cmd" | grep --quiet --extended-regexp "$home_pattern"'/\.claude-' || exit 0
  printf '%s' "$cmd" | grep --quiet --extended-regexp '/\.claude/worktrees(/|[[:space:]]|"|'"'"'|$)' && exit 0
  printf '%s' "$cmd" | grep -q '/\.claude-shared' && exit 0
  printf '%s' "$cmd" | grep -q '/\.claude-logs' && exit 0
  printf '%s' "$cmd" | grep -q '/\.agents-shared' && exit 0
  printf '%s' "$cmd" | grep -qE '/\.claude[^/]*/projects/' && exit 0
  emit "$reason"
  exit 0
fi
