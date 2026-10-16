#!/usr/bin/env bash

SCRIPTS="$(cd "$(dirname "$0")/../.." && pwd)"
export CLAUDE_SHARED_DIR="$(cd "$SCRIPTS/../../../../agents/claude" && pwd)"
SCRIPT="$SCRIPTS/ticket-done-usage"
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

export HOME="$TMPDIR/home"
export COCKPIT_BOARD_DIR="$TMPDIR/board"
export TICKET_CLAIM_LOCK_DIR="$TMPDIR/claims"
export TICKET_STATE_DIR="$HOME/.local/state/claude-ticket-sessions"
export CLAUDE_SESSION_ID="ticket-done-usage-test"
STATE_DIR="$TICKET_STATE_DIR"

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

register() { printf '%s\n' "$2" > "$STATE_DIR/$1.ticket"; }
record() { printf '%s' "$2" > "$STATE_DIR/$1.usage"; }
reset_state() { rm -rf "$STATE_DIR"; mkdir -p "$STATE_DIR"; }

printf "Test group: no measured usage reads as unavailable, not as zero\n"

rm -rf "$STATE_DIR"
assert_eq "with no state directory both totals are null" '{"cost_usd": null, "tokens_k": null}' "$(bash "$SCRIPT" FEAT-724)"

reset_state
register desktop-session FEAT-724
assert_eq "a session with no usage sidecar leaves both totals null" '{"cost_usd": null, "tokens_k": null}' "$(bash "$SCRIPT" FEAT-724)"

record desktop-session $'cost_usd=\ntokens_k_prev=\ntokens_k_cumul=\n'
assert_eq "a sidecar holding only empty values leaves both totals null" '{"cost_usd": null, "tokens_k": null}' "$(bash "$SCRIPT" FEAT-724)"

printf "Test group: measured usage is summed per total\n"

reset_state
register plan-session FEAT-724
record plan-session $'cost_usd=\ntokens_k_prev=40\ntokens_k_cumul=120\n'
assert_eq "tokens measured without cost keeps cost null" '{"cost_usd": null, "tokens_k": 120}' "$(bash "$SCRIPT" FEAT-724)"

register api-session FEAT-724
record api-session $'cost_usd=2.5\ntokens_k=30\n'
register other-card-session FEAT-9
record other-card-session $'cost_usd=7\ntokens_k_cumul=500\n'
register silent-session FEAT-724
assert_eq "sessions on the card are summed, legacy tokens_k included, other cards and silent sessions left out" '{"cost_usd": 2.5, "tokens_k": 150}' "$(bash "$SCRIPT" FEAT-724)"

record plan-session $'cost_usd=0\ntokens_k_cumul=0\n'
record api-session $'cost_usd=0\ntokens_k_cumul=0\n'
assert_eq "a measured zero stays zero" '{"cost_usd": 0, "tokens_k": 0}' "$(bash "$SCRIPT" FEAT-724)"

reset_state
register both-formats-session FEAT-724
record both-formats-session $'cost_usd=1\ntokens_k=999\ntokens_k_prev=40\ntokens_k_cumul=120\n'
assert_eq "a sidecar holding both token formats counts the cumulative one" '{"cost_usd": 1, "tokens_k": 120}' "$(bash "$SCRIPT" FEAT-724)"

printf "Test group: a total below one is still strict JSON\n"

reset_state
register cheap-session FEAT-724
record cheap-session $'cost_usd=0.42\ntokens_k_prev=0\ntokens_k_cumul=0.5\n'
cheap_usage="$(bash "$SCRIPT" FEAT-724)"
assert_eq "both totals keep their leading zero" '{"cost_usd": 0.42, "tokens_k": 0.5}' "$cheap_usage"
assert_eq "the line parses as strict JSON" "0.42" "$(printf '%s' "$cheap_usage" | python3 -c 'import json, sys; print(json.load(sys.stdin)["cost_usd"])')"

printf "Test group: the argument is a card id\n"

usage_error="$(bash "$SCRIPT" 2>&1 >/dev/null)"
assert_eq "no argument exits 1" "1" "$(bash "$SCRIPT" >/dev/null 2>&1; echo $?)"
assert_eq "the usage line names a card id" "usage: ticket-done-usage <card-id>" "$usage_error"

printf "Test group: board-card usage writes null onto a card nothing measured\n"

reset_state
bash "$SCRIPTS/board-card" init >/dev/null
bash "$SCRIPTS/board-card" create --kind project --name Home >/dev/null
bash "$SCRIPTS/board-card" create --kind epic --name Home --project PRJ-1 >/dev/null
card="$(bash "$SCRIPTS/board-card" create --epic EPIC-1 --name "A desktop session ticket")"
register desktop-session "$card"
assert_eq "board-card prints both totals as null" '{"cost_usd": null, "tokens_k": null}' "$(bash "$SCRIPTS/board-card" usage "$card")"
assert_eq "the card's tokens_k is null" "null" "$(bash "$SCRIPTS/board-card" show "$card" --json | jq --compact-output .tokens_k)"

record desktop-session $'cost_usd=0.42\ntokens_k_prev=0\ntokens_k_cumul=120\n'
assert_eq "board-card prints a sub-dollar cost with its leading zero" '{"cost_usd": 0.42, "tokens_k": 120}' "$(bash "$SCRIPTS/board-card" usage "$card")"
assert_eq "the card's cost_usd is the sub-dollar total" "0.42" "$(bash "$SCRIPTS/board-card" show "$card" --json | jq --compact-output .cost_usd)"

printf "\n%d passed, %d failed\n" "$pass" "$fail"
[ "$fail" -eq 0 ]
