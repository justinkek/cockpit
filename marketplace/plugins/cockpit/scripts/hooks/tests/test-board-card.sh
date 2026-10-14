#!/usr/bin/env bash

SCRIPTS="$(cd "$(dirname "$0")/../.." && pwd)"
HOOKS="$SCRIPTS/hooks"
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
field() { stub show "$1" --json | jq --raw-output "$2"; }
last_commit() { git -C "$COCKPIT_BOARD_DIR" log -1 --format="$1"; }

printf "Test group: a stub is created and read with nothing but the scripts\n"

stub init >/dev/null
assert_eq "the board is its own git repository" "true" "$([ -d "$COCKPIT_BOARD_DIR/.git" ] && echo true)"
assert_eq "init is committed on its own" "init" "$(last_commit %s)"
assert_eq "a feature is numbered with FEAT" "FEAT-1" "$(stub create --name 'Parent: with a colon')"
assert_eq "a bug is numbered with BUG and shares the sequence" "BUG-2" "$(stub create --name Child --type Bug)"
assert_eq "a create is committed under its verb and id" "create BUG-2" "$(last_commit %s)"
assert_eq "a commit carries the board's own identity with no git config to borrow" "board-card" "$(last_commit %an)"
assert_eq "a new stub starts in Backlog" "Backlog" "$(field FEAT-1 .status)"
assert_eq "a name with a colon survives the round trip" "Parent: with a colon" "$(field FEAT-1 .name)"
assert_eq "ticket-read answers for a stub id" "Status	Backlog" "$(bash "$SCRIPTS/ticket-read" FEAT-1 Status)"
stub create --name Bad --type Epic >/dev/null 2>&1
assert_eq "a type outside the three is refused" "2" "$?"
stub create --name Bad --source https://example.com >/dev/null 2>&1
assert_eq "a card links to no other board" "2" "$?"

printf "\nTest group: a stub moves between columns\n"

stub move BUG-2 "In BR" >/dev/null
assert_eq "move lands on the column" "In BR" "$(field BUG-2 .status)"
first_stamp="$(field BUG-2 '.dates["In BR"]')"
assert_eq "a date-stamped column is stamped on arrival" "true" "$([ -n "$first_stamp" ] && [ "$first_stamp" != null ] && echo true)"
sleep 1
stub move BUG-2 Backlog >/dev/null
moved="$(field BUG-2 .moved)"
assert_eq "a hop into a column with no date stamp still records when it moved" "true" \
  "$([ "$moved" != null ] && [[ "$moved" > "$first_stamp" ]] && echo true)"
assert_eq "and stamps no date for that column" "false" "$(field BUG-2 '.dates | has("Backlog")')"
assert_eq "the move time sits after the creation time in the file" "moved" \
  "$(sed -n '/^created:/{n;p;}' "$COCKPIT_BOARD_DIR/cards/BUG-2.md" | cut -d: -f1)"
stub move BUG-2 "In BR" >/dev/null
assert_eq "re-entering a column keeps the first stamp" "$first_stamp" "$(field BUG-2 '.dates["In BR"]')"
stub move BUG-2 "In Space" >/dev/null 2>&1
assert_eq "a column the board does not have is refused" "2" "$?"

stub walk FEAT-1 "In Dev" --skip "Sprint Backlog" >/dev/null
assert_eq "walk lands on the target" "In Dev" "$(field FEAT-1 .status)"
assert_eq "a whole walk is one commit" "walk FEAT-1" "$(last_commit %s)"
assert_eq "walk stamps every stamped column it passes" "Ready for BR In BR Ready for TR In TR Ready for Sprint In Dev" \
  "$(field FEAT-1 '.dates | keys_unsorted | join(" ")')"
stub walk FEAT-1 "In BR" >/dev/null 2>&1
assert_eq "a walk backwards is refused" "4" "$?"
stub walk FEAT-1 Done --skip Done >/dev/null 2>&1
assert_eq "Done cannot be skipped" "2" "$?"
stub move BUG-2 Deprioritised >/dev/null
assert_eq "a card can be parked in Deprioritised" "Deprioritised" "$(field BUG-2 .status)"
stub walk BUG-2 Done >/dev/null 2>&1
assert_eq "a walk does not start from a parked card" "2" "$?"
stub move BUG-2 "In BR" >/dev/null

printf "\nTest group: complexity and links\n"

stub set BUG-2 complexity 4 >/dev/null 2>&1
assert_eq "complexity off the Fibonacci list is refused" "2" "$?"
stub set BUG-2 complexity 5 >/dev/null
assert_eq "a Fibonacci complexity is kept" "5" "$(field BUG-2 .complexity)"
stub set BUG-2 complexity "1 2" >/dev/null 2>&1
assert_eq "two numbers are not one complexity" "2" "$?"
assert_eq "and the refused value leaves the record whole" "Child" "$(field BUG-2 .name)"
stub set BUG-2 complexity 0 >/dev/null 2>&1
assert_eq "0 is refused on a stub with no children" "2" "$?"
stub set BUG-2 complexity "" >/dev/null
assert_eq "an empty complexity clears it" "null" "$(field BUG-2 .complexity)"
stub set BUG-2 complexity 5 >/dev/null
stub link FEAT-1 BUG-2 >/dev/null
assert_eq "the parent lists the child" '["BUG-2"]' "$(field FEAT-1 '.dependent_on | tojson')"
assert_eq "the child names the parent" '["FEAT-1"]' "$(field BUG-2 '.dependency_for | tojson')"
assert_eq "a split parent drops to complexity 0" "0" "$(field FEAT-1 .complexity)"
stub set FEAT-1 complexity 3 >/dev/null 2>&1
assert_eq "a split parent refuses any other complexity" "2" "$?"
stub unlink FEAT-1 BUG-2 >/dev/null
assert_eq "unlinking empties both sides" "[] []" "$(field FEAT-1 '.dependent_on | tojson') $(field BUG-2 '.dependency_for | tojson')"

stub set BUG-2 rank -12.5 >/dev/null
assert_eq "a field with no property name of its own still sets cleanly" "0" "$?"
assert_eq "a rank orders a card within its column" "-12.5" "$(field BUG-2 .rank)"
stub set BUG-2 rank first >/dev/null 2>&1
assert_eq "a rank that is not a number is refused" "2" "$?"

printf "\nTest group: a claim is held by one session\n"

assert_eq "the first session takes it" "claimed FEAT-1" "$(stub claim FEAT-1)"
assert_eq "the stub names its holder" "session-one" "$(field FEAT-1 .session)"
CLAUDE_SESSION_ID=session-two bash "$SCRIPTS/board-card" claim FEAT-1 >/dev/null 2>&1
assert_eq "a second session is told no" "1" "$?"
CLAUDE_SESSION_ID=session-two bash "$SCRIPTS/board-card" release FEAT-1 >/dev/null 2>&1
assert_eq "a second session cannot release it" "1" "$?"
stub release-session session-one >/dev/null
assert_eq "the session-end sweep clears the holder" "null" "$(field FEAT-1 .session)"

printf "\nTest group: the gate hooks accept a stub id\n"

hook_input() {
  jq --null-input --compact-output --arg command "$1" \
    '{tool_name: "Bash", session_id: "hook-session", tool_input: {command: $command}}'
}

HOME="$TMPDIR/home" bash "$HOOKS/require-ticket.sh" <<<"$(hook_input '"$HOME/.cockpit/scripts/ticket-register" FEAT-1')" >/dev/null
assert_eq "registering a stub id writes the ticket marker" "FEAT-1" \
  "$(cat "$TMPDIR/home/.local/state/claude-ticket-sessions/hook-session.ticket" 2>/dev/null)"
assert_eq "board-card is not denied before registration" "" \
  "$(HOME="$TMPDIR/home2" bash "$HOOKS/require-ticket.sh" <<<"$(hook_input '"$HOME/.cockpit/scripts/board-card" claim FEAT-1')")"
assert_eq "a write other than claim or create is denied before registration" "deny" \
  "$(HOME="$TMPDIR/home2" bash "$HOOKS/require-ticket.sh" <<<"$(hook_input '"$HOME/.cockpit/scripts/board-card" move FEAT-1 Done')" | jq --raw-output '.hookSpecificOutput.permissionDecision')"
assert_eq "require-rename lets a claim through before the session is named" "" \
  "$(HOME="$TMPDIR/home2" bash "$HOOKS/require-rename.sh" <<<"$(hook_input '"$HOME/.cockpit/scripts/board-card" claim FEAT-1')")"

printf "\nTest group: the fields the flow writes\n"

stub set BUG-2 blocked "waiting on the API key" >/dev/null
assert_eq "blocked holds the reason" "Blocked	waiting on the API key" "$(stub show BUG-2 Blocked)"
stub set BUG-2 blocked "" >/dev/null
assert_eq "an empty value clears it" "null" "$(field BUG-2 .blocked)"
assert_eq "a known property holding nothing prints nothing" "" "$(stub show BUG-2 Blocked "Dependent on")"
stub show BUG-2 Blocked >/dev/null
assert_eq "and still succeeds" "0" "$?"
stub show BUG-2 Status "Dependant on" >/dev/null 2>&1
assert_eq "a property name the board does not know is refused" "2" "$?"
assert_eq "and the refusal names it" "true" \
  "$(stub show BUG-2 Status "Dependant on" 2>&1 | grep --quiet --fixed-strings "'Dependant on'" && echo true)"
assert_eq "and nothing prints before the refusal" "" "$(stub show BUG-2 Status "Dependant on" 2>/dev/null)"
stub set BUG-2 prs "https://github.com/o/r/pull/1" >/dev/null
assert_eq "PRs reads back under its property name" "PRs	https://github.com/o/r/pull/1" "$(stub show BUG-2 PRs)"
stub set BUG-2 models.Dev claude-opus-5-5 >/dev/null
assert_eq "a model is recorded per stage" "Model: Dev	claude-opus-5-5" "$(stub show BUG-2 "Model: Dev")"
stub set BUG-2 models.Lunch x >/dev/null 2>&1
assert_eq "a stage outside BR, TR, Dev and CR is refused" "2" "$?"
stub bounce BUG-2 CR >/dev/null
assert_eq "a bounce counts from one" "Back from CR	2" "$(stub bounce BUG-2 CR)"
stub set BUG-2 due 2026-10-20 >/dev/null
assert_eq "due is a date" "2026-10-20" "$(field BUG-2 .due)"
assert_eq "statuses lists the card columns in walk order" "Backlog" "$(stub statuses | head -1)"

printf "\nTest group: a section is written on its own\n"

printf '## Validation Steps\n- [ ] one\n\n## Context\nkept' | stub set BUG-2 body "$(cat)" >/dev/null
printf -- '- [ ] new step' | stub section BUG-2 "Validation Steps" >/dev/null
assert_eq "the section is replaced, a blank line after its heading" "## Validation Steps

- [ ] new step" "$(stub show BUG-2 --section "Validation Steps")"
assert_eq "the section after it is kept" "kept" "$(stub show BUG-2 --section Context | sed -n 2p)"
assert_eq "a section write is committed under its verb and id" "section BUG-2" "$(last_commit %s)"
printf -- 'step one' | stub section BUG-2 "Tech Steps" --after "Validation Steps" >/dev/null
assert_eq "a new section lands after the one named" "## Validation Steps|## Tech Steps|## Context" \
  "$(field BUG-2 .body | grep '^## ' | paste -sd '|' -)"
assert_eq "an added section has a blank line after its heading" "## Tech Steps

step one" "$(stub show BUG-2 --section "Tech Steps")"
printf 'first bounce' | stub section BUG-2 "Back from CR" --under Details >/dev/null
assert_eq "--under adds a missing parent and a subsection one level down" "## Details|### Back from CR" \
  "$(field BUG-2 .body | grep '^##' | tail -2 | paste -sd '|' -)"
printf 'second write' | stub section BUG-2 "Back from CR" --under Details >/dev/null
assert_eq "--under replaces the subsection it finds" "### Back from CR

second write" "$(stub show BUG-2 --section "Back from CR")"
printf 'other' | stub section BUG-2 "Preventions" --under Details >/dev/null
assert_eq "a second subsection is added after the first" "### Back from CR|### Preventions" \
  "$(field BUG-2 .body | grep '^###' | paste -sd '|' -)"
printf '\nalready spaced' | stub section BUG-2 "Preventions" --under Details >/dev/null
assert_eq "content that opens with a blank line gets no second one" "### Preventions

already spaced" "$(stub show BUG-2 --section "Preventions")"
printf -- '- [ ] first' | stub section BUG-2 "Replication/Validation Steps" --before "Validation Steps" >/dev/null
assert_eq "--before puts a new section ahead of the one named" "## Replication/Validation Steps|## Validation Steps" \
  "$(field BUG-2 .body | grep '^## ' | head -2 | paste -sd '|' -)"
assert_eq "a section put ahead has a blank line after its heading" "## Replication/Validation Steps

- [ ] first" "$(stub show BUG-2 --section "Replication/Validation Steps")"
printf -- '' | stub set BUG-2 body "$(field BUG-2 .body | awk '/^## Replication\/Validation Steps$/ { skip = 1; next } /^## / { skip = 0 } !skip')" >/dev/null
assert_eq "the sections before Details are untouched" "## Validation Steps|## Tech Steps|## Context|## Details" \
  "$(field BUG-2 .body | grep '^## ' | paste -sd '|' -)"
stub show BUG-2 --section "Nothing" >/dev/null 2>&1
assert_eq "a missing section exits 7" "7" "$?"

printf "\nTest group: inline comments\n"

assert_eq "a comment on a span of the body is numbered" "c1" "$(printf 'is this right?' | stub comment BUG-2 --anchor "step one" --author justin)"
printf 'not in the body' | stub comment BUG-2 --anchor "absent words" >/dev/null 2>&1
assert_eq "an anchor the body does not hold is refused" "2" "$?"
assert_eq "a reply joins the thread" "c2" "$(printf 'yes' | stub comment BUG-2 --reply c1 --author claude)"
assert_eq "the section read carries its comments" "[comment] justin: is this right?" "$(stub show BUG-2 --section "Tech Steps" | grep '^\[comment\]' | head -1)"
assert_eq "a comment is committed under its verb and id" "comment BUG-2" "$(last_commit %s)"
printf 'unfixed - from step one' | stub section BUG-2 "Machine gates" --under Details >/dev/null
assert_eq "a section quoting another section's anchor does not carry its thread" "" \
  "$(stub show BUG-2 --section "Machine gates" | grep '^\[comment\]')"
assert_eq "nor does the section holding the quote" "" "$(stub show BUG-2 --section Details | grep '^\[comment\]')"
assert_eq "the thread stays with the section its anchor first appears in" "[comment] justin: is this right?" \
  "$(stub show BUG-2 --section "Tech Steps" | grep '^\[comment\]' | head -1)"
stub resolve BUG-2 c1 >/dev/null
assert_eq "a resolve is committed under its verb and id" "resolve BUG-2" "$(last_commit %s)"
assert_eq "a resolved thread leaves the open list" "0" "$(stub comments BUG-2 --json | jq length)"
assert_eq "and stays in the full list" "1" "$(stub comments BUG-2 --all --json | jq length)"

printf 'diagram' > "$TMPDIR/flow.svg"
assert_eq "an attachment is copied beside the board and named relative to it" "attachments/BUG-2/flow.svg" "$(stub attach BUG-2 "$TMPDIR/flow.svg")"
assert_eq "the copy holds the file" "diagram" "$(cat "$COCKPIT_BOARD_DIR/attachments/BUG-2/flow.svg")"
assert_eq "an attachment is committed under its verb and id" "attach BUG-2" "$(last_commit %s)"

printf "\nTest group: epics have their own columns\n"

assert_eq "an epic is numbered on its own" "EPIC-1" "$(stub create --kind epic --name "Local board")"
assert_eq "an epic starts in its first column" "Ready for FD by AI" "$(field EPIC-1 .status)"
stub walk EPIC-1 "Ready for FD" >/dev/null
assert_eq "an epic walks its own columns and stamps them" "Ready for FD by AI In FD by AI Ready for FD" "$(field EPIC-1 '.dates | keys_unsorted | join(" ")')"
stub move EPIC-1 "In Dev" >/dev/null 2>&1
assert_eq "a card column is refused on an epic" "2" "$?"
stub set BUG-2 epic EPIC-1 >/dev/null
assert_eq "a card names its epic by id" "BUG-2" "$(stub list --epic EPIC-1 | cut -f1)"
stub set BUG-2 epic FEAT-1 >/dev/null 2>&1
assert_eq "a card is not an epic" "2" "$?"
stub set BUG-2 epic "" >/dev/null

printf "\nTest group: a card's id follows its type\n"

assert_eq "a timebox is numbered with TIME" "TIME-3" "$(stub create --name Spike --type Timebox)"
stub link FEAT-1 TIME-3 >/dev/null
printf 'note' | stub comment TIME-3 >/dev/null
assert_eq "changing the type renames the card" "renamed TIME-3 to FEAT-3" "$(stub set TIME-3 type Feature | sed -n 1p)"
assert_eq "the old file is gone" "false" "$([ -f "$COCKPIT_BOARD_DIR/cards/TIME-3.md" ] && echo true || echo false)"
assert_eq "the new file holds its id" "FEAT-3" "$(field FEAT-3 .id)"
assert_eq "a link to it follows the rename" '["FEAT-3"]' "$(field FEAT-1 '.dependent_on | tojson')"
assert_eq "its comments follow the rename" "1" "$(stub comments FEAT-3 --json | jq length)"
assert_eq "the rename is one commit naming every record it touched" "set FEAT-1 FEAT-3 TIME-3" "$(last_commit %s)"
stub set FEAT-3 type feature >/dev/null 2>&1
assert_eq "a type outside the three is refused on set" "2" "$?"
assert_eq "and the card keeps its file and its type" "FEAT-3 Feature" "$(field FEAT-3 '"\(.id) \(.type)"')"
stub set EPIC-1 type Bug >/dev/null 2>&1
assert_eq "only a card has a type" "2" "$?"
assert_eq "and the epic is not copied in as a card" "true false" \
  "$([ -f "$COCKPIT_BOARD_DIR/epics/EPIC-1.md" ] && echo true) $([ -f "$COCKPIT_BOARD_DIR/cards/BUG-1.md" ] && echo true || echo false)"
sed 's/"FEAT-3"/"BUG-3"/' "$COCKPIT_BOARD_DIR/cards/FEAT-3.md" > "$COCKPIT_BOARD_DIR/cards/BUG-3.md"
stub set FEAT-3 type Bug >/dev/null 2>&1
assert_eq "a type whose id is already taken is refused" "2" "$?"
assert_eq "before anything is written" "Feature" "$(field FEAT-3 .type)"
assert_eq "so a refused write leaves nothing behind" "" "$(git -C "$COCKPIT_BOARD_DIR" status --short)"
rm "$COCKPIT_BOARD_DIR/cards/BUG-3.md"
stub unlink FEAT-1 FEAT-3 >/dev/null
stub create --name Bad --assignee me >/dev/null 2>&1
assert_eq "a card has no assignee" "2" "$?"

printf "\nTest group: a record carries one emoji as its icon\n"

assert_eq "an icon reads back under its property name" "Icon	🧭" "$(stub set FEAT-1 icon "🧭")"
assert_eq "the icon sits after the name in the file" "icon" "$(sed -n '/^name:/{n;p;}' "$COCKPIT_BOARD_DIR/cards/FEAT-1.md" | cut -d: -f1)"
stub set FEAT-1 icon "👩‍💻" >/dev/null
assert_eq "an emoji joined from several is still one" "👩‍💻" "$(field FEAT-1 .icon)"
stub set FEAT-1 icon "🇬🇧" >/dev/null
assert_eq "so is a flag" "🇬🇧" "$(field FEAT-1 .icon)"
stub set FEAT-1 icon "ok" >/dev/null 2>&1
assert_eq "text is not an icon" "2" "$?"
stub set FEAT-1 icon "🚀🚀" >/dev/null 2>&1
assert_eq "nor are two emoji" "2" "$?"
stub set FEAT-1 icon "" >/dev/null
assert_eq "an empty icon clears it" "null" "$(field FEAT-1 .icon)"
icon_epic="$(stub create --kind epic --name "With an icon" --icon "🧭")"
assert_eq "create takes an icon for any kind" "🧭" "$(field "$icon_epic" .icon)"
stub create --name "Bad icon" --icon "x" >/dev/null 2>&1
assert_eq "and refuses one that is not an emoji" "2" "$?"

printf "\nTest group: a timebox carries its budget in minutes\n"

timebox="$(stub create --name "Spike two" --type Timebox)"
assert_eq "a new timebox starts with an hour" "60" "$(field "$timebox" .timebox_mins)"
assert_eq "the budget reads back under its property name" "Timebox (mins)	90" "$(stub set "$timebox" timebox_mins 90)"
stub set "$timebox" timebox_mins 0 >/dev/null 2>&1
assert_eq "a budget of no minutes is refused" "2" "$?"
stub set "$timebox" timebox_mins 1.5 >/dev/null 2>&1
assert_eq "so is part of a minute" "2" "$?"
stub set "$timebox" timebox_mins "" >/dev/null
assert_eq "an empty budget clears it" "null" "$(field "$timebox" .timebox_mins)"
assert_eq "create takes a budget of its own" "30" "$(field "$(stub create --name "Spike three" --type Timebox --timebox-mins 30)" .timebox_mins)"
assert_eq "a feature starts with none" "null" "$(field "$(stub create --name "No budget")" .timebox_mins)"
stub set EPIC-1 timebox_mins 30 >/dev/null 2>&1
assert_eq "only a card has a timebox" "2" "$?"

printf "\nTest group: a sprint has dates and a capacity\n"

sprint="$(stub create --kind sprint --name "Week 42" --start 2026-10-12 --end 2026-10-16 --dev-days 5 --speed 4)"
assert_eq "create takes a sprint's dates, dev days and speed" "2026-10-12 2026-10-16 5 4" \
  "$(field "$sprint" '"\(.start) \(.end) \(.dev_days) \(.speed)"')"
assert_eq "an end date reads back under its property name" "End Date	2026-10-15" "$(stub set "$sprint" end 2026-10-15)"
stub set "$sprint" speed 3.5 >/dev/null
assert_eq "a speed may be part of a point" "3.5" "$(field "$sprint" .speed)"
stub set "$sprint" start 2026-10-19 >/dev/null 2>&1
assert_eq "a start after the end is refused" "2" "$?"
stub set "$sprint" end 2026-11-31 >/dev/null 2>&1
assert_eq "a day the calendar does not have is refused" "2" "$?"
stub set "$sprint" dev_days five >/dev/null 2>&1
assert_eq "dev days are a number" "2" "$?"
stub set "$sprint" dev_days "" >/dev/null
assert_eq "an empty value clears it" "null" "$(field "$sprint" .dev_days)"
stub create --kind sprint --name Backwards --start 2026-10-16 --end 2026-10-12 >/dev/null 2>&1
assert_eq "create refuses a sprint that ends before it starts" "2" "$?"
stub set FEAT-1 start 2026-10-12 >/dev/null 2>&1
assert_eq "only a sprint has dates" "2" "$?"
stub create --name "Not a sprint" --speed 3 >/dev/null 2>&1
assert_eq "nor does create give a card a speed" "2" "$?"

printf "\nTest group: a project is ranked and moves through three states\n"

project="$(stub create --kind project --name Cockpit --priority 2 --repo https://github.com/o/cockpit)"
assert_eq "a new project has not started" "Not started" "$(field "$project" .status)"
assert_eq "create takes a project's priority and repo" "2 https://github.com/o/cockpit" "$(field "$project" '"\(.priority) \(.repo)"')"
assert_eq "a project's status is set rather than walked" "Status	In progress" "$(stub set "$project" status "In progress")"
stub set "$project" status Bogus >/dev/null 2>&1
assert_eq "a status outside the three is refused" "2" "$?"
stub create --kind project --name Bad --status Bogus >/dev/null 2>&1
assert_eq "and refused on create" "2" "$?"
assert_eq "a priority reads back under its property name" "Priority	5" "$(stub set "$project" priority 5)"
stub set "$project" priority first >/dev/null 2>&1
assert_eq "a priority is a whole number" "2" "$?"
stub set "$project" repo "not a url" >/dev/null 2>&1
assert_eq "a repo is a URL" "2" "$?"
stub set "$project" repo "" >/dev/null
assert_eq "an empty repo clears it" "null" "$(field "$project" .repo)"
assert_eq "list finds a project by its status" "$project" "$(stub list --kind project --status "In progress" | cut -f1)"
stub set FEAT-1 status Done >/dev/null 2>&1
assert_eq "a card's status still changes only through a move or a walk" "2" "$?"
stub set FEAT-1 priority 1 >/dev/null 2>&1
assert_eq "only a project has a priority" "2" "$?"

printf "\nTest group: a reference ticket keeps its fields where TR reads them\n"

reference="$(stub create --kind reference --name "Fix a typo")"
assert_eq "points read back under their property name" "Points	2" "$(stub set "$reference" points 2)"
stub set "$reference" why "One line, no decisions" >/dev/null
stub set "$reference" description "Change one word" >/dev/null
stub set "$reference" domain Tech >/dev/null
stub set "$reference" stack Shell >/dev/null
stub set "$reference" card FEAT-1 >/dev/null
assert_eq "each field sits at the top of the record, as list --kind reference --json gives it" '{"points":2,"why":"One line, no decisions","description":"Change one word","domain":"Tech","stack":"Shell","card":"FEAT-1"}' \
  "$(stub list --kind reference --json | jq --compact-output --arg id "$reference" '.[] | select(.id == $id) | {points, why, description, domain, stack, card}')"
stub set "$reference" reference.points 3 >/dev/null
assert_eq "the old reference.<key> form sets the same field" "3 false" "$(field "$reference" '"\(.points) \(has("reference"))"')"
stub set "$reference" points 4 >/dev/null 2>&1
assert_eq "points off the Fibonacci list are refused" "2" "$?"
stub set "$reference" points "1 2" >/dev/null 2>&1
assert_eq "and so are two numbers" "2 3" "$? $(field "$reference" .points)"
stub set "$reference" domain Ops >/dev/null 2>&1
assert_eq "a domain is Tech or Bizdev" "2" "$?"
stub set "$reference" card EPIC-1 >/dev/null 2>&1
assert_eq "the card is a card" "2" "$?"
stub set "$reference" card FEAT-99 >/dev/null 2>&1
assert_eq "and one the board holds" "3" "$?"
stub set FEAT-1 points 3 >/dev/null 2>&1
assert_eq "only a reference ticket has points" "2" "$?"
printf -- '---\nid: "REF-90"\nname: "Nested"\nstatus: null\npoints: 1\nreference:\n  "points": "5"\n  "why": "set the old way"\ndates: {}\n---\n' > "$COCKPIT_BOARD_DIR/references/REF-90.md"
stub set REF-90 stack Shell >/dev/null
assert_eq "a record written the old way is repaired on its next write" "5 set the old way false" \
  "$(field REF-90 '"\(.points) \(.why) \(has("reference"))"')"

printf "\nTest group: a record is archived and brought back, or copied\n"

assert_eq "archive moves a record off the board" "archived BUG-2" "$(stub archive BUG-2)"
assert_eq "its file, comments and attachments all go under archive/" "true true true false" \
  "$([ -f "$COCKPIT_BOARD_DIR/archive/cards/BUG-2.md" ] && echo true) $([ -f "$COCKPIT_BOARD_DIR/archive/cards/BUG-2.comments.jsonl" ] && echo true) $([ -f "$COCKPIT_BOARD_DIR/archive/attachments/BUG-2/flow.svg" ] && echo true) $([ -e "$COCKPIT_BOARD_DIR/cards/BUG-2.md" ] && echo true || echo false)"
assert_eq "an archive is committed under its verb and id" "archive BUG-2" "$(last_commit %s)"
assert_eq "list leaves it out" "" "$(stub list | cut -f1 | grep --line-regexp BUG-2)"
assert_eq "and --archived lists it" "BUG-2" "$(stub list --archived | cut -f1)"
stub show BUG-2 Status >/dev/null 2>&1
assert_eq "an archived record cannot be read as if it were on the board" "3" "$?"
assert_eq "and the refusal says how to bring it back" "true" "$(stub show BUG-2 Status 2>&1 | grep --quiet 'board-card unarchive BUG-2' && echo true)"
numbered="$(stub create --name "After the archive")"
assert_eq "an archived record's number is not given out again" "true" "$([ "${numbered##*-}" -gt 2 ] && echo true)"
assert_eq "unarchive brings it back with its comments and attachments" "unarchived BUG-2 true true" \
  "$(stub unarchive BUG-2) $([ -f "$COCKPIT_BOARD_DIR/cards/BUG-2.comments.jsonl" ] && echo true) $([ -f "$COCKPIT_BOARD_DIR/attachments/BUG-2/flow.svg" ] && echo true)"
stub unarchive BUG-2 >/dev/null 2>&1
assert_eq "a record on the board is not archived to bring back" "3" "$?"
stub link FEAT-1 BUG-2 >/dev/null
stub archive BUG-2 >/dev/null 2>&1
assert_eq "a linked card is not archived" "2" "$?"
stub unlink FEAT-1 BUG-2 >/dev/null

copy="$(stub duplicate BUG-2)"
assert_eq "a copy is a new card of the same type" "BUG" "${copy%%-*}"
assert_eq "named after the one it copies" "Copy of $(field BUG-2 .name)" "$(field "$copy" .name)"
assert_eq "with its body and complexity" "true $(field BUG-2 .complexity)" "$(stub show BUG-2 --json | jq --arg body "$(field "$copy" .body)" '.body == $body') $(field "$copy" .complexity)"
assert_eq "starting in the first column, with no comments of its own" "Backlog 0" "$(field "$copy" .status) $(stub comments "$copy" --json | jq length)"
assert_eq "a duplicate is committed under its verb and the new id" "duplicate $copy" "$(last_commit %s)"
named="$(stub duplicate EPIC-1 --name "Next month's chores" --status "Ready for FD")"
assert_eq "an epic copies too, under the name and column given" "Next month's chores|Ready for FD" "$(field "$named" '"\(.name)|\(.status)"')"
stub duplicate "$project" >/dev/null 2>&1
assert_eq "only a card or an epic is duplicated" "2" "$?"

printf "\nTest group: a record's history, and undoing its last change\n"

undoable="$(stub create --name "First name")"
stub set "$undoable" name "Second name" >/dev/null
printf 'a question' | stub comment "$undoable" >/dev/null
assert_eq "history lists the record's commits, newest first, one line each" "comment $undoable|set $undoable|create $undoable" \
  "$(stub history "$undoable" | cut -f3 | paste -sd '|' -)"
assert_eq "each line opens with the commit and its time" "true" \
  "$(stub history "$undoable" | head -1 | grep --quiet --extended-regexp '^[0-9a-f]{7,}	[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:]{8}Z	' && echo true)"
assert_eq "undo names the change it took back" "$undoable	undid $(git -C "$COCKPIT_BOARD_DIR" log -1 --format='%h %s')" "$(stub undo "$undoable")"
assert_eq "undoing a comment takes the comment away" "0" "$(stub comments "$undoable" --json | jq length)"
assert_eq "an undo is a write of its own" "undo $undoable" "$(last_commit %s)"
stub undo "$undoable" >/dev/null
assert_eq "undoing the undo puts the change back" "1" "$(stub comments "$undoable" --json | jq length)"
assert_eq "and leaves the change before it alone" "Second name" "$(field "$undoable" .name)"
stub set "$undoable" name "Third name" >/dev/null
stub undo "$undoable" >/dev/null
assert_eq "an undo after a set brings the name back" "Second name 1" "$(field "$undoable" .name) $(stub comments "$undoable" --json | jq length)"
fresh_record="$(stub create --name "Just made")"
stub undo "$fresh_record" >/dev/null 2>&1
assert_eq "a record with no earlier version has nothing to undo" "2" "$?"
stub archive "$undoable" >/dev/null
assert_eq "an archived record keeps its history" "archive $undoable" "$(stub history "$undoable" | head -1 | cut -f3)"
stub unarchive "$undoable" >/dev/null
stub history FEAT-999 >/dev/null 2>&1
assert_eq "a record the board never held has no history" "3" "$?"

printf "\nTest group: days in the column and overrunning are worked out as Notion did\n"

notion_card() {
  printf -- '---\nid: "%s"\nname: "From Notion"\ntype: "%s"\nstatus: "%s"\ncomplexity: %s\ntimebox_mins: %s\ndates:\n%b---\n' \
    "$1" "$2" "$3" "$4" "${6:-null}" "$5" > "$COCKPIT_BOARD_DIR/cards/$1.md"
}
notion_card FEAT-901 Feature "In Dev" 8 '  "In Dev": "2026-09-06T17:40:00.000+01:00"\n'
notion_card FEAT-902 Feature Done 1 '  "In Dev": "2026-08-14T15:35:00.000+01:00"\n  "Ready for CR": "2026-08-15T06:25:00.000+01:00"\n  "Done": "2026-08-15T07:00:00.000+01:00"\n'
notion_card FEAT-903 Feature Done 5 '  "In Dev": "2026-09-03T10:40:00.000+01:00"\n  "Ready for CR": "2026-09-03T13:02:00.000+01:00"\n'
notion_card TIME-904 Timebox Done null '  "In Dev": "2026-08-15T08:51:00.000+01:00"\n' 120
notion_card TIME-905 Timebox Done null '  "In Dev": "2026-08-19T07:41:00.000+01:00"\n  "Ready for CR": "2026-08-19T07:52:00.000+01:00"\n' 60
notion_card FEAT-906 Feature Backlog null ''
derived() { COCKPIT_NOW=2026-10-13T16:45:51Z stub show "$1" --json | jq --raw-output '"\(.days_in_column) \(.overrunning)"'; }
assert_eq "in dev since a Sunday, 27 working days on and past 8 points of time" "27 true" "$(derived FEAT-901)"
assert_eq "an evening and a Saturday morning count only the evening's last working minutes" "0 true" "$(derived FEAT-902)"
assert_eq "a few hours on a 5 is not overrunning, and Done counts no days" "0 false" "$(derived FEAT-903)"
assert_eq "a timebox never handed to review runs on to now" "0 true" "$(derived TIME-904)"
assert_eq "a timebox closed before the working day began used none of it" "0 false" "$(derived TIME-905)"
assert_eq "a card that never reached In Dev is not overrunning" "0 false" "$(derived FEAT-906)"
assert_eq "list carries the same values" "27 true" \
  "$(COCKPIT_NOW=2026-10-13T16:45:51Z stub list --json | jq --raw-output '.[] | select(.id == "FEAT-901") | "\(.days_in_column) \(.overrunning)"')"
assert_eq "and none of it is written to the record" "" "$(grep --extended-regexp '^(days_in_column|overrunning):' "$COCKPIT_BOARD_DIR/cards/FEAT-901.md")"
assert_eq "an epic carries neither" "false" "$(stub show EPIC-1 --json | jq 'has("overrunning")')"
rm "$COCKPIT_BOARD_DIR"/cards/FEAT-90[1-6].md "$COCKPIT_BOARD_DIR"/cards/TIME-90[45].md

printf "\nTest group: a record says when it last changed\n"

COCKPIT_NOW=2026-10-14T09:00:00Z stub set BUG-2 name "Stamped" >/dev/null
assert_eq "a write stamps the time it changed the record" "2026-10-14T09:00:00Z" "$(field BUG-2 .updated)"
assert_eq "the stamp sits after the creation and move times in the file" "updated" \
  "$(sed -n '/^moved:/{n;p;}' "$COCKPIT_BOARD_DIR/cards/BUG-2.md" | cut -d: -f1)"
COCKPIT_NOW=2026-10-14T10:00:00Z stub set BUG-2 name "Stamped" >/dev/null
assert_eq "a write that changes nothing leaves the stamp alone" "2026-10-14T09:00:00Z" "$(field BUG-2 .updated)"
printf 'a note' | COCKPIT_NOW=2026-10-14T11:00:00Z stub comment BUG-2 >/dev/null
assert_eq "a comment counts as a change to its record" "2026-10-14T11:00:00Z" "$(field BUG-2 .updated)"
COCKPIT_NOW=2026-10-14T12:00:00Z stub resolve BUG-2 "$(stub comments BUG-2 --json | jq --raw-output '.[-1].thread')" >/dev/null
assert_eq "and so does resolving one" "2026-10-14T12:00:00Z" "$(field BUG-2 .updated)"
fresh="$(COCKPIT_NOW=2026-10-14T13:00:00Z stub create --name Fresh)"
assert_eq "a new record is stamped when it is made" "2026-10-14T13:00:00Z 2026-10-14T13:00:00Z" "$(field "$fresh" '"\(.created) \(.updated)"')"

printf "\nTest group: every write is a commit in the board's own repository\n"

stub set BUG-2 epic EPIC-1 >/dev/null
assert_eq "one field change is one changed line beside the stamp of when it changed" '-epic: null
+epic: "EPIC-1"' "$(git -C "$COCKPIT_BOARD_DIR" show --unified=0 --format= HEAD | grep '^[-+][a-z]' | grep --invert-match '^[-+]updated:')"
assert_eq "nothing is left uncommitted, and the lock never reaches git" "" "$(git -C "$COCKPIT_BOARD_DIR" status --short)"
commits_before="$(git -C "$COCKPIT_BOARD_DIR" rev-list --count HEAD)"
stub move BUG-2 "$(field BUG-2 .status)" >/dev/null
assert_eq "a write that changes nothing still succeeds" "0" "$?"
assert_eq "and makes no commit" "$commits_before" "$(git -C "$COCKPIT_BOARD_DIR" rev-list --count HEAD)"
assert_eq "the board is never given a remote" "" "$(git -C "$COCKPIT_BOARD_DIR" remote)"
commits_before="$(git -C "$COCKPIT_BOARD_DIR" rev-list --count HEAD)"
stub init >/dev/null
assert_eq "init on a board already made commits nothing" "$commits_before" "$(git -C "$COCKPIT_BOARD_DIR" rev-list --count HEAD)"

printf '\nedited by hand\n' >> "$COCKPIT_BOARD_DIR/cards/FEAT-1.md"
stub move BUG-2 Backlog >/dev/null
assert_eq "a change found before a write is committed on its own, ahead of the write" "move BUG-2|unrecorded FEAT-1" \
  "$(git -C "$COCKPIT_BOARD_DIR" log -2 --format=%s | paste -sd '|' -)"

git init --quiet "$TMPDIR/other"
GIT_DIR="$TMPDIR/other/.git" GIT_INDEX_FILE="$TMPDIR/other/.git/index" \
  stub move BUG-2 "In BR" >/dev/null
assert_eq "a repository named by the caller's git variables never takes the commit" "0" "$(git -C "$TMPDIR/other" rev-list --all --count)"
assert_eq "the board's own repository does" "move BUG-2" "$(last_commit %s)"

printf '#!/bin/sh\nexit 1\n' > "$COCKPIT_BOARD_DIR/.git/hooks/pre-commit"
chmod +x "$COCKPIT_BOARD_DIR/.git/hooks/pre-commit"
git -C "$COCKPIT_BOARD_DIR" config commit.gpgsign true
stub move BUG-2 Backlog >/dev/null 2>&1
status=$?
assert_eq "a commit hook or a signing setting does not stop the commit" "0 move BUG-2" "$status $(last_commit %s)"
rm "$COCKPIT_BOARD_DIR/.git/hooks/pre-commit"
git -C "$COCKPIT_BOARD_DIR" config --unset commit.gpgsign

: > "$COCKPIT_BOARD_DIR/.git/index.lock"
stub set BUG-2 name "Held up" >/dev/null 2>&1
status=$?
assert_eq "a write git will not commit still lands, and says so" "6 Held up" "$status $(field BUG-2 .name)"
rm "$COCKPIT_BOARD_DIR/.git/index.lock"
: > "$COCKPIT_BOARD_DIR/.git/index.lock"
touch -t 202001010000 "$COCKPIT_BOARD_DIR/.git/index.lock"
stub set FEAT-1 name "Later" >/dev/null 2>&1
assert_eq "a git lock older than a minute is cleared" "0" "$?"
assert_eq "and the write it held up is committed on its own first" "set FEAT-1|unrecorded BUG-2" \
  "$(git -C "$COCKPIT_BOARD_DIR" log -2 --format=%s | paste -sd '|' -)"
assert_eq "leaving nothing uncommitted" "" "$(git -C "$COCKPIT_BOARD_DIR" status --short)"

printf "\n%d passed, %d failed\n" "$pass" "$fail"
[ "$fail" -eq 0 ]
