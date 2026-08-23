#!/usr/bin/env bash

WATCHER="$(cd "$(dirname "$0")/../.." && pwd)/ticket-watch-column"
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
PAGE_ID="3b38f3776f4f819aa509d6ebf233eb71"

cat > "$BIN/curl" <<'STUB'
#!/usr/bin/env bash
# Serve the next scripted column as a Notion page response, one per call.
n="$(cat "$TICKET_WATCH_FIXTURE/count")"
total="$(wc -l < "$TICKET_WATCH_FIXTURE/script" | tr -d ' ')"
if [ "$n" -ge "$total" ]; then
  : > "$TICKET_WATCH_FIXTURE/done"
  sleep 5
  exit 0
fi
printf '%s' "$((n + 1))" > "$TICKET_WATCH_FIXTURE/count"
scripted="$(sed -n "$((n + 1))p" "$TICKET_WATCH_FIXTURE/script")"
live_column="${scripted%%|*}"
case "$scripted" in
  *"|"*)
    walked_by_the_agent="${scripted#*|}"
    printf '%s' "$walked_by_the_agent" > "${TICKET_WATCH_TEST_COLUMN_FILE:-/dev/null}"
    ;;
esac
printf '{"properties":{"Status":{"status":{"name":"%s"}}}}' "$live_column"
STUB

cat > "$BIN/security" <<'STUB'
#!/usr/bin/env bash
# Stand in for the Keychain read. No token in the environment means the
# credential is missing, which is the case the watcher must announce.
[ -n "${TICKET_WATCH_TEST_TOKEN:-}" ] || exit 1
printf '%s\n' "$TICKET_WATCH_TEST_TOKEN"
STUB

chmod +x "$BIN/curl" "$BIN/security"

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

  PATH="$BIN:$PATH" \
  TICKET_WATCH_FIXTURE="$FIXTURE" \
  TICKET_WATCH_TEST_TOKEN="stub-token" \
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

output="$(run_watch "In CR" "Done")"
assert_contains "announces the disarm" "watcher disarmed" "$output"
assert_contains "names Done as the end" "ticket done" "$output"
assert_contains "asks for the close-out nobody ran" "/cockpit:ticket:7:done" "$output"

output="$(run_watch "Done" "Done")"
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
  printf 'https://app.notion.com/p/%s\n' "$PAGE_ID" > "$STATE_DIR/$SESSION.ticket"

  local out="$TMPDIR/out-unnamed"
  : > "$out"

  env -u CLAUDE_SESSION_ID -u CLAUDE_CODE_SESSION_ID \
  PATH="$BIN:$PATH" \
  TICKET_WATCH_FIXTURE="$FIXTURE" \
  TICKET_WATCH_TEST_TOKEN="stub-token" \
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
  PATH="$BIN:$PATH" \
  TICKET_WATCH_FIXTURE="$FIXTURE" \
  TICKET_WATCH_TEST_TOKEN="stub-token" \
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

printf "\nTest group: a cross-board session is told which of its two cards moved\n"

SOURCE_PAGE_ID="3b48f3776f4f81d3813bc32528dcbacf"

run_watch_two_cards() {
  local recorded="$1"
  shift

  rm -f "$FIXTURE/done"
  printf '0' > "$FIXTURE/count"
  printf '%s\n' "$@" > "$FIXTURE/script"
  printf '%s' "$recorded" > "$STATE_DIR/$SESSION.column"

  local out="$TMPDIR/out-two-cards"
  : > "$out"

  PATH="$BIN:$PATH" \
  TICKET_WATCH_FIXTURE="$FIXTURE" \
  TICKET_WATCH_TEST_TOKEN="stub-token" \
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
assert_contains "the project board's move names its own board" \
  "Project board card moved to Ready for CR" "$output"
assert_contains "and says which card the status is read from" \
  "the project board owns status" "$output"

output="$(run_watch_two_cards "In CR" \
  "In CR" "In Review" \
  "In CR" "In Progress" \
  "In CR" "In Progress")"
assert_contains "a backward move on the project board is reported like any other" \
  "Project board card moved to In Progress - the project board owns status." "$output"
assert_eq "and asks for no bounce-back, which the cockpit card has not had" "0" \
  "$(printf '%s' "$output" | grep --count --fixed-strings "dragged back" | tr -d ' ')"

output="$(run_watch_two_cards "In Dev" \
  "In Dev" "In Progress" \
  "In CR" "In Progress" \
  "In CR" "In Progress")"
assert_contains "the cockpit's own move names the cockpit" \
  "Cockpit card moved to In CR." "$output"
assert_eq "and does not claim the cockpit owns status" "0" \
  "$(printf '%s' "$output" | grep --count --fixed-strings "owns status" | tr -d ' ')"

output="$(run_watch "Ready for TR" "In Dev" "In Dev")"
assert_contains "one watched card has no second board to be confused with" \
  "Ticket moved to In Dev - invoke /cockpit:ticket:3:dev now." "$output"

printf "\nTest group: a missing credential is loud, not silent\n"

printf '0' > "$FIXTURE/count"
printf '%s\n' "Ready for TR by AI" > "$FIXTURE/script"

output="$(PATH="$BIN:$PATH" \
  TICKET_WATCH_FIXTURE="$FIXTURE" \
  TICKET_WATCH_INTERVAL=0 \
  TICKET_STATE_DIR="$STATE_DIR" \
  CLAUDE_SESSION_ID="$SESSION" \
  bash "$WATCHER" "$PAGE_ID" 2>&1)"
status=$?

assert_contains "announces the missing credential" "[ticket-watch] no credential" "$output"
assert_eq "one line only" "1" "$(printf '%s' "$output" | grep -c . | tr -d ' ')"
assert_eq "exits non-zero" "1" "$status"

printf "\n%d passed, %d failed\n" "$pass" "$fail"
[ "$fail" -eq 0 ]
