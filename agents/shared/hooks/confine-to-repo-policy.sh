#!/usr/bin/env bash
#
# confine-to-repo-policy.sh — shared worktree confinement policy.
#
# Agent-neutral: no JSON parsing, no transport format, no tool names.
#
# Interface:
#   $1 = operation ("read" | "write")
#   $2 = target path (absolute)
#   $3 = cwd
#   $4 = label (optional; human-readable name for the operation, e.g. the
#        agent's tool name — used in reason text only, never interpreted)
#
# Output on stdout (one line):
#   deny <reason>   — hard block
#   ask <reason>    — prompt user for one-off approval
#   (empty)         — defer to normal permission flow

op="$1" target_path="$2" cwd="${3:-$PWD}" label="${4:-$1}"

[ -n "$target_path" ] || exit 0

canonical() {
  local p="$1" dir base tail=""
  case "$p" in
    "~")    p="$HOME" ;;
    "~/"*)  p="$HOME/${p#\~/}" ;;
  esac
  case "$p" in /*) ;; *) p="$cwd/$p" ;; esac
  dir="$p"
  while [ ! -d "$dir" ]; do
    base="$(basename "$dir")"; dir="$(dirname "$dir")"
    tail="$base${tail:+/}$tail"
    [ "$dir" = "/" ] && break
  done
  if cd "$dir" 2>/dev/null; then
    dir="$(pwd -P)"
    [ -n "$tail" ] && printf '%s/%s' "$dir" "$tail" || printf '%s' "$dir"
  else
    printf '%s' "$p"
  fi
}

repo="$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null)"
[ -n "$repo" ] || exit 0
repo="$(cd "$repo" 2>/dev/null && pwd -P || printf '%s' "$repo")"

# Absolute path before symlink resolution (tilde/relative expanded, symlinks intact).
orig_abs="$target_path"
case "$orig_abs" in
  "~")    orig_abs="$HOME" ;;
  "~/"*)  orig_abs="$HOME/${orig_abs#\~/}" ;;
esac
case "$orig_abs" in /*) ;; *) orig_abs="$cwd/$orig_abs" ;; esac

target="$(canonical "$target_path")"

case "$target" in
  "$repo"|"$repo"/*) exit 0 ;;
esac

# Claude Code's scratchpad and background-task output directories are outside
# the repo by design. Allow read and write access so agents don't get prompted
# for temp files or for the output of a task they started themselves.
case "$target" in
  /private/tmp/claude-*/scratchpad|/private/tmp/claude-*/scratchpad/*) exit 0 ;;
  /tmp/claude-*/scratchpad|/tmp/claude-*/scratchpad/*)                exit 0 ;;
  /private/tmp/claude-*/tasks|/private/tmp/claude-*/tasks/*)          exit 0 ;;
  /tmp/claude-*/tasks|/tmp/claude-*/tasks/*)                          exit 0 ;;
esac

# Agent state lives outside the repo by design (ticket sessions, cockpit cache).
case "$target" in
  "$HOME/.local/state/cockpit"|"$HOME/.local/state/cockpit"/*) exit 0 ;;
  "$HOME/.local/state/claude-ticket-sessions"|"$HOME/.local/state/claude-ticket-sessions"/*) exit 0 ;;
esac

case "$op" in
  write)
    printf 'deny Refusing %s outside the current worktree. Writes are confined to %s; the main repo and sibling worktrees are read-only from here. Target: %s.\n' "$label" "$repo" "$target"
    exit 0 ;;
esac

# Agent configuration directories — read access (writes already denied above).
# Check both canonical and original paths: symlinks like ~/.claude-shared
# resolve outside $HOME/.claude-* but should still be allowed.
case "$target" in
  "$HOME"/.claude|"$HOME"/.claude/*) exit 0 ;;
  "$HOME"/.claude-*|"$HOME"/.claude-*/*) exit 0 ;;
  "$HOME"/.agents-shared|"$HOME"/.agents-shared/*) exit 0 ;;
esac
case "$orig_abs" in
  "$HOME"/.claude|"$HOME"/.claude/*) exit 0 ;;
  "$HOME"/.claude-*|"$HOME"/.claude-*/*) exit 0 ;;
  "$HOME"/.agents-shared|"$HOME"/.agents-shared/*) exit 0 ;;
esac

while IFS= read -r line; do
  case "$line" in
    "worktree "*)
      wt="${line#worktree }"
      wtc="$(cd "$wt" 2>/dev/null && pwd -P || printf '%s' "$wt")"
      case "$target" in
        "$wtc"|"$wtc"/*) exit 0 ;;
      esac ;;
  esac
done < <(git -C "$cwd" worktree list --porcelain 2>/dev/null)

# Images pasted in chat land in Claude's temp directory.
case "$target" in
  /private/tmp/claude-*|/tmp/claude-*)
    case "$target" in
      *.png|*.jpg|*.jpeg|*.gif|*.webp|*.svg|*.bmp|*.tiff|*.ico) exit 0 ;;
    esac ;;
esac

printf 'ask %s target is outside this repo and its worktrees: %s. Approve to allow one-off access.\n' "$label" "$target"
exit 0
