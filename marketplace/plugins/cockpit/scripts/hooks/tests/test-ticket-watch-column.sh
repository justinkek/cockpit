#!/usr/bin/env bash

export CLAUDE_SHARED_DIR="$(cd "$(dirname "$0")/../../../../../../agents/claude" && pwd)"

WATCHER="$(cd "$(dirname "$0")/../.." && pwd)/ticket-watch-column"
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
  if printf '%s' "$output" | grep -qF "$expected"; then
    printf "  OK  %s\n" "$label"
    pass=$((pass + 1))
  else
    printf "  KO  %s — expected '%s' in output '%s'\n" "$label" "$expected" "$output"
    fail=$((fail + 1))
  fi
}

BIN="$TMPDIR/bin"
STATE_DIR="$TMPDIR/state"
FIXTURE="$TMPDIR/fixture"
mkdir -p "$BIN" "$STATE_DIR" "$FIXTURE"

SESSION="test-watch-$$"

export COCKPIT_BOARD_DIR="$TMPDIR/board"
"$BOARD_CARD" init >/dev/null
PAGE_ID="$("$BOARD_CARD" create --name "the registered ticket")"
SOURCE_PAGE_ID="$("$BOARD_CARD" create --name "a second watched card")"

cat > "$BIN/board-card" <<STUB
#!/usr/bin/env bash
# Move the card to the next scripted column, one per read, then read it back
# through the real board.
n="\$(cat "\$TICKET_WATCH_FIXTURE/count")"
total="\$(wc -l < "\$TICKET_WATCH_FIXTURE/script" | tr -d ' ')"
if [ "\$n" -ge "\$total" ]; then
  : > "\$TICKET_WATCH_FIXTURE/done"
  sleep 5
  exit 0
fi
printf '%s' "\$((n + 1))" > "\$TICKET_WATCH_FIXTURE/count"
scripted="\$(sed -n "\$((n + 1))p" "\$TICKET_WATCH_FIXTURE/script")"
live_column="\${scripted%%|*}"
case "\$scripted" in
  *"|"*)
    walked_by_the_agent="\${scripted#*|}"
    printf '%s' "\$walked_by_the_agent" > "\${TICKET_WATCH_TEST_COLUMN_FILE:-/dev/null}"
    ;;
esac
if [ "\$(cat "\$TICKET_WATCH_FIXTURE/last-\$2" 2>/dev/null)" != "\$live_column" ]; then
  "$BOARD_CARD" move "\$2" "\$live_column" >/dev/null
  printf '%s' "\$live_column" > "\$TICKET_WATCH_FIXTURE/last-\$2"
fi
exec "$BOARD_CARD" "\$@"
STUB

chmod +x "$BIN/board-card"

# Run the watcher against a scripted sequence of live columns and return
# whatever it emitted. $1 is the recorded column (empty for none), the rest are
# the columns the board reports, one per poll.
run_watch() {
  local recorded="$1"
  shift

  rm -f "$FIXTURE/done"
  printf '0' > "$FIXTURE/count"
  printf '%s\n' "$@" > "$FIXTURE/script"

  if [ -n "$recorded" ]; then
    printf '%s' "$recorded" > "$STATE_DIR/$SESSION.column"
  else
    rm -f "$STATE_DIR/$SESSION.column"
  fi

  local out="$TMPDIR/out"
  : > "$out"

  COCKPIT_BOARD_CARD="$BIN/board-card" \
  TICKET_WATCH_FIXTURE="$FIXTURE" \
  TICKET_WATCH_TEST_COLUMN_FILE="$STATE_DIR/$SESSION.column" \
  TICKET_WATCH_INTERVAL=0 \
  TICKET_STATE_DIR="$STATE_DIR" \
  CLAUDE_SESSION_ID="$SESSION" \
    bash "$WATCHER" "$PAGE_ID" > "$out" 2>&1 &
  local pid=$!

  # Wait for every scripted poll to be consumed rather than sleeping a fixed
  # amount — the last emit already happened by the time the sentinel lands.
  local waited=0
  # The watcher can now end on its own, so the wait must also break when the
  # process is gone - otherwise a self-disarm run pays the full timeout.
  while [ ! -f "$FIXTURE/done" ] && kill -0 "$pid" 2>/dev/null && [ "$waited" -lt 100 ]; do
    sleep 0.1
    waited=$((waited + 1))
  done

  kill "$pid" 2>/dev/null
  wait "$pid" 2>/dev/null

  cat "$out"
}

count_events() {
  printf '%s' "$1" | grep -cF "[ticket-watch] Ticket " | tr -d ' '
}

printf "Test group: a human move into a by-AI column fires exactly once\n"

output="$(run_watch "Ready for BR" "Ready for TR by AI" "Ready for TR by AI")"
assert_eq "one event for a move held two polls" "1" "$(count_events "$output")"
assert_contains "names the TR skill" "/cockpit:ticket:2:tr" "$output"
assert_contains "names the column" "Ready for TR by AI" "$output"

printf "\nTest group: the agent's own walk through the column is silent\n"

output="$(run_watch "Ready for BR" "Ready for TR by AI" "In TR by AI")"
assert_eq "no event when the mismatch lasts one poll" "0" "$(count_events "$output")"

printf "\nTest group: a card left sitting does not re-emit\n"

output="$(run_watch "Ready for BR" \
  "Ready for TR by AI" "Ready for TR by AI" "Ready for TR by AI" \
  "Ready for TR by AI" "Ready for TR by AI" "Ready for TR by AI")"
assert_eq "still one event after six polls" "1" "$(count_events "$output")"

printf "\nTest group: a card returning to a column it already announced is announced again\n"

output="$(run_watch "Ready for BR" \
  "Ready for TR by AI" "Ready for TR by AI" \
  "Ready for TR|Ready for TR" "Ready for TR|Ready for TR" \
  "Ready for TR by AI" "Ready for TR by AI")"
assert_eq "the agent's own walk stays silent, the return does not" "2" "$(count_events "$output")"
assert_eq "the column it came back to is named both times it landed there" "2" \
  "$(printf '%s' "$output" \
    | grep --count --extended-regexp "Ticket (moved to|dragged back to) Ready for TR by AI" \
    | tr -d ' ')"

printf "\nTest group: a drag back to an earlier column is announced as a bounce-back\n"

output="$(run_watch "Ready for TR" "Ready for TR by AI" "Ready for TR by AI")"
assert_contains "names the column it came from" \
  "dragged back to Ready for TR by AI from Ready for TR" "$output"
assert_contains "names the skill that records the bounce" \
  "/cockpit:ticket:x:back-from-column" "$output"
assert_contains "still names the drafting skill" "/cockpit:ticket:2:tr" "$output"

output="$(run_watch "In FR" "In CR" "In CR")"
assert_contains "a drag back to a column with no skill still bounces" \
  "dragged back to In CR from In FR" "$output"
assert_eq "and names only the skill that records it" "1" \
  "$(printf '%s' "$output" \
    | grep --only-matching --fixed-strings "/cockpit:ticket:" \
    | wc -l | tr -d ' ')"

output="$(run_watch "Ready for BR" "Ready for TR by AI" "Ready for TR by AI")"
assert_eq "a forward move is not a bounce-back" "0" \
  "$(printf '%s' "$output" | grep --count --fixed-strings "dragged back" | tr -d ' ')"

output="$(run_watch "Deprioritised" "In Dev" "In Dev")"
assert_eq "a column outside the order has no position, so nothing is claimed" "0" \
  "$(printf '%s' "$output" | grep --count --fixed-strings "dragged back" | tr -d ' ')"

output="$(run_watch "Ready for CR" "In Dev" "In Dev")"
assert_eq "a source column the bounce skill has no counter for is a plain move" "0" \
  "$(printf '%s' "$output" | grep --count --fixed-strings "dragged back" | tr -d ' ')"
assert_contains "and is still reported" \
  "Ticket moved to In Dev - invoke /cockpit:ticket:3:dev now." "$output"

printf "\nTest group: a move to a column with no skill behind it is still reported\n"

output="$(run_watch "Ready for TR" "In Dev" "In Dev")"
assert_eq "one event for the move into In Dev" "1" "$(count_events "$output")"
assert_contains "names the skill that starts dev" \
  "Ticket moved to In Dev - invoke /cockpit:ticket:3:dev now." "$output"

output="$(run_watch "In Dev" "In CR" "In CR")"
assert_contains "names the column it landed in" "Ticket moved to In CR." "$output"
assert_eq "names no skill, because none services In CR" "0" \
  "$(printf '%s' "$output" | grep -cF "invoke" | tr -d ' ')"

printf "\nTest group: the status line follows a card a person dragged\n"

output="$(run_watch "Ready for TR" "In Dev" "In Dev")"
assert_eq "the announced move is recorded for the status line" "In Dev" \
  "$(cat "$STATE_DIR/$SESSION.column")"

output="$(run_watch "In Dev" "In Dev" "In Dev")"
assert_eq "a card sitting where it was recorded leaves the record alone" "In Dev" \
  "$(cat "$STATE_DIR/$SESSION.column")"

printf "\nTest group: the watcher disarms itself once the ticket is Done\n"

output="$(run_watch "In CR" "Done" "Done")"
assert_contains "announces the disarm" "watcher disarmed" "$output"
assert_contains "names Done as the end" "ticket done" "$output"
assert_contains "asks for the close-out nobody ran" "/cockpit:ticket:7:done" "$output"
assert_eq "records Done for the status line" "Done" "$(cat "$STATE_DIR/$SESSION.column")"

output="$(run_watch "In CR" "Done")"
assert_eq "one poll reading Done does not disarm it" "0" \
  "$(printf '%s' "$output" | grep -cF "watcher disarmed" | tr -d ' ')"

output="$(run_watch "In CR" "Done" "Done|Done")"
assert_contains "the agent's walk recorded on the second poll still disarms it" "watcher disarmed" "$output"
assert_eq "and asks for no close-out, because the walk ran it" "0" \
  "$(printf '%s' "$output" | grep --count --fixed-strings "/cockpit:ticket:7:done" | tr -d ' ')"

output="$(run_watch "In CR" "Done" "In CR" "Done")"
assert_eq "Done read on two polls that are not consecutive does not disarm it" "0" \
  "$(printf '%s' "$output" | grep -cF "watcher disarmed" | tr -d ' ')"

output="$(run_watch "Done" "Done" "Done")"
assert_eq "the agent's own walk to Done asks for nothing" "0" \
  "$(printf '%s' "$output" | grep --count --fixed-strings "/cockpit:ticket:7:done" | tr -d ' ')"

output="$(run_watch "Ready for BR" "Ready for TR by AI" "Ready for TR by AI")"
assert_eq "a refinement column does not disarm it" "0" \
  "$(printf '%s' "$output" | grep -cF "watcher disarmed" | tr -d ' ')"

output="$(run_watch "In TR" "In Dev" "In Dev")"
assert_eq "In Dev does not disarm it either" "0" \
  "$(printf '%s' "$output" | grep -cF "watcher disarmed" | tr -d ' ')"

printf "\nTest group: the session is found from its marker when no env var names it\n"

run_watch_unnamed() {
  local recorded="$1"
  shift

  rm -f "$FIXTURE/done"
  printf '0' > "$FIXTURE/count"
  printf '%s\n' "$@" > "$FIXTURE/script"
  printf '%s' "$recorded" > "$STATE_DIR/$SESSION.column"
  printf '%s\n' "$PAGE_ID" > "$STATE_DIR/$SESSION.ticket"

  local out="$TMPDIR/out-unnamed"
  : > "$out"

  env -u CLAUDE_SESSION_ID -u CLAUDE_CODE_SESSION_ID \
  COCKPIT_BOARD_CARD="$BIN/board-card" \
  TICKET_WATCH_FIXTURE="$FIXTURE" \
  TICKET_WATCH_INTERVAL=0 \
  TICKET_STATE_DIR="$STATE_DIR" \
    bash "$WATCHER" "$PAGE_ID" > "$out" 2>&1 &
  local pid=$!

  local waited=0
  while [ ! -f "$FIXTURE/done" ] && kill -0 "$pid" 2>/dev/null && [ "$waited" -lt 100 ]; do
    sleep 0.1
    waited=$((waited + 1))
  done

  kill "$pid" 2>/dev/null
  wait "$pid" 2>/dev/null

  rm -f "$STATE_DIR/$SESSION.ticket"
  cat "$out"
}

output="$(run_watch_unnamed "In Dev" "In Dev" "In Dev")"
assert_eq "the recorded column silences a card already there" "0" "$(count_events "$output")"

output="$(run_watch_unnamed "In Dev" "In CR" "In CR")"
assert_eq "a real move still fires" "1" "$(count_events "$output")"

printf "\nTest group: a page no session registered fires on every landing\n"

run_watch_with_no_session_id_and_no_marker() {
  rm -f "$FIXTURE/done" "$STATE_DIR/.column"
  printf '0' > "$FIXTURE/count"
  printf '%s\n' "$@" > "$FIXTURE/script"

  local out="$TMPDIR/out-unregistered"
  : > "$out"

  env -u CLAUDE_SESSION_ID -u CLAUDE_CODE_SESSION_ID \
  COCKPIT_BOARD_CARD="$BIN/board-card" \
  TICKET_WATCH_FIXTURE="$FIXTURE" \
  TICKET_WATCH_INTERVAL=0 \
  TICKET_STATE_DIR="$STATE_DIR" \
    bash "$WATCHER" "$PAGE_ID" > "$out" 2>&1 &
  local pid=$!

  local waited=0
  while [ ! -f "$FIXTURE/done" ] && kill -0 "$pid" 2>/dev/null && [ "$waited" -lt 100 ]; do
    sleep 0.1
    waited=$((waited + 1))
  done

  kill "$pid" 2>/dev/null
  wait "$pid" 2>/dev/null

  cat "$out"
}

output="$(run_watch_with_no_session_id_and_no_marker "In Dev" "In Dev" "In CR" "In CR")"
assert_eq "both landings fire, with no record to silence either" "2" "$(count_events "$output")"
assert_eq "and nothing is recorded for a session that does not exist" "absent" \
  "$([ -f "$STATE_DIR/.column" ] && echo present || echo absent)"

printf "\nTest group: a second watched card is named by its id\n"

run_watch_two_cards() {
  local recorded="$1"
  shift

  rm -f "$FIXTURE/done"
  printf '0' > "$FIXTURE/count"
  printf '%s\n' "$@" > "$FIXTURE/script"
  printf '%s' "$recorded" > "$STATE_DIR/$SESSION.column"

  local out="$TMPDIR/out-two-cards"
  : > "$out"

  COCKPIT_BOARD_CARD="$BIN/board-card" \
  TICKET_WATCH_FIXTURE="$FIXTURE" \
  TICKET_WATCH_TEST_COLUMN_FILE="$STATE_DIR/$SESSION.column" \
  TICKET_WATCH_INTERVAL=0 \
  TICKET_STATE_DIR="$STATE_DIR" \
  CLAUDE_SESSION_ID="$SESSION" \
    bash "$WATCHER" "$PAGE_ID" "$SOURCE_PAGE_ID" > "$out" 2>&1 &
  local pid=$!

  local waited=0
  while [ ! -f "$FIXTURE/done" ] && kill -0 "$pid" 2>/dev/null && [ "$waited" -lt 100 ]; do
    sleep 0.1
    waited=$((waited + 1))
  done

  kill "$pid" 2>/dev/null
  wait "$pid" 2>/dev/null

  cat "$out"
}

output="$(run_watch_two_cards "In Dev" \
  "In Dev" "In Dev" \
  "In Dev" "Ready for CR" \
  "In Dev" "Ready for CR")"
assert_contains "the second card's move names that card" \
  "Card $SOURCE_PAGE_ID moved to Ready for CR" "$output"

output="$(run_watch_two_cards "In CR" \
  "In CR" "In CR" \
  "In CR" "In Dev" \
  "In CR" "In Dev")"
assert_eq "a backward move on the second card asks for no bounce-back" "0" \
  "$(printf '%s' "$output" | grep --count --fixed-strings "dragged back" | tr -d ' ')"

output="$(run_watch_two_cards "In Dev" \
  "In Dev" "In Dev" \
  "In CR" "In Dev" \
  "In CR" "In Dev")"
assert_contains "the registered card's own move is the ticket's" \
  "Ticket moved to In CR." "$output"

output="$(run_watch "Ready for TR" "In Dev" "In Dev")"
assert_contains "one watched card is the ticket" \
  "Ticket moved to In Dev - invoke /cockpit:ticket:3:dev now." "$output"

printf "\nTest group: a card the board cannot read is loud, not silent\n"

out="$TMPDIR/out-unreadable"
TICKET_WATCH_INTERVAL=0 \
TICKET_STATE_DIR="$STATE_DIR" \
CLAUDE_SESSION_ID="$SESSION" \
  bash "$WATCHER" FEAT-999 > "$out" 2>&1 &
pid=$!
waited=0
while ! grep --quiet --fixed-strings "poll failing" "$out" && [ "$waited" -lt 100 ]; do
  sleep 0.1
  waited=$((waited + 1))
done
kill "$pid" 2>/dev/null
wait "$pid" 2>/dev/null

assert_contains "says the poll is failing" "[ticket-watch] poll failing" "$(cat "$out")"
assert_eq "and announces no move" "0" "$(count_events "$(cat "$out")")"

output="$(bash "$WATCHER" 2>&1)"
assert_eq "no card named is refused" "1" "$?"
assert_contains "and says how to call it" "usage: ticket-watch-column <card-id>" "$output"

printf "\n%d passed, %d failed\n" "$pass" "$fail"
[ "$fail" -eq 0 ]
