#!/usr/bin/env bash

input="$(cat)"

if command -v jq >/dev/null 2>&1; then
  fp="$(printf '%s' "$input" | jq -r '.tool_input.file_path // empty')"
else
  fp="$(printf '%s' "$input" | sed -n 's/.*"file_path"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')"
fi

[ -n "$fp" ] || exit 0

resolved="$(realpath "$fp" 2>/dev/null)" || resolved="$fp"

SHARED_DIR="${CLAUDE_SHARED_DIR:-$HOME/.claude-shared}"
CHECKOUT="$(cd "$(realpath "$SHARED_DIR")/../.." && pwd)"

case "$resolved" in
  "$CHECKOUT"/agents/claude/settings/*)
    "$SHARED_DIR/sync.sh" settings --apply -y >/dev/null 2>&1
    echo "[auto-sync] Settings synced to all accounts after editing ${fp##*/}."
    ;;
  "$CHECKOUT"/agents/claude/claude-md/*|"$CHECKOUT"/agents/shared/*)
    "$SHARED_DIR/sync.sh" claude-md --apply -y >/dev/null 2>&1
    echo "[auto-sync] CLAUDE.md synced to all accounts after editing ${fp##*/}."
    ;;
esac

exit 0
