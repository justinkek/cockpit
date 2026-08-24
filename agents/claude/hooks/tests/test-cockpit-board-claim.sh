#!/usr/bin/env bash

CLAIM="$(cd "$(dirname "$0")/../.." && pwd)/cockpit-board-claim"
LIB_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
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

BOARDS="$TMPDIR/boards.json"

reset_boards() {
  cat > "$BOARDS" <<'JSON'
{
	"comment": "a comment the script must not eat",
	"boards": [
		{"name": "Cockpit", "ids": {"tickets-database": "db-cockpit"}, "view_id": "v-cockpit", "checkouts": ["~/dotfiles"]},
		{"name": "Project", "ids": {"tickets-database": "db-project"}, "repos": []}
	]
}
JSON
}

claim() {
  COCKPIT_BOARDS_FILE="$BOARDS" bash "$CLAIM" "$@"
}

checkouts_of() {
  jq --compact-output --arg name "$1" '.boards[] | select(.name == $name) | .checkouts' "$BOARDS"
}

printf "Test group: the answer is recorded against the board\n"

reset_boards
claim Project /tmp/newcheckout >/dev/null
assert_eq "the checkout lands in that board's checkouts" \
  '["/tmp/newcheckout"]' "$(checkouts_of Project)"
assert_eq "the other board is untouched" \
  '["~/dotfiles"]' "$(checkouts_of Cockpit)"
assert_eq "the rest of the file survives the rewrite" \
  "a comment the script must not eat" "$(jq -r .comment "$BOARDS")"
assert_eq "a board still on the old key carries none of it away" \
  'null' "$(jq --compact-output '.boards[] | select(.name == "Project") | .repos' "$BOARDS")"

printf "\nTest group: claiming twice leaves one entry\n"

claim Project /tmp/newcheckout >/dev/null
assert_eq "no duplicate" '["/tmp/newcheckout"]' "$(checkouts_of Project)"

claim Project /tmp/second >/dev/null
assert_eq "a second checkout is added, not replaced" \
  '["/tmp/newcheckout","/tmp/second"]' "$(checkouts_of Project)"

printf "\nTest group: a name no board has changes nothing\n"

reset_boards
before="$(cat "$BOARDS")"
out="$(claim Prject /tmp/typo 2>&1)"; st=$?
assert_eq "exits non-zero" "1" "$st"
assert_eq "names the boards it does know" "1" \
  "$(printf '%s' "$out" | grep -c 'Cockpit' | tr -d ' ')"
assert_eq "the file is byte-for-byte unchanged" "$before" "$(cat "$BOARDS")"

printf "\nTest group: a missing board name is a usage error\n"

out="$(claim 2>&1)"; st=$?
assert_eq "exits 2" "2" "$st"
assert_eq "prints the usage line" "1" \
  "$(printf '%s' "$out" | grep -c 'usage:' | tr -d ' ')"

printf "\nTest group: the claim is what the board list then matches on\n"

reset_boards
claim Project /tmp/roundtrip >/dev/null
source "$LIB_DIR/ticket-state-lib.sh"
assert_eq "the checkout now resolves to that board" "Project" \
  "$(COCKPIT_BOARDS_FILE="$BOARDS" COCKPIT_REPO=/tmp/roundtrip cockpit_boards | cut -f1)"

printf "\n%d passed, %d failed\n" "$pass" "$fail"
[ "$fail" -eq 0 ]
