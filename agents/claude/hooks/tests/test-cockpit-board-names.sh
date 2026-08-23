#!/usr/bin/env bash

BOARD_ID="$(cd "$(dirname "$0")/../.." && pwd)/cockpit-board-id"
TMPDIR="$(cd "$(mktemp -d)" && pwd -P)"
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

names() {
  COCKPIT_BOARDS_FILE="$1" "$BOARD_ID" boards 2>/dev/null
}

status() {
  COCKPIT_BOARDS_FILE="$1" "$BOARD_ID" boards >/dev/null 2>&1
  echo $?
}

cat > "$TMPDIR/boards.json" <<JSON
{"boards":[
  {"name":"Cockpit","ids":{"tickets-database":"db-cockpit"},"repos":["$TMPDIR/dotfiles"]},
  {"name":"Project","ids":{"tickets-database":"db-project"},"repos":[]}
]}
JSON

printf '{"boards":[]}' > "$TMPDIR/empty.json"

printf "Test group: every configured board is named, whatever checkout it serves\n"

assert_eq "both boards, one name per line, in the order the file holds them" \
  "$(printf 'Cockpit\nProject')" "$(names "$TMPDIR/boards.json")"
assert_eq "a board serving no checkout is named alongside one that does" \
  "Project" "$(names "$TMPDIR/boards.json" | tail -1)"

printf "\nTest group: the action takes no key and never refuses for want of one\n"

assert_eq "it exits 0 with no second argument" "0" "$(status "$TMPDIR/boards.json")"

printf "\nTest group: nothing recorded yet is silence, not a failure\n"

assert_eq "a file configuring no boards prints nothing" "" "$(names "$TMPDIR/empty.json")"
assert_eq "and a file that does not exist prints nothing" "" "$(names "$TMPDIR/absent.json")"
assert_eq "exiting 0 either way, so a caller reads an empty list" \
  "0" "$(status "$TMPDIR/absent.json")"

printf "\n%d passed, %d failed\n" "$pass" "$fail"
[ "$fail" -eq 0 ]
