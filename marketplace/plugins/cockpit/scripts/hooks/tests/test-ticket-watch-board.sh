#!/usr/bin/env bash

export CLAUDE_SHARED_DIR="$(cd "$(dirname "$0")/../../../../../../agents/claude" && pwd)"

WATCHER="$(cd "$(dirname "$0")/../.." && pwd)/ticket-watch-board"
BOARD_CARD="$(cd "$(dirname "$0")/../.." && pwd)/board-card"
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

export TICKET_CLAIM_LOCK="$TMPDIR/claim-lock"
printf '#!/usr/bin/env bash\nexit 0\n' > "$TICKET_CLAIM_LOCK"
chmod +x "$TICKET_CLAIM_LOCK"

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
  if printf '%s' "$output" | grep -qF "$expected"; then
    printf "  OK  %s\n" "$label"
    pass=$((pass + 1))
  else
    printf "  KO  %s — expected '%s' in output '%s'\n" "$label" "$expected" "$output"
    fail=$((fail + 1))
  fi
}

fresh_board() {
  export COCKPIT_BOARD_DIR="$TMPDIR/board-$1"
  "$BOARD_CARD" init >/dev/null
  "$BOARD_CARD" create --kind project --name Home --key HOM >/dev/null
  "$BOARD_CARD" create --kind epic --name Home --project PRJ-1 >/dev/null
}

card_in() {
  "$BOARD_CARD" create --epic EPIC-1 --name "$2" --status "$1"
}

run_watch() {
  local seconds="${1:-3}" out="$TMPDIR/out"
  : > "$out"
  TICKET_WATCH_INTERVAL=0.2 bash "$WATCHER" > "$out" 2>&1 &
  local pid=$! waited=0
  while kill -0 "$pid" 2>/dev/null && [ "$waited" -lt "$((seconds * 10))" ]; do
    sleep 0.1
    waited=$((waited + 1))
  done
  kill "$pid" 2>/dev/null
  wait "$pid" 2>/dev/null
  cat "$out"
}

count_events() {
  printf '%s' "$1" | grep -cF "[ticket-listen]" | tr -d ' '
}

printf "Test group: unclaimed work is announced once\n"

fresh_board announce
card_in "Ready for BR by AI" "a card for BR" >/dev/null
card_in "Ready for TR by AI" "a card for TR" >/dev/null
output="$(run_watch)"
assert_contains "names the count" "2 ticket(s)" "$output"
assert_contains "names the skill to invoke" "/cockpit:ticket:0:copilot" "$output"
assert_eq "exactly one line, then it ends" "1" "$(count_events "$output")"

printf "\nTest group: In Dev counts only when nobody is holding it\n"

fresh_board in-dev
held="$(card_in "In Dev" "being built")"
CLAUDE_SESSION_ID=someone "$BOARD_CARD" claim "$held" >/dev/null
output="$(run_watch 2)"
assert_eq "a held In Dev card is not waiting" "0" "$(count_events "$output")"

card_in "In Dev" "abandoned before anyone held it" >/dev/null
output="$(run_watch)"
assert_contains "an unheld In Dev card is" "1 ticket(s)" "$output"

printf "\nTest group: a blocked card is not waiting\n"

fresh_board blocked
blocked="$(card_in "Ready for BR by AI" "waiting on an answer")"
"$BOARD_CARD" set "$blocked" blocked "waiting on the person" >/dev/null
output="$(run_watch 2)"
assert_eq "nothing announced for a blocked card" "0" "$(count_events "$output")"

printf "\nTest group: an empty queue is silent\n"

fresh_board empty
card_in "Backlog" "not yet" >/dev/null
card_in "In BR" "a person is on it" >/dev/null
output="$(run_watch 2)"
assert_eq "nothing announced when no card is waiting" "0" "$(count_events "$output")"

printf "\nTest group: it waits, then announces when work appears\n"

fresh_board appears
out="$TMPDIR/out-appears"
TICKET_WATCH_INTERVAL=0.2 bash "$WATCHER" > "$out" 2>&1 &
pid=$!
sleep 1
assert_eq "silent before the card arrives" "0" "$(count_events "$(cat "$out")")"
card_in "Ready for TR by AI" "arrived late" >/dev/null
waited=0
while kill -0 "$pid" 2>/dev/null && [ "$waited" -lt 50 ]; do
  sleep 0.1
  waited=$((waited + 1))
done
kill "$pid" 2>/dev/null
wait "$pid" 2>/dev/null
assert_contains "announces the card that arrived" "1 ticket(s)" "$(cat "$out")"

printf "\nTest group: no board is loud, never an empty queue\n"

export COCKPIT_BOARD_DIR="$TMPDIR/never-made"
output="$(TICKET_WATCH_INTERVAL=0 bash "$WATCHER" 2>&1)"
status=$?
assert_contains "names the missing board" "no board at" "$output"
assert_contains "and how to make one" "board-card init" "$output"
assert_eq "exits non-zero" "1" "$status"

printf "\n%d passed, %d failed\n" "$pass" "$fail"
[ "$fail" -eq 0 ]
