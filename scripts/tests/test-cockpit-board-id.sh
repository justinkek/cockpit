#!/usr/bin/env bash

REPO="$(cd "$(dirname "$0")" && cd "$(pwd -P)/../.." && pwd)"
SCRIPT="$REPO/agents/claude/cockpit-board-id"
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

pass=0
fail=0

export COCKPIT_BOARDS_FILE="$TMPDIR/cockpit-boards.json"
export COCKPIT_REPO="$TMPDIR/checkout"
mkdir -p "$COCKPIT_REPO"

write_fixture() {
  cat > "$COCKPIT_BOARDS_FILE" <<FIXTURE
{
	"boards": [
		{
			"name": "Served",
			"ids": { "tickets-data-source": "collection://tickets-of-served", "tickets-database": "aaa" },
			"repos": [ "$COCKPIT_REPO" ]
		},
		{
			"name": "Elsewhere",
			"ids": { "tickets-data-source": "collection://tickets-of-elsewhere", "tickets-database": "bbb" },
			"repos": [ "$TMPDIR/other" ]
		}
	]
}
FIXTURE
}

run_board_id() {
  unset COCKPIT_BOARD
  output="$("$SCRIPT" "$@" 2>&1)"
  status=$?
}

assert_output() {
  local label="$1" expected="$2"
  if [ "$output" = "$expected" ]; then
    printf "  OK  %s\n" "$label"
    pass=$((pass + 1))
  else
    printf "  KO  %s — got '%s', expected '%s'\n" "$label" "$output" "$expected"
    fail=$((fail + 1))
  fi
}

assert_status() {
  local label="$1" expected="$2"
  if [ "$status" -eq "$expected" ]; then
    printf "  OK  %s\n" "$label"
    pass=$((pass + 1))
  else
    printf "  KO  %s — exit %s, expected %s\n" "$label" "$status" "$expected"
    fail=$((fail + 1))
  fi
}

assert_key_count() {
  local label="$1" expected="$2" actual
  actual="$(jq '[.boards[] | select(.name == "Served") | .ids | keys[]] | length' "$COCKPIT_BOARDS_FILE")"
  if [ "$actual" -eq "$expected" ]; then
    printf "  OK  %s\n" "$label"
    pass=$((pass + 1))
  else
    printf "  KO  %s — %s keys, expected %s\n" "$label" "$actual" "$expected"
    fail=$((fail + 1))
  fi
}

printf "Test group: a recorded id is read off the board serving this checkout\n"

write_fixture
run_board_id get tickets-data-source
assert_output "the checkout picks its own board, not the first one listed" "collection://tickets-of-served"
assert_status "and exits clean" 0

run_board_id get tickets-data-source Elsewhere
assert_output "naming a board reaches one this checkout does not serve" "collection://tickets-of-elsewhere"

run_board_id get tickets-data-source elsewhere
assert_output "a board name typed in lower case still matches" "collection://tickets-of-elsewhere"

run_board_id get tickets-database
assert_output "a classic id reads through the same reader as a data source one" "aaa"

printf "\nTest group: an unrecorded id is a question, not an empty answer\n"

write_fixture
run_board_id get epics-data-source
assert_status "a key the board has not recorded exits 6" 6

run_board_id get nosuchkey
assert_status "a key outside the known list is refused before any lookup" 2

COCKPIT_REPO="$TMPDIR/unclaimed" run_board_id get tickets-data-source
assert_status "a checkout no board claims exits 3 rather than guessing" 3

run_board_id get tickets-data-source Nosuchboard
assert_status "a board name the file does not have exits 4" 4

printf "\nTest group: the answer to the question is recorded, so it is asked once\n"

write_fixture
run_board_id set epics-data-source "collection://epics-of-served"
assert_status "recording an id exits clean" 0

run_board_id get epics-data-source
assert_output "the recorded id reads back" "collection://epics-of-served"

run_board_id set epics-data-source "collection://epics-corrected"
run_board_id get epics-data-source
assert_output "recording the same key twice replaces rather than duplicates" "collection://epics-corrected"
assert_key_count "and leaves one entry per key" 3

run_board_id set epics-data-source "collection://elsewhere-epics" Elsewhere
assert_key_count "recording against another board leaves this one alone" 3

printf "\n%d passed, %d failed\n" "$pass" "$fail"
[ "$fail" -eq 0 ]
