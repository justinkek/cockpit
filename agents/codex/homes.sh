#!/usr/bin/env bash
#
# homes.sh — single source of truth for the Codex home taxonomy.
#
# Sourced (not executed) by agents/codex/sync.sh and by every concern's
# sync.*.sh. Defines:
#   CODEX_HOMES      — ordered, deterministic list of home names to sync.
#   codex_home_dir() — maps a home name to its Codex config dir.

CODEX_HOMES=(codex-cockpit)

codex_home_dir() {
  printf '%s' "$HOME/.$1"
}

codex_home_reached_without_a_wrapper() {
  [ "$1" = "codex" ]
}

codex_home_works_the_ticket_board() {
  ! codex_home_reached_without_a_wrapper "$1"
}

codex_home_from_environment() {
  if [ -n "${CODEX_HOME:-}" ] && [ -n "${CODEX_HOME_NAME:-}" ]; then
    return 0
  fi
  echo "run this through agents/codex/sync.sh — it sets CODEX_HOME and CODEX_HOME_NAME" >&2
  exit 1
}

if [ -z "${BASH_SOURCE:-}" ]; then
  echo "homes.sh: must be sourced from bash (per-user overlay would be skipped)" >&2
  return 1 2>/dev/null || exit 1
fi
__homes_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[ -f "$__homes_dir/homes.local.sh" ] && source "$__homes_dir/homes.local.sh"
unset __homes_dir

for __home in "${CODEX_HOMES[@]}"; do
  if [ "$__home" = "codex-vanilla" ]; then
    echo "homes.sh: 'codex-vanilla' names the home that runs with none of this repo's config, so it must never be synced" >&2
    return 1 2>/dev/null || exit 1
  fi
done
unset __home
