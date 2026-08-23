#!/usr/bin/env bash

WATCHER="$(cd "$(dirname "$0")/../.." && pwd)/ticket-watch-board"
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
FIXTURE="$TMPDIR/fixture"
mkdir -p "$BIN" "$FIXTURE"

# Each line of the script is one poll's answer: a row count, or the word
# `error:<code>` to return a board error instead.
cat > "$BIN/curl" <<'STUB'
#!/usr/bin/env bash
config="$(cat)"
url="$(printf '%s\n' "$config" | sed -n 's/^url = "\(.*\)"$/\1/p')"

case "$url" in
  */views/*)
    rows_the_board_shows="$(cat "$TICKET_WATCH_FIXTURE/members" 2>/dev/null || true)"
    if [ "$rows_the_board_shows" = "error" ]; then
      printf '{"object":"error","status":400,"code":"object_not_found","message":"stub"}'
      exit 0
    fi
    total=0
    printf '{"object":"list","results":['
    for row in $rows_the_board_shows; do
      [ "$total" -gt 0 ] && printf ','
      printf '{"id":"%s"}' "$row"
      total=$((total + 1))
    done
    printf '],"total_count":%s,"has_more":false}' "$total"
    exit 0
    ;;
esac

body_path="$(printf '%s\n' "$config" | sed -n 's/^data = "@\(.*\)"$/\1/p')"
if [ -n "$body_path" ] && [ -f "$body_path" ]; then
  cp "$body_path" "$TICKET_WATCH_FIXTURE/last-body"
fi
n="$(cat "$TICKET_WATCH_FIXTURE/count")"
total="$(wc -l < "$TICKET_WATCH_FIXTURE/script" | tr -d ' ')"
if [ "$n" -ge "$total" ]; then
  : > "$TICKET_WATCH_FIXTURE/done"
  sleep 5
  exit 0
fi
printf '%s' "$((n + 1))" > "$TICKET_WATCH_FIXTURE/count"
answer="$(sed -n "$((n + 1))p" "$TICKET_WATCH_FIXTURE/script")"
case "$answer" in
  error:*)
    printf '{"object":"error","status":400,"code":"%s","message":"stub"}' "${answer#error:}"
    ;;
  *)
    # A results array of the requested length — only its length is read.
    printf '{"object":"list","results":['
    i=0
    while [ "$i" -lt "$answer" ]; do
      [ "$i" -gt 0 ] && printf ','
      printf '{"id":"row-%s"}' "$i"
      i=$((i + 1))
    done
    printf ']}'
    ;;
esac
STUB

cat > "$BIN/security" <<'STUB'
#!/usr/bin/env bash
# Stand in for the Keychain read. No token in the environment means the
# credential is missing, which is the case the listener must announce.
[ -n "${TICKET_WATCH_TEST_TOKEN:-}" ] || exit 1
printf '%s\n' "$TICKET_WATCH_TEST_TOKEN"
STUB

chmod +x "$BIN/curl" "$BIN/security"

# Both fixture boards serve the checkout the listener is pinned to below, so the
# scoping in cockpit_boards leaves the list alone and these groups keep testing
# what they always tested. The scoping itself is covered by
# test-cockpit-boards-scope.sh.
printf '{"boards":[{"name":"One","ids":{"tickets-database":"db-one"},"repos":["/tmp/here"]}]}' > "$FIXTURE/boards-one.json"
printf '{"boards":[{"name":"One","ids":{"tickets-database":"db-one"},"repos":["/tmp/here"]},{"name":"Two","ids":{"tickets-database":"db-two"},"repos":["/tmp/here"]}]}' \
  > "$FIXTURE/boards-two.json"
printf '{"boards":[{"name":"One","ids":{"tickets-database":"db-one"},"view_id":"view-one","repos":["/tmp/here"]}]}' \
  > "$FIXTURE/boards-view.json"

BOARDS="$FIXTURE/boards-one.json"
BOARD_SHOWS=""

# Run the listener against a scripted sequence of poll answers and return
# whatever it emitted.
run_watch() {
  rm -f "$FIXTURE/done"
  printf '0' > "$FIXTURE/count"
  printf '%s\n' "$@" > "$FIXTURE/script"
  printf '%s\n' "$BOARD_SHOWS" > "$FIXTURE/members"

  local out="$TMPDIR/out"
  : > "$out"

  PATH="$BIN:$PATH" \
  TICKET_WATCH_FIXTURE="$FIXTURE" \
  TICKET_WATCH_TEST_TOKEN="stub-token" \
  TICKET_WATCH_INTERVAL=0 \
  COCKPIT_REPO=/tmp/here \
  COCKPIT_BOARDS_FILE="$BOARDS" \
    bash "$WATCHER" > "$out" 2>&1 &
  local pid=$!

  # Wait for the scripted polls to be consumed, but break as soon as the
  # listener ends itself — announcing is an exit, so a successful run must not
  # pay the full timeout.
  local waited=0
  while [ ! -f "$FIXTURE/done" ] && kill -0 "$pid" 2>/dev/null && [ "$waited" -lt 100 ]; do
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

last_filter() {
  jq -c '.filter' < "$FIXTURE/last-body"
}

printf "Test group: the query asks for every column an agent can pick up\n"

run_watch 0 >/dev/null

assert_contains "a card in Ready for BR by AI counts whoever holds it" \
  '{"property":"Status","status":{"equals":"Ready for BR by AI"}}' "$(last_filter)"
assert_contains "so does a card in Ready for TR by AI" \
  '{"property":"Status","status":{"equals":"Ready for TR by AI"}}' "$(last_filter)"
assert_contains "an In Dev card counts only when nobody is holding it" \
  '{"and":[{"property":"Status","status":{"equals":"In Dev"}},{"property":"Agent: Session Id","rich_text":{"is_empty":true}}]}' \
  "$(last_filter)"


printf "Test group: unclaimed work is announced once\n"

output="$(run_watch 2)"
assert_contains "names the count" "2 ticket(s)" "$output"
assert_contains "names the skill to invoke" "/cockpit:ticket:0:copilot" "$output"
assert_eq "exactly one line" "1" "$(count_events "$output")"

printf "\nTest group: it announces and ends, rather than repeating\n"

output="$(run_watch 1 1 1 1 1 1)"
assert_eq "still one line after six polls' worth of work waiting" "1" "$(count_events "$output")"

printf "\nTest group: an empty queue is silent\n"

output="$(run_watch 0 0 0)"
assert_eq "nothing announced when no card is waiting" "0" "$(count_events "$output")"

printf "\nTest group: it waits, then announces when work appears\n"

output="$(run_watch 0 0 3)"
assert_contains "announces the card that arrived" "3 ticket(s)" "$output"
assert_eq "one line only" "1" "$(count_events "$output")"

printf "\nTest group: a board error is loud, never an empty queue\n"

output="$(run_watch error:object_not_found)"
assert_contains "names the code" "object_not_found" "$output"
assert_eq "does not announce work" "1" "$(count_events "$output")"

output="$(run_watch error:unauthorized)"
assert_contains "tells you how to replace the token" "security add-generic-password -U" "$output"

printf "\nTest group: the count covers every board, not just the first\n"

BOARDS="$FIXTURE/boards-two.json"

output="$(run_watch 2 1)"
assert_contains "sums the two boards" "3 ticket(s)" "$output"
assert_eq "one line only" "1" "$(count_events "$output")"

output="$(run_watch 0 2)"
assert_contains "a card on the second board alone still announces" "2 ticket(s)" "$output"

output="$(run_watch error:object_not_found 1)"
assert_contains "one board rejecting does not silence the other" "1 ticket(s)" "$output"

BOARDS="$FIXTURE/boards-one.json"

printf "\nTest group: a card the board hides is never announced\n"

announcements() {
  printf '%s' "$1" | grep -cF "ticket(s) waiting" | tr -d ' '
}

BOARDS="$FIXTURE/boards-view.json"

BOARD_SHOWS=""
output="$(run_watch 2 2 2)"
assert_eq "two cards waiting and the board showing neither says nothing" "0" "$(announcements "$output")"

BOARD_SHOWS="row-0"
output="$(run_watch 2)"
assert_contains "two cards waiting and the board showing one announces that one" "1 ticket(s)" "$output"

BOARD_SHOWS="row-0 row-1"
output="$(run_watch 2)"
assert_contains "both on the board announces both" "2 ticket(s)" "$output"

BOARD_SHOWS="error"
output="$(run_watch 1 1)"
assert_contains "a view that cannot be listed names the board" "could not be listed to the end" "$output"
assert_eq "and announces nothing off the short list" "0" "$(announcements "$output")"

BOARDS="$FIXTURE/boards-one.json"
BOARD_SHOWS=""
output="$(run_watch 2)"
assert_contains "a board with no view still counts every row" "2 ticket(s)" "$output"

printf "\nTest group: a missing credential is loud, not silent\n"

printf '0' > "$FIXTURE/count"
printf '%s\n' 1 > "$FIXTURE/script"

output="$(PATH="$BIN:$PATH" \
  TICKET_WATCH_FIXTURE="$FIXTURE" \
  TICKET_WATCH_INTERVAL=0 \
  COCKPIT_BOARDS_FILE="$BOARDS" \
  bash "$WATCHER" 2>&1)"
status=$?

assert_contains "announces the missing credential" "[ticket-listen] no credential" "$output"
assert_eq "one line only" "1" "$(printf '%s' "$output" | grep -c . | tr -d ' ')"
assert_eq "exits non-zero" "1" "$status"

printf "\n%d passed, %d failed\n" "$pass" "$fail"
[ "$fail" -eq 0 ]
