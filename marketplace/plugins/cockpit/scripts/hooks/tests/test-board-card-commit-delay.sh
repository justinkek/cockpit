#!/usr/bin/env bash

SCRIPTS="$(cd "$(dirname "$0")/../.." && pwd)"
export CLAUDE_SHARED_DIR="$(cd "$SCRIPTS/../../../../agents/claude" && pwd)"
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

export COCKPIT_BOARD_DIR="$TMPDIR/board"
export TICKET_CLAIM_LOCK_DIR="$TMPDIR/claims"
export TICKET_STATE_DIR="$TMPDIR/state"
export CLAUDE_SESSION_ID="session-one"
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
commits() { git -C "$COCKPIT_BOARD_DIR" rev-list --count HEAD; }
subjects() { git -C "$COCKPIT_BOARD_DIR" log -"$1" --format=%s | paste -sd '|' -; }
held="$COCKPIT_BOARD_DIR/.git/board-card-held"

wait_for_commits() {
  local want="$1" tries=0
  until [ "$(commits)" -ge "$want" ] || [ "$tries" -ge 50 ]; do
    sleep 0.2
    tries=$((tries + 1))
  done
}

printf "Test group: writes to one record close together become one commit for that record once they stop\n"

COCKPIT_COMMIT_DELAY=0 stub init >/dev/null
COCKPIT_COMMIT_DELAY=0 stub create --kind project --name Home --key HOM >/dev/null
COCKPIT_COMMIT_DELAY=0 stub create --kind epic --name Home --project PRJ-1 >/dev/null
COCKPIT_COMMIT_DELAY=0 stub create --epic EPIC-1 --name First >/dev/null
COCKPIT_COMMIT_DELAY=0 stub create --epic EPIC-1 --name Second >/dev/null
COCKPIT_COMMIT_DELAY=0 stub create --epic EPIC-1 --name Third >/dev/null
before="$(commits)"

export COCKPIT_COMMIT_DELAY=2
stub move HOM-1 "Ready for BR by AI" >/dev/null
stub set HOM-2 name "Second, renamed" >/dev/null
stub move HOM-2 "Ready for BR by AI" >/dev/null
assert_eq "nothing is committed while the writes keep coming" "$before" "$(commits)"
assert_eq "but every write is already on disk" "Second, renamed" "$(stub show HOM-2 --json | jq --raw-output .name)"
wait_for_commits $((before + 2))
sleep 1
assert_eq "once they stop, each record lands as a commit of its own" "$((before + 2))" "$(commits)"
assert_eq "naming each action once and the one record it touched" "set, move HOM-2|move HOM-1" "$(subjects 2)"
assert_eq "with nothing left uncommitted" "" "$(git -C "$COCKPIT_BOARD_DIR" status --short)"
assert_eq "and nothing left waiting" "false" "$([ -e "$held" ] && echo true || echo false)"

printf "\nTest group: one write that changes several records is one commit holding all of them\n"

export COCKPIT_COMMIT_DELAY=60
before="$(commits)"
stub set HOM-1 name "First, again" >/dev/null
stub link HOM-1 HOM-2 >/dev/null
assert_eq "a record's waiting write is committed on its own once a write spanning it and another lands" "set HOM-1" "$(subjects 1)"
assert_eq "while the write spanning both waits" "$((before + 1))" "$(commits)"
stub set HOM-3 name "Third, renamed" >/dev/null
stub set HOM-2 name "Second, again" >/dev/null
assert_eq "a later write to one of its records commits it first, as one commit" "link HOM-1 HOM-2" "$(subjects 1)"
stub flush --now >/dev/null
assert_eq "and every record's own write follows in a commit of its own" "set HOM-2|set HOM-3|link HOM-1 HOM-2" "$(subjects 3)"
assert_eq "the link commit holds both cards and nothing else" "cards/HOM-1.md cards/HOM-2.md" \
  "$(git -C "$COCKPIT_BOARD_DIR" show --name-only --format= HEAD~2 | paste -sd ' ' -)"

printf "\nTest group: a read of one record's history takes that record's waiting writes first\n"

before="$(commits)"
stub set HOM-1 name "First, renamed" >/dev/null
stub set HOM-2 name "Second, renamed again" >/dev/null
assert_eq "a write waits for the quiet that has not come" "$before" "$(commits)"
assert_eq "history shows the write it would otherwise miss" "set HOM-1" "$(stub history HOM-1 | head -1 | cut -f3)"
assert_eq "as a commit of its own" "$((before + 1))" "$(commits)"
assert_eq "leaving another record's write waiting" "M cards/HOM-2.md" "$(git -C "$COCKPIT_BOARD_DIR" status --short | sed 's/^ *//')"
assert_eq "until its own history is read" "set HOM-2" "$(stub history HOM-2 | head -1 | cut -f3)"

printf "\nTest group: undo commits what is waiting before it takes anything back\n"

before="$(commits)"
stub set HOM-2 complexity 3 >/dev/null
stub undo HOM-2 >/dev/null
assert_eq "the waiting write is committed, then taken back in a commit of its own" "undo HOM-2|set HOM-2" "$(subjects 2)"
assert_eq "so the undo took back that write and nothing older" "null" "$(stub show HOM-2 --json | jq .complexity)"
assert_eq "two commits in all" "$((before + 2))" "$(commits)"

printf "\nTest group: nothing is lost when the board-card that wrote has gone\n"

COCKPIT_COMMIT_DELAY=0 stub create --kind project --name Garden --key GAR >/dev/null
COCKPIT_COMMIT_DELAY=0 stub create --kind epic --name Beds --project PRJ-2 >/dev/null
before="$(commits)"
stub set HOM-1 epic EPIC-2 >/dev/null
assert_eq "the write is waiting, one line for each file it changed, the linked ticket and the aliases among them" "4" "$(wc -l < "$held" | tr -d ' ')"
stub flush >/dev/null
assert_eq "flush leaves a write that is not yet due" "$before" "$(commits)"
stub flush --now >/dev/null
assert_eq "flush --now commits the renumbering as one, under each id the record held and the ticket it is linked to" "set GAR-1 HOM-1 HOM-2" "$(subjects 1)"

stub set HOM-1 name "Stale" >/dev/null
awk -F'\t' 'BEGIN { OFS = FS } { $2 = 1; print }' "$held" > "$held.old" && mv "$held.old" "$held"
stub set HOM-2 name "Fresh" >/dev/null
assert_eq "a write finding an overdue batch commits it first, on its own" "set GAR-1" "$(subjects 1)"
stub flush --now >/dev/null
assert_eq "and its own write follows in the next" "set HOM-2|set GAR-1" "$(subjects 2)"

printf 'edited by hand\n' >> "$COCKPIT_BOARD_DIR/cards/HOM-3.md"
stub set HOM-2 name "Beside a hand edit" >/dev/null
assert_eq "a change no write made is committed on its own ahead of the write" "unrecorded HOM-3" "$(subjects 1)"
stub flush --now >/dev/null

export COCKPIT_COMMIT_DELAY=1
before="$(commits)"
stub set HOM-2 name "After exit" >/dev/null &
wait $!
wait_for_commits $((before + 1))
assert_eq "a write whose process has exited is still committed once quiet" "set HOM-2" "$(subjects 1)"

printf "\nTest group: an epic's target and the due dates it holds wait as one commit, which either record's history takes\n"

export COCKPIT_COMMIT_DELAY=0
epic="$(stub create --kind epic --project PRJ-1 --name Payments)"
card="$(stub create --name "Held by the epic" --epic "$epic")"
export COCKPIT_COMMIT_DELAY=60
before="$(commits)"
stub set "$epic" target 2026-11-20 >/dev/null
assert_eq "the target and the due date it set both wait" "$before" "$(commits)"
epic_last="$(stub history "$epic" | head -1)"
assert_eq "the epic's history commits them as one" "set $card $epic" "$(printf '%s' "$epic_last" | cut -f3)"
assert_eq "which is the card's last commit too" "$(printf '%s' "$epic_last" | cut -f1)" "$(stub history "$card" | head -1 | cut -f1)"

printf "\nTest group: the board's revision follows its content, not its commits\n"

export COCKPIT_COMMIT_DELAY=60
stub set HOM-2 name "Revised" >/dev/null
written="$(stub revision)"
stub flush --now >/dev/null
assert_eq "committing what was written leaves the revision as it was" "$written" "$(stub revision)"
stub set HOM-2 name "Revised again" >/dev/null
assert_eq "while a write changes it" "true" "$([ "$written" != "$(stub revision)" ] && echo true)"
stub flush --now >/dev/null

printf "\n%d passed, %d failed\n" "$pass" "$fail"
[ "$fail" -eq 0 ]
