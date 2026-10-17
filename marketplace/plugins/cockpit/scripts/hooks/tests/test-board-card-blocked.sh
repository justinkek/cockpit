#!/usr/bin/env bash

SCRIPTS="$(cd "$(dirname "$0")/../.." && pwd)"
export CLAUDE_SHARED_DIR="$(cd "$SCRIPTS/../../../../agents/claude" && pwd)"
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

export COCKPIT_BOARD_DIR="$TMPDIR/board"
export TICKET_CLAIM_LOCK_DIR="$TMPDIR/claims"
export COCKPIT_COMMIT_DELAY=0
export TICKET_STATE_DIR="$TMPDIR/state"
export CLAUDE_SESSION_ID="session-one"
export COCKPIT_NOW="2026-10-05T10:00:00Z"
export GIT_CONFIG_GLOBAL=/dev/null
export GIT_CONFIG_NOSYSTEM=1

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

stub() { bash "$SCRIPTS/board-card" "$@"; }
field() { stub show "$1" --json | jq --raw-output "$2"; }
last_commit() { git -C "$COCKPIT_BOARD_DIR" log -1 --format="$1"; }

stub init >/dev/null
stub create --kind project --name Cockpit --key COC >/dev/null
stub create --kind epic --project PRJ-1 --name Board >/dev/null
stub create --epic EPIC-1 --name Waiting >/dev/null

printf "Test group: setting and clearing blocked records the spell it was blocked for\n"

stub set COC-1 blocked "Waiting on the vendor" >/dev/null
assert_eq "setting it opens a spell from that day" '[{"from":"2026-10-05"}]' "$(field COC-1 '.blocked_spans | tojson')"
assert_eq "in the set's own commit" "set COC-1" "$(last_commit %s)"
COCKPIT_NOW=2026-10-06T10:00:00Z stub set COC-1 blocked "Still waiting on the vendor" >/dev/null
assert_eq "a new reason keeps the spell open" '[{"from":"2026-10-05"}]' "$(field COC-1 '.blocked_spans | tojson')"
COCKPIT_NOW=2026-10-08T23:30:00Z stub set COC-1 blocked '' >/dev/null
assert_eq "clearing it closes the spell on that UTC day" '[{"from":"2026-10-05","to":"2026-10-08"}]' "$(field COC-1 '.blocked_spans | tojson')"
COCKPIT_NOW=2026-10-08T23:40:00Z stub set COC-1 blocked '' >/dev/null
assert_eq "clearing it again changes nothing" '[{"from":"2026-10-05","to":"2026-10-08"}]' "$(field COC-1 '.blocked_spans | tojson')"
COCKPIT_NOW=2026-10-12T10:00:00Z stub set EPIC-1 blocked "Needs a decision" >/dev/null
assert_eq "an epic records its spells the same way" '[{"from":"2026-10-12"}]' "$(field EPIC-1 '.blocked_spans | tojson')"

printf "\nTest group: migrate dates the spells of a board from before from its history\n"

old="$TMPDIR/old"
export COCKPIT_BOARD_DIR="$old"
stub init >/dev/null
stub create --kind project --name Cockpit --key COC >/dev/null
stub create --kind epic --project PRJ-1 --name Board >/dev/null
stub create --epic EPIC-1 --name Dated >/dev/null
stub create --epic EPIC-1 --name Never >/dev/null
stub create --epic EPIC-1 --name Untracked >/dev/null
GIT_AUTHOR_DATE=2026-09-01T10:00:00Z stub set COC-1 blocked "First" >/dev/null
GIT_AUTHOR_DATE=2026-09-03T10:00:00Z stub set COC-1 blocked "Reworded" >/dev/null
GIT_AUTHOR_DATE=2026-09-04T23:30:00Z stub set COC-1 blocked '' >/dev/null
GIT_AUTHOR_DATE=2026-09-10T10:00:00Z stub set COC-1 blocked "Again" >/dev/null
GIT_AUTHOR_DATE=2026-09-11T10:00:00Z stub set EPIC-1 blocked "Epic too" >/dev/null
GIT_AUTHOR_DATE=2026-09-12T10:00:00Z stub set EPIC-1 blocked '' >/dev/null
for file in "$old"/tickets/COC-1.md "$old"/epics/EPIC-1.md; do perl -ni -e 'print unless /^blocked_spans: /' "$file"; done
perl -pi -e 's/^blocked: null$/blocked: "Set by hand"/' "$old/tickets/COC-3.md"
git -C "$old" add --all >/dev/null && git -C "$old" -c user.name=t -c user.email=t@t -c commit.gpgsign=false commit --quiet -m "an older board" >/dev/null
FEAT3_DAY="$(TZ=UTC git -C "$old" log -1 --format=%ad --date=format-local:%Y-%m-%d)"
output="$(stub migrate)"
assert_eq "a card's spells come from each change of its blocked field, one still open running on" \
  '[{"from":"2026-09-01","to":"2026-09-04"},{"from":"2026-09-10"}]' "$(field COC-1 '.blocked_spans | tojson')"
assert_eq "and an epic's the same way" '[{"from":"2026-09-11","to":"2026-09-12"}]' "$(field EPIC-1 '.blocked_spans | tojson')"
assert_eq "naming each record and its spells" "COC-1	blocked spans 2026-09-01 to 2026-09-04, 2026-09-10 to now" "$(printf '%s\n' "$output" | grep '^COC-1')"
assert_eq "a record never blocked gets none" "false" "$(field COC-2 'has("blocked_spans")')"
assert_eq "a record blocked in a commit board-card did not write is dated by that commit" "[{\"from\":\"$FEAT3_DAY\"}]" "$(field COC-3 '.blocked_spans | tojson')"
assert_eq "a second migrate changes no spell" "0" "$(stub migrate | grep --count 'blocked spans')"
rm -rf "$old/.git"
perl -ni -e 'print unless /^blocked_spans: /' "$old/tickets/COC-3.md"
assert_eq "a board with no history leaves a blocked record with no spell, and says so" \
  "COC-3	blocked with no history to date it, so it has no blocked span" "$(stub migrate | grep '^COC-3')"

printf "\n%d passed, %d failed\n" "$pass" "$fail"
[ "$fail" -eq 0 ]
