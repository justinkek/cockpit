#!/usr/bin/env bash

SCRIPT="$(cd "$(dirname "$0")/../.." && pwd)/ticket-read"
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
  if printf '%s' "$output" | grep --quiet --fixed-strings --regexp="$expected"; then
    printf "  OK  %s\n" "$label"
    pass=$((pass + 1))
  else
    printf "  KO  %s — expected '%s' in output '%s'\n" "$label" "$expected" "$output"
    fail=$((fail + 1))
  fi
}

PAGE="3b98f3776f4f81a6ab13cd05b1683e96"
FIXTURE="$TMPDIR/page.json"
ERROR_FIXTURE="$TMPDIR/unauthorized.json"
TAB="$(printf '\t')"

cat > "$FIXTURE" <<'JSON'
{
  "object": "page",
  "id": "3b98f377-6f4f-81a6-ab13-cd05b1683e96",
  "properties": {
    "Name": { "type": "title", "title": [ { "plain_text": "A ticket fetch returns " }, { "plain_text": "the properties skills read" } ] },
    "Status": { "type": "status", "status": { "name": "In Dev" } },
    "Type": { "type": "select", "select": { "name": "Feature" } },
    "Complexity": { "type": "number", "number": 8 },
    "Back from CR": { "type": "number", "number": 0 },
    "Timebox (mins)": { "type": "number", "number": null },
    "Epic": { "type": "relation", "relation": [ { "id": "3af8f377-6f4f-8140-b032-ffbc3fb09be3" } ] },
    "Dependent on": { "type": "relation", "relation": [] },
    "Assignee": { "type": "people", "people": [ { "id": "89f46ffe-e74b-44b3-8c33-6d9a3f8b92cf" } ] },
    "Agent: Session Id": { "type": "rich_text", "rich_text": [ { "plain_text": "09248d51 @ 2026-08-12T07:28:19Z" } ] },
    "PRs": { "type": "rich_text", "rich_text": [] },
    "Ticket No.": { "type": "unique_id", "unique_id": { "prefix": "COC", "number": 585 } },
    "Date: Ready for BR": { "type": "date", "date": { "start": "2026-08-12T07:29:00.000Z" } },
    "Date: Done": { "type": "date", "date": null },
    "Duration: In Dev (hrs)": { "type": "formula", "formula": { "type": "number", "number": 3 } },
    "Project": { "type": "rollup", "rollup": { "type": "array", "array": [] } }
  }
}
JSON

cat > "$ERROR_FIXTURE" <<'JSON'
{ "object": "error", "status": 401, "code": "unauthorized", "message": "API token is invalid." }
JSON

RATE_LIMIT_FIXTURE="$TMPDIR/rate-limited.json"
cat > "$RATE_LIMIT_FIXTURE" <<'JSON'
{ "object": "error", "status": 429, "code": "rate_limited", "message": "You have been rate limited." }
JSON

SERVER_ERROR_FIXTURE="$TMPDIR/server-error.json"
cat > "$SERVER_ERROR_FIXTURE" <<'JSON'
{ "object": "error", "status": 502, "code": "service_unavailable", "message": "Upstream is unavailable." }
JSON

BLOCKS_FIXTURE="$TMPDIR/blocks.tsv"
COMMENTS_FIXTURE="$TMPDIR/comments.jsonl"

cat > "$BLOCKS_FIXTURE" <<TSV
blk-validation${TAB}0${TAB}heading_2${TAB}Validation Steps
blk-actor${TAB}0${TAB}to_do${TAB}AaUser
blk-given${TAB}0${TAB}to_do${TAB}Given I have a session working a cockpit ticket
blk-then${TAB}0${TAB}to_do${TAB}Then I see the body come back on its own
blk-and${TAB}1${TAB}to_do${TAB}And the read is cheap
blk-hash${TAB}0${TAB}paragraph${TAB}# not a heading, just a line that starts with a hash
blk-context${TAB}0${TAB}heading_2${TAB}Context
blk-handoff${TAB}0${TAB}paragraph${TAB}Handoff from the timebox
blk-tech${TAB}0${TAB}heading_2${TAB}Tech Steps
blk-layer${TAB}0${TAB}toggle${TAB}Agent Layer
blk-done${TAB}1${TAB}to_do_checked${TAB}And this one is built
TSV

cat > "$COMMENTS_FIXTURE" <<'JSONL'
{ "block": "blk-then", "text": "the golden path only" }
{ "block": "blk-and", "text": "and it is cheap" }
{ "block": "blk-layer", "text": "on the tech steps" }
{ "block": "3b98f3776f4f81a6ab13cd05b1683e96", "text": "ready for TR" }
JSONL

read_page() {
  TICKET_READ_FIXTURE="$FIXTURE" "$SCRIPT" "$@" 2>/dev/null
}

read_section() {
  NOTION_LINES_FIXTURE="$BLOCKS_FIXTURE" NOTION_COMMENTS_FIXTURE="$COMMENTS_FIXTURE" \
    "$SCRIPT" "$@" 2>/dev/null
}

exit_code_of() {
  "$@" >/dev/null 2>&1
  echo "$?"
}

printf "Test group: a property named on the command line prints, one per line\n"

assert_eq "a status prints its name after a tab" "Status${TAB}In Dev" \
  "$(read_page "$PAGE" Status)"
assert_eq "a select prints its name" "Type${TAB}Feature" \
  "$(read_page "$PAGE" Type)"
assert_eq "a title joins its runs" "Name${TAB}A ticket fetch returns the properties skills read" \
  "$(read_page "$PAGE" Name)"
assert_eq "a number prints as written" "Complexity${TAB}8" \
  "$(read_page "$PAGE" Complexity)"
assert_eq "a relation prints the ids it holds" "Epic${TAB}3af8f377-6f4f-8140-b032-ffbc3fb09be3" \
  "$(read_page "$PAGE" Epic)"
assert_eq "a person prints their id" "Assignee${TAB}89f46ffe-e74b-44b3-8c33-6d9a3f8b92cf" \
  "$(read_page "$PAGE" Assignee)"
assert_eq "a unique id prints prefix and number" "Ticket No.${TAB}COC-585" \
  "$(read_page "$PAGE" "Ticket No.")"
assert_eq "two properties print in the order asked for" \
  "Type${TAB}Feature
Status${TAB}In Dev" \
  "$(read_page "$PAGE" Type Status)"

printf "\nTest group: a property not named does not print\n"

assert_eq "asking for one property prints one line" "Status${TAB}In Dev" \
  "$(read_page "$PAGE" Status)"
assert_eq "a rich text holding nothing prints nothing" "" \
  "$(read_page "$PAGE" PRs)"
assert_eq "a relation holding nothing prints nothing" "" \
  "$(read_page "$PAGE" "Dependent on")"
assert_eq "a number holding nothing prints nothing" "" \
  "$(read_page "$PAGE" "Timebox (mins)")"
assert_eq "a number holding zero is not that case" "Back from CR${TAB}0" \
  "$(read_page "$PAGE" "Back from CR")"
assert_eq "a property the page does not have prints nothing" "" \
  "$(read_page "$PAGE" "No Such Property")"

printf "\nTest group: a formula and a rollup have no branch to print through\n"

assert_eq "a formula named by hand prints nothing" "" \
  "$(read_page "$PAGE" "Duration: In Dev (hrs)")"
assert_eq "a rollup named by hand prints nothing" "" \
  "$(read_page "$PAGE" Project)"
assert_eq "naming one is not an error" "0" \
  "$(exit_code_of env TICKET_READ_FIXTURE="$FIXTURE" "$SCRIPT" "$PAGE" "Duration: In Dev (hrs)")"

printf "\nTest group: a date field prints only once the board has stamped it\n"

assert_eq "a stamped field prints its start" "Date: Ready for BR${TAB}2026-08-12T07:29:00.000Z" \
  "$(read_page "$PAGE" "Date: Ready for BR")"
assert_eq "an unstamped field prints nothing" "" \
  "$(read_page "$PAGE" "Date: Done")"

printf "\nTest group: naming no property prints the set the skills read\n"

assert_contains "the status is in the default set" "Status" "$(read_page "$PAGE")"
assert_contains "the epic is in the default set" "Epic" "$(read_page "$PAGE")"
assert_eq "no formula reaches the default set" "" \
  "$(read_page "$PAGE" | grep 'Duration:' || true)"
assert_eq "no unstamped date reaches the default set" "" \
  "$(read_page "$PAGE" | grep 'Date:' || true)"

printf "\nTest group: a page reference is read out of whatever form it arrives in\n"

assert_eq "a dashed uuid resolves" "Status${TAB}In Dev" \
  "$(read_page "3b98f377-6f4f-81a6-ab13-cd05b1683e96" Status)"
assert_eq "a titled url with a query string resolves" "Status${TAB}In Dev" \
  "$(read_page "https://app.notion.com/p/m33/A-ticket-fetch-$PAGE?source=copy_link" Status)"
assert_eq "a reference holding no page id is refused" "2" \
  "$(exit_code_of env TICKET_READ_FIXTURE="$FIXTURE" "$SCRIPT" "not-a-page")"
assert_eq "a long slug carrying no id is refused rather than read as one" "2" \
  "$(exit_code_of env TICKET_READ_FIXTURE="$FIXTURE" "$SCRIPT" "https://app.notion.com/p/m33/A-ticket-fetch-returns-the-properties-skills-read")"
assert_contains "and says what it was looking for" "hexadecimal page id" \
  "$(env TICKET_READ_FIXTURE="$FIXTURE" "$SCRIPT" "https://app.notion.com/p/m33/A-ticket-fetch-returns-the-properties-skills-read" 2>&1 || true)"
assert_eq "no argument at all is refused" "2" \
  "$(exit_code_of env TICKET_READ_FIXTURE="$FIXTURE" "$SCRIPT")"

printf "\nTest group: a read that cannot happen says so rather than printing nothing\n"

assert_eq "no credential and no fixture exits 3" "3" \
  "$(exit_code_of env USER=no-such-user-holds-this-token "$SCRIPT" "$PAGE" Status)"
assert_contains "and names the setup step" "add-generic-password" \
  "$(env USER=no-such-user-holds-this-token "$SCRIPT" "$PAGE" Status 2>&1 || true)"
assert_eq "a rejected token exits 4" "4" \
  "$(exit_code_of env TICKET_READ_FIXTURE="$ERROR_FIXTURE" "$SCRIPT" "$PAGE" Status)"
assert_contains "and says to replace it" "expired or revoked" \
  "$(env TICKET_READ_FIXTURE="$ERROR_FIXTURE" "$SCRIPT" "$PAGE" Status 2>&1 || true)"

printf "\nTest group: being rate limited is not the same answer as an unreadable page\n"

assert_eq "a rate limited body exits 6" "6" \
  "$(exit_code_of env TICKET_READ_FIXTURE="$RATE_LIMIT_FIXTURE" "$SCRIPT" "$PAGE" Status)"
assert_eq "a 429 with no such body exits 6 too" "6" \
  "$(exit_code_of env TICKET_READ_FIXTURE="$FIXTURE" TICKET_READ_FIXTURE_STATUS=429 "$SCRIPT" "$PAGE" Status)"
assert_contains "the wait comes from the retry-after header" "wait 45 seconds" \
  "$(env TICKET_READ_FIXTURE="$RATE_LIMIT_FIXTURE" TICKET_READ_FIXTURE_RETRY_AFTER=45 "$SCRIPT" "$PAGE" Status 2>&1 || true)"
assert_contains "and falls back to a wait when the header is absent" "wait 30 seconds" \
  "$(env TICKET_READ_FIXTURE="$RATE_LIMIT_FIXTURE" "$SCRIPT" "$PAGE" Status 2>&1 || true)"
assert_eq "a server error is still unreadable" "5" \
  "$(exit_code_of env TICKET_READ_FIXTURE="$SERVER_ERROR_FIXTURE" TICKET_READ_FIXTURE_STATUS=502 "$SCRIPT" "$PAGE" Status)"
assert_contains "and names the status it answered with" "answered 502" \
  "$(env TICKET_READ_FIXTURE="$SERVER_ERROR_FIXTURE" TICKET_READ_FIXTURE_STATUS=502 "$SCRIPT" "$PAGE" Status 2>&1 || true)"

printf "\nTest group: a named section prints, and nothing outside it does\n"

assert_eq "the heading comes back with its section" "## Validation Steps" \
  "$(read_section "$PAGE" --section "Validation Steps" | head --lines=1)"
assert_contains "a checklist item keeps its box" "- [ ] AaUser" \
  "$(read_section "$PAGE" --section "Validation Steps")"
assert_contains "a nested item keeps its indent" "${TAB}- [ ] And the read is cheap" \
  "$(read_section "$PAGE" --section "Validation Steps")"
assert_contains "a ticked item keeps its tick" "- [x] And this one is built" \
  "$(read_section "$PAGE" --section "Tech Steps")"
assert_contains "a paragraph opening with a hash does not end the section" "# not a heading, just a line that starts with a hash" \
  "$(read_section "$PAGE" --section "Validation Steps")"
assert_eq "the next heading does not come with it" "" \
  "$(read_section "$PAGE" --section "Validation Steps" | grep 'Context' || true)"
assert_eq "the next section's body does not come with it" "" \
  "$(read_section "$PAGE" --section "Validation Steps" | grep 'Handoff' || true)"
assert_eq "no property reaches the section output" "" \
  "$(read_section "$PAGE" --section "Validation Steps" | grep 'Status' || true)"
assert_eq "a section the page does not have exits 7" "7" \
  "$(exit_code_of env NOTION_LINES_FIXTURE="$BLOCKS_FIXTURE" NOTION_COMMENTS_FIXTURE="$COMMENTS_FIXTURE" "$SCRIPT" "$PAGE" --section "No Such Section")"
assert_contains "and names the section it looked for" "No Such Section" \
  "$(env NOTION_LINES_FIXTURE="$BLOCKS_FIXTURE" NOTION_COMMENTS_FIXTURE="$COMMENTS_FIXTURE" "$SCRIPT" "$PAGE" --section "No Such Section" 2>&1 || true)"
assert_eq "a section flag with no heading is refused" "2" \
  "$(exit_code_of env NOTION_LINES_FIXTURE="$BLOCKS_FIXTURE" "$SCRIPT" "$PAGE" --section)"
assert_eq "a heading given with its marker reads the same section" "## Validation Steps" \
  "$(read_section "$PAGE" --section "## Validation Steps" | head --lines=1)"
assert_eq "a section the page does not have exits 7 with its marker too" "7" \
  "$(exit_code_of env NOTION_LINES_FIXTURE="$BLOCKS_FIXTURE" NOTION_COMMENTS_FIXTURE="$COMMENTS_FIXTURE" "$SCRIPT" "$PAGE" --section "## No Such Section")"
assert_eq "a heading that is nothing but a marker is refused" "2" \
  "$(exit_code_of env NOTION_LINES_FIXTURE="$BLOCKS_FIXTURE" "$SCRIPT" "$PAGE" --section "## ")"

printf "\nTest group: a section read that could not happen is not a missing section\n"

assert_eq "a rejected token on a section read exits 4" "4" \
  "$(exit_code_of env NOTION_LINES_FIXTURE="$BLOCKS_FIXTURE" NOTION_LINES_FIXTURE_STATUS=401 "$SCRIPT" "$PAGE" --section "Validation Steps")"
assert_eq "a rate limited section read exits 6" "6" \
  "$(exit_code_of env NOTION_LINES_FIXTURE="$BLOCKS_FIXTURE" NOTION_LINES_FIXTURE_STATUS=429 "$SCRIPT" "$PAGE" --section "Validation Steps")"
assert_eq "a server error on a section read exits 5" "5" \
  "$(exit_code_of env NOTION_LINES_FIXTURE="$BLOCKS_FIXTURE" NOTION_LINES_FIXTURE_STATUS=502 "$SCRIPT" "$PAGE" --section "Validation Steps")"
assert_eq "a section that is really there is still read" "0" \
  "$(exit_code_of env NOTION_LINES_FIXTURE="$BLOCKS_FIXTURE" NOTION_LINES_FIXTURE_STATUS=200 "$SCRIPT" "$PAGE" --section "Validation Steps")"

printf "\nTest group: a comment comes back beside the line it hangs off\n"

assert_contains "a line's comment reads under that line" "[comment] the golden path only" \
  "$(read_section "$PAGE" --section "Validation Steps")"
assert_contains "a comment sits at its line's indent" "${TAB}[comment] and it is cheap" \
  "$(read_section "$PAGE" --section "Validation Steps")"
assert_contains "the page's own comment reads at the end" "[comment on the page] ready for TR" \
  "$(read_section "$PAGE" --section "Validation Steps")"
assert_eq "a comment on another section does not come with it" "" \
  "$(read_section "$PAGE" --section "Validation Steps" | grep 'on the tech steps' || true)"

printf "\n%d passed, %d failed\n" "$pass" "$fail"
[ "$fail" -eq 0 ]
