#!/usr/bin/env bash

SCRIPT="$(cd "$(dirname "$0")/../.." && pwd)/cockpit-cache-query"
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

FAKE_HOME="$TMPDIR/home"
mkdir -p "$FAKE_HOME/.local/state/cockpit"

# Write the fixture cache, stamped $1 days into the past.
write_cache() {
  local days_old="$1"
  local updated
  updated="$(TZ=UTC date -v-"${days_old}"d '+%Y-%m-%dT%H:%M:%S.000Z')"

  cat > "$FAKE_HOME/.local/state/cockpit/cache.json" <<JSON
{
  "user": { "id": "test-user", "name": "Test User" },
  "cockpit": {
    "tickets": {
      "statuses": [ "Backlog", "In Dev" ],
      "properties": { "Name": "title", "Status": "status", "Epic": "relation" }
    },
    "epics": {
      "items": [
        { "id": "https://example.com/1", "name": "Closed Epic", "status": "Epic Done" },
        { "id": "https://example.com/2", "name": "Open Epic", "status": "Tickets In Dev" }
      ]
    }
  },
  "updated_at": "$updated"
}
JSON
}

write_cache_stamped() {
  cat > "$FAKE_HOME/.local/state/cockpit/cache.json" <<JSON
{
  "project_boards": { "collection://one": { "name": "A Board", "statuses": [ "Backlog" ] } },
  "updated_at": "$1"
}
JSON
}

write_cache_holding_only_a_project_board() {
  write_cache_stamped "$(TZ=UTC date '+%Y-%m-%dT%H:%M:%S.000Z')"
}

write_cache_from_before_the_property_map() {
  cat > "$FAKE_HOME/.local/state/cockpit/cache.json" <<JSON
{
  "user": { "id": "test-user", "name": "Test User" },
  "cockpit": { "tickets": { "statuses": [ "Backlog" ] } },
  "updated_at": "$(TZ=UTC date '+%Y-%m-%dT%H:%M:%S.000Z')"
}
JSON
}

# Run the reader against the fixture home. Stdout and stderr stay separate so a
# warning can never be mistaken for data.
cache_query() { HOME="$FAKE_HOME" bash "$SCRIPT" "$1" 2>/dev/null; }
cache_warning() { HOME="$FAKE_HOME" bash "$SCRIPT" "$1" 2>&1 >/dev/null; }
cache_exit_status() {
  HOME="$FAKE_HOME" bash "$SCRIPT" "$1" >/dev/null 2>&1
  printf '%s' "$?"
}

printf "Test group: a closed epic is never offered\n"

write_cache 1
epics="$(cache_query epics)"
assert_eq "the done epic is dropped" "" \
  "$(printf '%s' "$epics" | jq -r '.[] | select(.name == "Closed Epic") | .name')"
assert_eq "the open epic survives" "Open Epic" \
  "$(printf '%s' "$epics" | jq -r '.[0].name')"
assert_eq "nothing else is dropped with it" "1" \
  "$(printf '%s' "$epics" | jq -r 'length')"

printf "\nTest group: epic-statuses answers with every epic, closed ones included\n"

write_cache 1
epic_statuses="$(cache_query epic-statuses)"
assert_eq "the closed epic is in it" "Epic Done" \
  "$(printf '%s' "$epic_statuses" | jq -r '.[] | select(.name == "Closed Epic") | .status')"
assert_eq "the open epic is in it too" "Tickets In Dev" \
  "$(printf '%s' "$epic_statuses" | jq -r '.[] | select(.name == "Open Epic") | .status')"
assert_eq "neither is dropped" "2" "$(printf '%s' "$epic_statuses" | jq -r 'length')"
assert_eq "each carries the url the relation holds" "https://example.com/1" \
  "$(printf '%s' "$epic_statuses" | jq -r '.[] | select(.name == "Closed Epic") | .id')"
assert_eq "a cache with no epics is refused, not answered null" "1" \
  "$(write_cache_holding_only_a_project_board; cache_exit_status epic-statuses)"

printf "\nTest group: the cache answers what a ticket property is called and what type it is\n"

write_cache 0
properties="$(cache_query ticket-properties)"
assert_eq "a relation reads back as one, so an empty value on a ticket is a relation with nothing in it" "relation" \
  "$(printf '%s' "$properties" | jq -r '.Epic')"
assert_eq "every property the board has is named, not only the ones a ticket fills" "3" \
  "$(printf '%s' "$properties" | jq -r 'keys | length')"
assert_eq "reading the map exits clean" "0" "$(cache_exit_status ticket-properties)"

write_cache_from_before_the_property_map
assert_eq "a cache written before the map is refused, not answered empty" "1" \
  "$(cache_exit_status ticket-properties)"
assert_contains "and says which command adds it" "/cockpit:cache" "$(cache_warning ticket-properties)"
assert_eq "the statuses that cache does hold still read" "Backlog" \
  "$(cache_query statuses | jq -r '.[0]')"

printf "\nTest group: a key the cache does not hold is refused, so the caller falls back\n"

write_cache_holding_only_a_project_board
for missing in user-id statuses reference-tickets projects; do
  assert_eq "$missing is refused rather than answered null" "1" "$(cache_exit_status "$missing")"
  assert_eq "and nothing reaches stdout for it" "" "$(cache_query "$missing")"
done
assert_eq "the key that cache does hold still reads" "A Board" \
  "$(cache_query project-boards | jq -r '."collection://one".name')"

printf "\nTest group: a stale cache announces itself\n"

write_cache 30
assert_contains "names the age" "30 days old" "$(cache_warning epics)"
assert_contains "names the refresh path" "/cockpit:cache" "$(cache_warning epics)"
assert_eq "the warning stays off stdout" "0" \
  "$(cache_query epics | grep -cF 'days old' | tr -d ' ')"
assert_contains "every key inherits it, not just epics" "days old" "$(cache_warning user-id)"

printf "\nTest group: a cache whose age cannot be read says so\n"

write_cache_stamped ""
assert_contains "an absent stamp is not silence" "no readable date" \
  "$(cache_warning project-boards)"

write_cache_stamped "2026-08-08"
assert_contains "a date with no time is not silence either" "no readable date" \
  "$(cache_warning project-boards)"

printf "\nTest group: a fresh cache stays silent\n"

write_cache 0
assert_eq "no warning inside the window" "" "$(cache_warning epics)"

write_cache 1
assert_eq "no warning on the boundary day" "" "$(cache_warning epics)"

write_cache 2
assert_contains "the day past the boundary warns" "2 days old" "$(cache_warning epics)"

printf "\n%d passed, %d failed\n" "$pass" "$fail"
[ "$fail" -eq 0 ]
