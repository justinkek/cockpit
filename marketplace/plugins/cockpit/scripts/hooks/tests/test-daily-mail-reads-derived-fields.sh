#!/usr/bin/env bash

SCRIPTS="$(cd "$(dirname "$0")/../.." && pwd)"
DAILY_MAIL="$SCRIPTS/../skills/daily-mail/SKILL.md"
export CLAUDE_SHARED_DIR="$(cd "$SCRIPTS/../../../../agents/claude" && pwd)"
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

export COCKPIT_BOARD_DIR="$TMPDIR/board"
export TICKET_CLAIM_LOCK_DIR="$TMPDIR/claims"
export TICKET_STATE_DIR="$TMPDIR/state"
export CLAUDE_SESSION_ID="session-one"
export GIT_CONFIG_GLOBAL=/dev/null
export GIT_CONFIG_NOSYSTEM=1

pass=0
fail=0

assert_eq() {
  local label="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then
    printf "  OK  %s\n" "$label"
    pass=$((pass + 1))
  else
    printf "  KO  %s — expected '%s', got '%s'\n" "$label" "$expected" "$actual"
    fail=$((fail + 1))
  fi
}

stub() { bash "$SCRIPTS/board-card" "$@"; }

printf "Test group: daily-mail reads off list --json every field it names\n"

assert_eq "daily-mail reads the board with list --json" "yes" \
  "$(grep --fixed-strings --quiet '"$HOME/.cockpit/scripts/board-card" list --json' "$DAILY_MAIL" && echo yes || echo no)"

read_line="$(grep '^Keep the cards whose `status`' "$DAILY_MAIL" | head -n 1)"
fields="$(printf '%s' "${read_line%% off each*}" | grep --only-matching --extended-regexp '`[a-z_]+`' | tr -d '`')"
assert_eq "it reads overrunning" "yes" "$(printf '%s\n' "$fields" | grep --quiet --line-regexp overrunning && echo yes || echo no)"
assert_eq "it reads days_in_column" "yes" "$(printf '%s\n' "$fields" | grep --quiet --line-regexp days_in_column && echo yes || echo no)"

stub init >/dev/null
stub create --kind project --name Home >/dev/null
stub create --kind epic --name Home --project PRJ-1 >/dev/null
card="$(stub create --epic EPIC-1 --name 'Sprint card')"
stub move "$card" "In Dev" >/dev/null
listed="$(stub list --json | jq --compact-output --arg id "$card" '.[] | select(.id == $id)')"
missing="$(printf '%s\n' "$fields" | while read -r name; do
  [ -n "$name" ] || continue
  printf '%s' "$listed" | jq --exit-status --arg key "$name" 'has($key)' >/dev/null || printf '%s ' "$name"
done)"
assert_eq "every field it names is one list --json gives a card in a sprint column" "" "$missing"

printf "\nTest group: the amber light reads the computed values\n"

amber="$(grep --fixed-strings 'Off track' "$DAILY_MAIL" | head -n 1)"
assert_eq "an overrunning card turns the light amber" "yes" "$(printf '%s' "$amber" | grep --quiet --fixed-strings '`overrunning`' && echo yes || echo no)"
assert_eq "the values are taken as board-card gives them" "yes" \
  "$(grep --fixed-strings --quiet 'never work either out from the card' "$DAILY_MAIL" && echo yes || echo no)"
assert_eq "the explanation gives an overrunning card's days in its column" "yes" \
  "$(grep --fixed-strings 'For 🟠' "$DAILY_MAIL" | grep --quiet --fixed-strings '`days_in_column`' && echo yes || echo no)"

printf "\n%d passed, %d failed\n" "$pass" "$fail"
[ "$fail" -eq 0 ]
