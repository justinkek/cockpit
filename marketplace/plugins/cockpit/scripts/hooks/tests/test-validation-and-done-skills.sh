#!/usr/bin/env bash

SCRIPTS="$(cd "$(dirname "$0")/../.." && pwd)"
SKILLS="$(cd "$SCRIPTS/../skills" && pwd)"
VALIDATION="$SKILLS/ticket:6:validation/SKILL.md"
DONE="$SKILLS/ticket:7:done/SKILL.md"
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

export COCKPIT_BOARD_DIR="$TMPDIR/board"
export TICKET_CLAIM_LOCK_DIR="$TMPDIR/claims"
export TICKET_STATE_DIR="$TMPDIR/state"
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

holds() {
  grep --quiet --fixed-strings -- "$2" "$1" && echo yes || echo no
}

line_holding() {
  grep --fixed-strings -- "$2" "$1" | head -n 1
}

guard_properties() {
  sed -n '/^### 1\./,/^### 2\./p' "$1" \
    | grep '^`"$HOME/.cockpit/scripts/board-card" show <id> ' \
    | head -n 1 \
    | sed -e 's/^`"$HOME\/.cockpit\/scripts\/board-card" show <id> //' -e 's/`.*$//' \
    | xargs printf '%s\n'
}

board() { bash "$SCRIPTS/board-card" "$@"; }

board init >/dev/null
parent="$(board create --name Parent)"
part="$(board create --name Part)"
board link "$parent" "$part" >/dev/null
bug="$(board create --name Defect --type Bug)"
timebox="$(board create --name "[30m] Research" --type Timebox)"

printf "Test group: the guard reads every property a later step decides on\n"

for skill in "$VALIDATION" "$DONE"; do
  name="$(basename "$(dirname "$skill")")"
  properties=()
  while IFS= read -r property; do properties+=("$property"); done < <(guard_properties "$skill")
  read_back="$(board show "$parent" "${properties[@]}" 2>&1)"
  assert_eq "$name's guard call is one board-card accepts" "0" "$?"
  assert_eq "$name's guard reads the type" "yes" "$(printf '%s\n' "$read_back" | grep --quiet '^Type	' && echo yes || echo no)"
done

done_properties=()
while IFS= read -r property; do done_properties+=("$property"); done < <(guard_properties "$DONE")
assert_eq "done's guard sees a split parent's sub-tickets" "Dependent on	$part" \
  "$(board show "$parent" "${done_properties[@]}" | grep '^Dependent on	')"
assert_eq "and sees none on a card that has none" "" \
  "$(board show "$part" "${done_properties[@]}" | grep '^Dependent on	')"

printf "\nTest group: a blocked card is told nothing untrue\n"

for skill in "$VALIDATION" "$DONE"; do
  name="$(basename "$(dirname "$skill")")"
  assert_eq "$name does not call every column in between a person's pull" "no" "$(holds "$skill" "is a person's pull")"
  assert_eq "$name names the column the card has to reach first" "yes" \
    "$(line_holding "$skill" '**Any other column** blocks' | grep --quiet --fixed-strings 'the column the card has to reach first' && echo yes || echo no)"
done

printf "\nTest group: validation writes its evidence from this run alone\n"

assert_eq "every tick and Seen line comes from this run" "yes" \
  "$(holds "$VALIDATION" 'Every box and every `Seen:` line is written from what this run saw.')"
assert_eq "a step this run did not see goes back to unticked" "yes" \
  "$(holds "$VALIDATION" 'a step this run did not see hold goes back to `- [ ]` and loses its `Seen:` line')"
assert_eq "a step that does not hold keeps no Seen line" "yes" \
  "$(holds "$VALIDATION" 'no `Seen:` line hangs under it')"

printf "\nTest group: a Bug's (bug) step holds once the broken behaviour is gone\n"

assert_eq "the (bug) step holds when the build no longer does it" "yes" \
  "$(holds "$VALIDATION" 'it holds once the build no longer does it')"
assert_eq "the evidence hangs under the (fix) step" "yes" \
  "$(holds "$VALIDATION" 'hangs under the `(fix)` step')"

printf -- '## Replication/Validation Steps\n\n- [ ] AaUser\n- [ ] Then the export opens a blank page (bug)\n\t- [x] Instead of downloading the report (fix)\n\t\t- Seen: from an earlier build\n\n## Context\n\nkept' \
  | board set "$bug" body "$(cat)" >/dev/null
printf -- '- [x] AaUser\n- [x] Then the export opens a blank page (bug)\n\t- [x] Instead of downloading the report (fix)\n\t\t- Seen: report.csv downloaded\n' \
  | board section "$bug" "Replication/Validation Steps" >/dev/null
assert_eq "the written pair reads back with this run's Seen line two levels down" "- [x] Then the export opens a blank page (bug)
	- [x] Instead of downloading the report (fix)
		- Seen: report.csv downloaded" \
  "$(board show "$bug" --section "Replication/Validation Steps" | sed -n '4,6p')"
assert_eq "the earlier run's Seen line is gone" "no" \
  "$(board show "$bug" --section "Replication/Validation Steps" | grep --quiet 'earlier build' && echo yes || echo no)"

printf "\nTest group: a Timebox records on its Outcome and leaves Expected Outcome as BR wrote it\n"

assert_eq "a Timebox names Outcome in both calls" "yes" "$(holds "$VALIDATION" '`Outcome` on a Timebox')"
assert_eq "Expected Outcome is left as BR wrote it" "yes" "$(holds "$VALIDATION" '`## Expected Outcome` is left as BR wrote it.')"
assert_eq "a Timebox with no Outcome is a defect" "yes" "$(holds "$VALIDATION" 'a Timebox with no `## Outcome` to check')"

board show "$timebox" --section "Outcome" >/dev/null 2>&1
assert_eq "a Timebox with no Outcome yet has nothing to read" "7" "$?"

expected_outcome='## Expected Outcome

1. A recommended library'
printf '%s\n\n## Outcome\n\n**Success**\n\n1. ✅ A recommended library\n\n- Next Steps: FEAT-9\n\n## Context\n\nkept' "$expected_outcome" \
  | board set "$timebox" body "$(cat)" >/dev/null
assert_eq "the Outcome read is not the Expected Outcome" "## Outcome" "$(board show "$timebox" --section "Outcome" | head -n 1)"
printf '**Success**\n\n1. ✅ A recommended library\n\t- Seen: the comparison table under Details\n\n- Next Steps: FEAT-9\n' \
  | board section "$timebox" "Outcome" >/dev/null
assert_eq "the Seen line lands under its Outcome item" "	- Seen: the comparison table under Details" \
  "$(board show "$timebox" --section "Outcome" | grep 'Seen:')"
assert_eq "Expected Outcome is untouched by the write" "$expected_outcome" "$(board show "$timebox" --section "Expected Outcome")"

printf "\nTest group: done checks a split parent's sub-tickets, not a pull request it has none of\n"

assert_eq "a split parent reads each sub-ticket's column" "yes" \
  "$(holds "$DONE" 'show <sub-ticket id> Status')"
assert_eq "a sub-ticket short of Done is named before the walk" "yes" \
  "$(holds "$DONE" 'which sub-ticket and its column')"

printf "\n%d passed, %d failed\n" "$pass" "$fail"
[ "$fail" -eq 0 ]
