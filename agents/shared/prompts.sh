#!/usr/bin/env bash
#
# prompts.sh — the y/N gate every concern's sync.*.sh puts in front of a write.
#
# Sourced by the orchestrator via $BASH_ENV — never executed, and never sourced
# by a concern itself. sync.sh exports BASH_ENV before running each worker, so
# bash sources this file before the worker's own first line: a new concern
# inherits confirm() with no prelude to copy, and so no /dev/tty block to get
# wrong. That inheritance is also why the workers are not executable — run one
# by its own path and confirm() would be undefined.
#
# The behaviour twin of accounts.sh: accounts.sh is the single source of truth
# for shared DATA (ACCOUNTS, acct_dir); this file is the single source of truth
# for shared BEHAVIOUR.
#
# It lives in agents/shared rather than agents/claude because only that tree is
# reachable from both sides: ~/.agents-shared/prompts.sh resolves for the Claude
# workers and the Codex workers alike.

# confirm INDENT PROMPT — ask for y/N on the controlling terminal.
#
# Returns 0 to proceed, 1 to skip. Answers yes WITHOUT asking when $ASSUME_YES
# is 1, or when there is no terminal to ask on (agent session, hook, CI).
#
# That second case is the reason this function exists. Every caller used to read
# /dev/tty inline and swallow the failure with `|| ans=""`, so a run with no
# terminal printed "skipped" for every account and still exited 0 — an unapplied
# config looked applied. An unattended --apply must apply.
confirm() {
  local indent="$1" prompt="$2" ans=""

  if [ "${ASSUME_YES:-0}" -eq 1 ]; then
    return 0
  fi

  # Probe in a subshell: a failed redirection on `exec` can kill the shell.
  if ! ( : </dev/tty ) 2>/dev/null; then
    printf '%s%s [y/N] (no terminal - applying unattended)\n' "$indent" "$prompt"
    return 0
  fi

  printf '%s%s [y/N] ' "$indent" "$prompt"
  read -r ans </dev/tty || ans=""

  case "$ans" in
    y|Y|yes|YES) return 0 ;;
    *)           return 1 ;;
  esac
}
