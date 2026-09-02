#!/usr/bin/env bash

cat >/dev/null

SHARED_DIRECTORY="${CLAUDE_SHARED_DIR:-$HOME/.claude-shared}"

resolved_shared_directory="$(realpath "$SHARED_DIRECTORY" 2>/dev/null)" || exit 0
DOTFILES="$(cd "$resolved_shared_directory/../.." 2>/dev/null && pwd)" || exit 0

REPOSITORY="$DOTFILES"
if [ -n "$1" ]; then
  REPOSITORY="$(git -C "$1" rev-parse --show-toplevel 2>/dev/null)" || exit 0
fi

git -C "$REPOSITORY" rev-parse --git-dir >/dev/null 2>&1 || exit 0

default_branch="$(git -C "$REPOSITORY" symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null)"
default_branch="${default_branch#origin/}"
current_branch="$(git -C "$REPOSITORY" rev-parse --abbrev-ref HEAD 2>/dev/null)"

if [ -n "$default_branch" ] && [ "$current_branch" != "$default_branch" ]; then
  echo "[main] not pulled - the checkout is on $current_branch, not $default_branch."
  exit 0
fi

if ! git -C "$REPOSITORY" fetch --quiet origin 2>/dev/null; then
  echo "[main] fetch failed - main is whatever the last fetch left."
  exit 0
fi

commits_behind="$(git -C "$REPOSITORY" rev-list --count HEAD..@{u} 2>/dev/null)" || exit 0
[ "${commits_behind:-0}" -gt 0 ] || exit 0

if [ -n "$(git -C "$REPOSITORY" status --porcelain)" ]; then
  echo "[main] $commits_behind behind, not pulled - the checkout has uncommitted changes."
  exit 0
fi

if ! git -C "$REPOSITORY" merge --ff-only --quiet '@{u}' 2>/dev/null; then
  echo "[main] $commits_behind behind, not pulled - main has diverged from its remote."
  exit 0
fi

if [ "$REPOSITORY" != "$DOTFILES" ]; then
  echo "[main] pulled $commits_behind in $REPOSITORY."
  exit 0
fi

if ! "$SHARED_DIRECTORY/sync.sh" --apply --yes >/dev/null 2>&1; then
  echo "[main] pulled $commits_behind - the generated config could not be rebuilt from it."
  exit 0
fi

echo "[main] pulled $commits_behind - the generated config is rebuilt from it."
exit 0
