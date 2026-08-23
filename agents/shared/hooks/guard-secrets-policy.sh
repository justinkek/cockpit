#!/usr/bin/env bash
#
# guard-secrets-policy.sh — shared env-secret deny + gitignore write gate.
#
# Agent-neutral: no JSON parsing, no transport format, no tool names.
#
# Interface:
#   $1 = operation ("read" | "write")
#   $2 = target path (absolute)
#   $3 = cwd
#   $4 = label (optional; human-readable name for the operation — used in
#        reason text only, never interpreted)
#
# Output on stdout (one line):
#   deny <reason>   — hard block
#   ask <reason>    — prompt user for one-off approval
#   (empty)         — defer to normal permission flow

op="$1" fp="$2" cwd="${3:-.}" label="${4:-$1}"

[ -n "$fp" ] || exit 0

bn="${fp##*/}"

# Job 1: env-secret default-deny (reads and writes)
case "$bn" in
  .env|.env.*)
    case "$bn" in
      .env.example|.env.sample|.env.template|.env.dist) ;;
      *)
        printf 'deny Refusing %s on %s: env files are treated as secrets (default-deny). Readable example names: .env.example, .env.sample, .env.template, .env.dist.\n' "$label" "$bn"
        exit 0 ;;
    esac
    ;;
esac

# Job 2: gitignore write-visibility (writes only)
case "$op" in
  write)
    if git -C "$cwd" check-ignore -q -- "$fp" 2>/dev/null; then
      printf 'ask %s is gitignored — edits to it won'\''t appear in git status, so the change would be invisible and hard to revert. Approve to proceed.\n' "$fp"
      exit 0
    fi
    ;;
esac

exit 0
