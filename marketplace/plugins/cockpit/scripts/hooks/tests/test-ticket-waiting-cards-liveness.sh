#!/usr/bin/env bash

SCRIPT="$(cd "$(dirname "$0")/../.." && pwd)/ticket-waiting-cards"
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

BIN="$TMPDIR/bin"
STATE_DIR="$TMPDIR/state"
mkdir -p "$BIN" "$STATE_DIR"

BOARDS="$TMPDIR/cockpit-boards.json"
cat > "$BOARDS" <<JSON
{"boards":[{"name":"Cockpit","ids":{"tickets-database":"db-cockpit"},"view_id":"","repos":["$TMPDIR"]}]}
JSON

cat > "$BIN/security" <<'STUB'
#!/usr/bin/env bash
printf 'stub-token\n'
STUB

# Serve the fixture board response and record the request body, so the filter
# under --claimed-by can be asserted too.
cat > "$BIN/curl" <<STUB
#!/usr/bin/env bash
config="\$(cat)"
printf '%s\n' "\$config" >> "$TMPDIR/requests"
body="\$(printf '%s\n' "\$config" | sed -n 's/^data = "@\(.*\)"\$/\1/p')"
[ -z "\$body" ] || cat "\$body" >> "$TMPDIR/bodies"
cat "$TMPDIR/response.json"
STUB

chmod +x "$BIN/security" "$BIN/curl"

# One card per claim case. Ages are relative so the fixture never goes stale.
now="$(date -u +%s)"
old_claim="$(TZ=UTC date -u -r "$((now - 7200))" +%Y-%m-%dT%H:%M:%SZ)"
fresh_claim="$(TZ=UTC date -u -r "$((now - 600))" +%Y-%m-%dT%H:%M:%SZ)"

cat > "$TMPDIR/response.json" <<JSON
{"results":[
 {"id":"page-beating","properties":{
   "Status":{"status":{"name":"Ready for TR by AI"}},
   "Agent: Session Id":{"rich_text":[{"plain_text":"sess-beating @ $old_claim"}]},
   "Name":{"title":[{"plain_text":"held by a live session"}]}}},
 {"id":"page-dead","properties":{
   "Status":{"status":{"name":"Ready for TR by AI"}},
   "Agent: Session Id":{"rich_text":[{"plain_text":"sess-dead @ $old_claim"}]},
   "Name":{"title":[{"plain_text":"held by a session that went away"}]}}},
 {"id":"page-recent","properties":{
   "Status":{"status":{"name":"Ready for BR by AI"}},
   "Agent: Session Id":{"rich_text":[{"plain_text":"sess-elsewhere @ $fresh_claim"}]},
   "Name":{"title":[{"plain_text":"claimed minutes ago, no beat here"}]}}},
 {"id":"page-free","properties":{
   "Status":{"status":{"name":"Ready for BR by AI"}},
   "Agent: Session Id":{"rich_text":[]},
   "Name":{"title":[{"plain_text":"unclaimed"}]}}}
]}
JSON

# Only one session is beating. The other two have no heartbeat file at all,
# which is what a session that died looks like.
touch "$STATE_DIR/sess-beating.alive"

run_cards() {
  : > "$TMPDIR/requests"
  : > "$TMPDIR/bodies"
  PATH="$BIN:$PATH" \
  COCKPIT_BOARDS_FILE="$BOARDS" \
  COCKPIT_REPO="$TMPDIR" \
  TICKET_STATE_DIR="$STATE_DIR" \
    bash "$SCRIPT" "$@" 2>&1
}

verdict_for() {
  printf '%s\n' "$1" | awk -F'\t' -v p="$2" '$2 == p { print $6 }'
}

output="$(run_cards)"

printf "Test group: the verdict on each kind of claim\n"

assert_eq "a beating session keeps its claim" "live" "$(verdict_for "$output" page-beating)"
assert_eq "no beat and an old claim is expirable" "stale" "$(verdict_for "$output" page-dead)"
assert_eq "no beat but a claim under an hour old is left alone" "live" \
  "$(verdict_for "$output" page-recent)"
assert_eq "an empty claim has no verdict to give" "-" "$(verdict_for "$output" page-free)"

printf "\nTest group: the five fields before it keep their positions\n"

line="$(printf '%s\n' "$output" | awk -F'\t' '$2 == "page-beating"')"
assert_eq "board is still first" "Cockpit" "$(printf '%s' "$line" | cut -f1)"
assert_eq "status is still third" "Ready for TR by AI" "$(printf '%s' "$line" | cut -f3)"
assert_contains "claim is still fourth" "sess-beating @" "$(printf '%s' "$line" | cut -f4)"
assert_eq "name is still fifth" "held by a live session" "$(printf '%s' "$line" | cut -f5)"
assert_eq "six fields, no more" "6" "$(printf '%s' "$line" | awk -F'\t' '{print NF}')"

printf "\nTest group: the bare query covers the columns an abandoned card sits in\n"

bodies="$(cat "$TMPDIR/bodies")"
assert_contains "a card left mid-BR is a candidate" '"In BR by AI"' "$bodies"
assert_contains "a card left mid-TR is a candidate" '"In TR by AI"' "$bodies"

printf "\nTest group: --claimed-by asks a different question of the board\n"

output="$(run_cards --claimed-by sess-beating)"
bodies="$(cat "$TMPDIR/bodies")"

assert_contains "filters on the claim property" '"Agent: Session Id"' "$bodies"
assert_contains "names the session asked for" 'sess-beating' "$bodies"
assert_eq "no longer filters on a column" "0" \
  "$(printf '%s' "$bodies" | grep -cF 'Ready for BR by AI' | tr -d ' ')"

output="$(run_cards --claimed-by 2>&1 || true)"
assert_contains "refuses an empty session id" "needs a session id" "$output"

printf "\n%d passed, %d failed\n" "$pass" "$fail"
[ "$fail" -eq 0 ]
