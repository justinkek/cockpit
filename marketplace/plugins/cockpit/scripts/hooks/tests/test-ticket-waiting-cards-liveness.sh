#!/usr/bin/env bash

export CLAUDE_SHARED_DIR="$(cd "$(dirname "$0")/../../../../../../agents/claude" && pwd)"

SCRIPT="$(cd "$(dirname "$0")/../.." && pwd)/ticket-waiting-cards"
BOARD_CARD="$(cd "$(dirname "$0")/../.." && pwd)/board-card"
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

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

assert_contains() {
  local label="$1" expected="$2" output="$3"
  if printf '%s' "$output" | grep -qF -- "$expected"; then
    printf "  OK  %s\n" "$label"
    pass=$((pass + 1))
  else
    printf "  KO  %s — expected '%s' in output '%s'\n" "$label" "$expected" "$output"
    fail=$((fail + 1))
  fi
}

STATE_DIR="$TMPDIR/state"
mkdir -p "$STATE_DIR"
export COCKPIT_BOARD_DIR="$TMPDIR/board"
"$BOARD_CARD" init >/dev/null
"$BOARD_CARD" create --kind project --name Home >/dev/null
"$BOARD_CARD" create --kind epic --name Home --project PRJ-1 >/dev/null

now="$(date -u +%s)"
old_claim="$(TZ=UTC date -u -r "$((now - 7200))" +%Y-%m-%dT%H:%M:%SZ)"
fresh_claim="$(TZ=UTC date -u -r "$((now - 600))" +%Y-%m-%dT%H:%M:%SZ)"

card() {
  local status="$1" name="$2" session="$3" claimed_at="$4" id
  id="$("$BOARD_CARD" create --epic EPIC-1 --name "$name" --status "$status")"
  if [ -n "$session" ]; then
    "$BOARD_CARD" set "$id" session "$session" >/dev/null
    perl -pi -e "s/^claimed_at: .*/claimed_at: \"$claimed_at\"/" "$("$BOARD_CARD" path "$id")"
  fi
  printf '%s\n' "$id"
}

beating="$(card "Ready for TR by AI" "held by a live session" sess-beating "$old_claim")"
dead="$(card "Ready for TR by AI" "held by a session that went away" sess-dead "$old_claim")"
recent="$(card "Ready for BR by AI" "claimed minutes ago, no beat here" sess-elsewhere "$fresh_claim")"
free="$(card "Ready for BR by AI" "unclaimed" "" "")"
mid_br="$(card "In BR by AI" "left mid-BR" "" "")"
mid_tr="$(card "In TR by AI" "left mid-TR" "" "")"
in_dev="$(card "In Dev" "held mid-dev" sess-beating "$old_claim")"
person="$(card "In BR" "a person is reviewing it" sess-beating "$old_claim")"
backlog="$(card "Backlog" "not yet" "" "")"
blocked="$(card "Ready for BR by AI" "waiting on an answer" "" "")"
"$BOARD_CARD" set "$blocked" blocked "waiting on the person" >/dev/null
blocked_held="$(card "In Dev" "blocked mid-dev" sess-beating "$old_claim")"
"$BOARD_CARD" set "$blocked_held" blocked "waiting on the person" >/dev/null

touch "$STATE_DIR/sess-beating.alive"

run_cards() {
  TICKET_STATE_DIR="$STATE_DIR" bash "$SCRIPT" "$@" 2>&1
}

verdict_for() {
  printf '%s\n' "$1" | awk -F'\t' -v card="$2" '$1 == card { print $5 }'
}

listed() {
  printf '%s\n' "$1" | awk -F'\t' -v card="$2" '$1 == card { found = 1 } END { print found ? "listed" : "absent" }'
}

output="$(run_cards)"

printf "Test group: the verdict on each kind of claim\n"

assert_eq "a beating session keeps its claim" "live" "$(verdict_for "$output" "$beating")"
assert_eq "no beat and an old claim is expirable" "stale" "$(verdict_for "$output" "$dead")"
assert_eq "no beat but a claim under an hour old is left alone" "live" "$(verdict_for "$output" "$recent")"
assert_eq "an empty claim has no verdict to give" "-" "$(verdict_for "$output" "$free")"

printf "\nTest group: the four fields before it keep their positions\n"

line="$(printf '%s\n' "$output" | awk -F'\t' -v card="$beating" '$1 == card')"
assert_eq "the card id is first" "$beating" "$(printf '%s' "$line" | cut -f1)"
assert_eq "status is second" "Ready for TR by AI" "$(printf '%s' "$line" | cut -f2)"
assert_eq "claim is the session and when it claimed" "sess-beating $old_claim" "$(printf '%s' "$line" | cut -f3)"
assert_eq "name is fourth" "held by a live session" "$(printf '%s' "$line" | cut -f4)"
assert_eq "five fields, no more" "5" "$(printf '%s' "$line" | awk -F'\t' '{print NF}')"

printf "\nTest group: cards come in pick order\n"

assert_eq "with no rank the newest card comes first" "$in_dev" "$(printf '%s\n' "$output" | head -1 | cut -f1)"
"$BOARD_CARD" set "$dead" rank -100 >/dev/null
"$BOARD_CARD" set "$free" rank -50 >/dev/null
ranked="$(run_cards | cut -f1 | head -2 | paste -sd ' ' -)"
assert_eq "a ranked card comes before the rest, lowest rank first" "$dead $free" "$ranked"

printf "\nTest group: the bare listing covers the columns an abandoned card sits in\n"

assert_eq "a card left mid-BR is a candidate" "listed" "$(listed "$output" "$mid_br")"
assert_eq "a card left mid-TR is a candidate" "listed" "$(listed "$output" "$mid_tr")"
assert_eq "an In Dev card is a candidate" "listed" "$(listed "$output" "$in_dev")"
assert_eq "a card a person is reviewing is not" "absent" "$(listed "$output" "$person")"
assert_eq "a backlog card is not" "absent" "$(listed "$output" "$backlog")"
assert_eq "a blocked card is not, whatever column it waits in" "absent" "$(listed "$output" "$blocked")"

printf "\nTest group: --claimed-by asks which cards one session holds\n"

output="$(run_cards --claimed-by sess-beating)"
assert_eq "its card in a by-AI column" "listed" "$(listed "$output" "$beating")"
assert_eq "its card in a column a person works" "listed" "$(listed "$output" "$person")"
assert_eq "its card mid-dev" "listed" "$(listed "$output" "$in_dev")"
assert_eq "and nobody else's" "absent" "$(listed "$output" "$dead")"
assert_eq "its blocked card too, because it still holds it" "listed" "$(listed "$output" "$blocked_held")"
assert_eq "four cards, no more" "4" "$(printf '%s\n' "$output" | grep -c . | tr -d ' ')"

output="$(run_cards --claimed-by 2>&1 || true)"
assert_contains "refuses an empty session id" "needs a session id" "$output"

printf "\nTest group: no board is an error, not an empty list\n"

COCKPIT_BOARD_DIR="$TMPDIR/never-made" TICKET_STATE_DIR="$STATE_DIR" bash "$SCRIPT" >/dev/null 2>&1
assert_eq "exits with the board's no-record code" "3" "$?"

printf "\n%d passed, %d failed\n" "$pass" "$fail"
[ "$fail" -eq 0 ]
