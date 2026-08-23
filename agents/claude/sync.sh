#!/usr/bin/env bash
#
# sync.sh — top-level orchestrator for ~/.claude-shared.
#
# For each concern subfolder, runs its sync action (<concern>/sync.*.sh) and
# passes all arguments through. Today: settings/sync.settings.sh and
# claudemd/sync.claudemd.sh. Drop a new concern folder with a sync.*.sh and it
# gets picked up here automatically.
#
# This is the ONLY way to run a concern — the workers are not executable, and
# they get confirm() from here rather than sourcing it themselves.
#
# Usage: sync.sh [concern...] [args...]
#   bare words  : concerns to run (default: all of them), e.g. sync.sh settings
#   -* args     : forwarded to every concern that runs, e.g. --check
#
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Every worker inherits confirm() before its own first line: bash sources
# $BASH_ENV for non-interactive shells. A new concern folder gets the y/N gate
# with no prelude to copy — and so no /dev/tty block to get wrong.
export BASH_ENV="${AGENTS_SHARED_DIR:-$HOME/.agents-shared}/prompts.sh"

# Bare words select concerns; flags forward to every worker that runs.
concerns=(); args=()
for arg in "$@"; do
  case "$arg" in
    -*) args+=("$arg") ;;
    *)  concerns+=("$arg") ;;
  esac
done

shopt -s nullglob
actions=()
if [ "${#concerns[@]}" -gt 0 ]; then
  for c in "${concerns[@]}"; do actions+=("$DIR/$c"/sync.*.sh); done
else
  actions=("$DIR"/*/sync.*.sh)
fi
shopt -u nullglob

# An unknown concern name globs to nothing, so it lands here too.
if [ "${#actions[@]}" -eq 0 ]; then
  echo "sync.sh: no concern actions (*/sync.*.sh) found in $DIR" >&2
  exit 1
fi

# Concern-header color — only when stdout is a terminal.
if [ -t 1 ]; then
  C_RESET=$'\033[0m'; C_HDR=$'\033[1;35m'   # bold magenta
else
  C_RESET=''; C_HDR=''
fi

status=0
first=1
for action in "${actions[@]}"; do
  [ "$first" -eq 1 ] && first=0 || echo
  name="$(basename "$(dirname "$action")")"
  echo "${C_HDR}=== $name ===${C_RESET}"
  bash "$action" "${args[@]+"${args[@]}"}" || status=$?
done
exit "$status"
