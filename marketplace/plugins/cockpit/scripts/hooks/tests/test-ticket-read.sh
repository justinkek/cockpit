#!/usr/bin/env bash

export CLAUDE_SHARED_DIR="$(cd "$(dirname "$0")/../../../../../../agents/claude" && pwd)"

SCRIPT="$(cd "$(dirname "$0")/../.." && pwd)/ticket-read"
BOARD_CARD="$(cd "$(dirname "$0")/../.." && pwd)/board-card"
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

export COCKPIT_BOARD_DIR="$TMPDIR/board"
export CLAUDE_SESSION_ID="ticket-read-test"
export TICKET_CLAIM_LOCK="$TMPDIR/claim-lock"
printf '#!/usr/bin/env bash\nexit 0\n' > "$TICKET_CLAIM_LOCK"
chmod +x "$TICKET_CLAIM_LOCK"

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
  if printf '%s' "$output" | grep --quiet --fixed-strings --regexp="$expected"; then
    printf "  OK  %s\n" "$label"
    pass=$((pass + 1))
  else
    printf "  KO  %s — expected '%s' in output '%s'\n" "$label" "$expected" "$output"
    fail=$((fail + 1))
  fi
}

TAB="$(printf '\t')"

"$BOARD_CARD" init >/dev/null
"$BOARD_CARD" create --kind project --name Home --key HOM >/dev/null
"$BOARD_CARD" create --kind epic --project PRJ-1 --name "an epic" >/dev/null
CARD="$("$BOARD_CARD" create --name "A ticket fetch returns the properties skills read" --status "Ready for BR" --epic EPIC-1 --body - <<'BODY'
## Validation Steps

- [ ] AaUser
- [ ] Given I have a session working a cockpit ticket
- [ ] Then I see the body come back on its own
  - [ ] And the read is cheap

## Context

Handoff from the timebox

## Tech Steps

- [x] And this one is built
BODY
)"
"$BOARD_CARD" claim "$CARD" >/dev/null
"$BOARD_CARD" comment "$CARD" --anchor "Then I see the body come back on its own" --author tester <<< "the golden path only" >/dev/null
"$BOARD_CARD" comment "$CARD" --anchor "this one is built" --author tester <<< "on the tech steps" >/dev/null
"$BOARD_CARD" comment "$CARD" --author tester <<< "ready for TR" >/dev/null

exit_code_of() {
  "$@" >/dev/null 2>&1
  echo "$?"
}

printf "Test group: a property named on the command line prints, one per line\n"

assert_eq "a status prints its name after a tab" "Status${TAB}Ready for BR" "$("$SCRIPT" "$CARD" Status)"
assert_eq "a title prints whole" "Name${TAB}A ticket fetch returns the properties skills read" "$("$SCRIPT" "$CARD" Name)"
assert_eq "a relation prints the id it holds" "Epic${TAB}EPIC-1" "$("$SCRIPT" "$CARD" Epic)"
assert_eq "two properties print in the order asked for" \
  "Epic${TAB}EPIC-1
Status${TAB}Ready for BR" \
  "$("$SCRIPT" "$CARD" Epic Status)"
assert_contains "a stamped column date prints" "Date: Ready for BR${TAB}" "$("$SCRIPT" "$CARD" "Date: Ready for BR")"
assert_eq "an unstamped date prints nothing" "" "$("$SCRIPT" "$CARD" "Date: Done")"
assert_eq "a property holding nothing prints nothing" "" "$("$SCRIPT" "$CARD" PRs)"

printf "\nTest group: naming no property prints the set the skills read\n"

assert_contains "the status is in the default set" "Status" "$("$SCRIPT" "$CARD")"
assert_contains "the claim is in the default set" "Agent: Session Id${TAB}ticket-read-test" "$("$SCRIPT" "$CARD")"

printf "\nTest group: a reference is a card id or it is refused\n"

assert_eq "a lower case id reads the same card" "Status${TAB}Ready for BR" "$("$SCRIPT" "$(printf '%s' "$CARD" | tr '[:upper:]' '[:lower:]')" Status)"
assert_eq "a page url is refused" "2" "$(exit_code_of "$SCRIPT" "https://app.notion.com/p/3b98f3776f4f81a6ab13cd05b1683e96")"
assert_contains "and says what it wanted" "not a card id" "$("$SCRIPT" "https://app.notion.com/p/abc" 2>&1)"
assert_eq "no argument at all is refused" "2" "$(exit_code_of "$SCRIPT")"
assert_eq "a card the board does not hold exits 3" "3" "$(exit_code_of "$SCRIPT" HOM-999 Status)"

printf "\nTest group: a named section prints, and nothing outside it does\n"

section="$("$SCRIPT" "$CARD" --section "Validation Steps")"
assert_eq "the heading comes back with its section" "## Validation Steps" "$(printf '%s\n' "$section" | head -1)"
assert_contains "a checklist item keeps its box" "- [ ] AaUser" "$section"
assert_contains "a nested item keeps its indent" "  - [ ] And the read is cheap" "$section"
assert_eq "the next heading does not come with it" "" "$(printf '%s\n' "$section" | grep '## Context' || true)"
assert_eq "the next section's body does not come with it" "" "$(printf '%s\n' "$section" | grep 'Handoff' || true)"
assert_eq "a section the card does not have exits 7" "7" "$(exit_code_of "$SCRIPT" "$CARD" --section "No Such Section")"
assert_contains "and names the section it looked for" "No Such Section" "$("$SCRIPT" "$CARD" --section "No Such Section" 2>&1)"
assert_eq "a section flag with no heading is refused" "2" "$(exit_code_of "$SCRIPT" "$CARD" --section)"
assert_eq "a heading given with its marker reads the same section" "## Validation Steps" \
  "$("$SCRIPT" "$CARD" --section "## Validation Steps" | head -1)"
assert_eq "a heading that is nothing but a marker is refused" "2" "$(exit_code_of "$SCRIPT" "$CARD" --section "##")"

printf "\nTest group: a comment comes back with the section it is anchored in\n"

assert_contains "an anchored comment reads with its section" "[comment] tester: the golden path only" "$section"
assert_contains "the page's own comment reads at the end" "[comment on the page] tester: ready for TR" "$section"
assert_eq "a comment on another section does not come with it" "" \
  "$(printf '%s\n' "$section" | grep 'on the tech steps' || true)"

printf "\n%d passed, %d failed\n" "$pass" "$fail"
[ "$fail" -eq 0 ]
