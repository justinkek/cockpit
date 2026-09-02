#!/usr/bin/env bash
#
# Test: a line nested under another line resolves to its own block.
#
# That is the defect the script exists for — three attempts with the MCP
# create-comment tool put the comment on the parent `Then` instead of the `And`
# written under it, and Notion has no delete-comment API to take it back with.
#
# A blocks fixture stands in for the API, so the test needs no credential and no
# network.

SCRIPT="$(cd "$(dirname "$0")/../.." && pwd)/ticket-comment-line"
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

PAGE="3b48f377-6f4f-8176-81e0-cf7d6cd422a4"
THEN_BLOCK="3b48f3776f4f80000000000000000t01"
AND_BLOCK="3b48f3776f4f80000000000000000a01"

# The page as notion_page_blocks returns it: <id><TAB><text>, one line per
# block, children flattened in alongside their parents.
FIXTURE="$TMPDIR/blocks.tsv"
{
  printf '%s\t%s\n' "3b48f3776f4f80000000000000000u01" "AaUser"
  printf '%s\t%s\n' "3b48f3776f4f80000000000000000g01" "Given I moved a ticket into a by-AI refinement column"
  printf '%s\t%s\n' "$THEN_BLOCK" "Then I see a comment anchored to each line the session needs my decision on"
  printf '%s\t%s\n' "$AND_BLOCK" "And each comment states the proposed wording and one reason for it"
  printf '%s\t%s\n' "3b48f3776f4f80000000000000000a02" "And the session asked me nothing in chat"
  # A second scenario repeating the same Given, which is how a page comes to
  # hold two blocks a caller's line could mean.
  printf '%s\t%s\n' "3b48f3776f4f80000000000000000g02" "Given I moved a ticket into a by-AI refinement column"
} >"$FIXTURE"

run() {
  NOTION_BLOCKS_FIXTURE="$FIXTURE" TICKET_COMMENT_LINE_DRY_RUN=1 \
    bash "$SCRIPT" "$PAGE" "$1" "${2:-a suggestion}" "${3:-a reason}" 2>/dev/null
}

exit_code() {
  NOTION_BLOCKS_FIXTURE="$FIXTURE" TICKET_COMMENT_LINE_DRY_RUN=1 \
    bash "$SCRIPT" "$PAGE" "$1" "a suggestion" "a reason" >/dev/null 2>&1
  echo $?
}

anchor() { run "$1" | jq -r '.parent.block_id // empty'; }

printf "Test group: the line the caller named is the line commented on\n"

assert_eq "a nested And resolves to itself, not to its Then" "$AND_BLOCK" \
  "$(anchor 'And each comment states the proposed wording and one reason for it')"

assert_eq "the parent Then still resolves to itself" "$THEN_BLOCK" \
  "$(anchor 'Then I see a comment anchored to each line the session needs my decision on')"

assert_eq "a line sent tab-indented as it appears in the draft" "$AND_BLOCK" \
  "$(anchor '	- [ ] And each comment states the proposed wording and one reason for it')"

assert_eq "inline markdown the page stores as annotations, not characters" "$AND_BLOCK" \
  "$(anchor 'And **each comment** states the proposed wording and one `reason` for it')"

printf "\nTest group: nothing is posted unless exactly one block matches\n"

assert_eq "a line that is not on the page" 1 \
  "$(exit_code 'And the ticket carries no Blocked flag')"

assert_eq "a line two blocks both carry" 1 \
  "$(exit_code 'Given I moved a ticket into a by-AI refinement column')"

assert_eq "too short to match on is refused, not guessed" 2 \
  "$(exit_code 'AaUser')"

printf "\nTest group: the comment carries both parts, in order\n"

body="$(run 'And the session asked me nothing in chat' 'the drafted wording' 'why it reads better')"

assert_eq "suggestion is labelled and first" "[suggestion] " \
  "$(printf '%s' "$body" | jq -r '.rich_text[0].text.content')"
assert_eq "the label is bold" "true" \
  "$(printf '%s' "$body" | jq -r '.rich_text[0].annotations.bold')"
assert_eq "the caller's suggestion follows it" "the drafted wording" \
  "$(printf '%s' "$body" | jq -r '.rich_text[1].text.content')"
assert_eq "why is labelled and second" "
[why] " \
  "$(printf '%s' "$body" | jq -r '.rich_text[2].text.content')"
assert_eq "the caller's reason follows it" "why it reads better" \
  "$(printf '%s' "$body" | jq -r '.rich_text[3].text.content')"

printf "\nTest group: a missing argument is refused, not guessed at\n"

assert_eq "no why" 2 \
  "$(bash "$SCRIPT" "$PAGE" "a line" "a suggestion" >/dev/null 2>&1; echo $?)"
assert_eq "no arguments at all" 2 \
  "$(bash "$SCRIPT" >/dev/null 2>&1; echo $?)"

printf "\nTest group: a machine with no credential asks for the fallback it can trust\n"

mkdir -p "$TMPDIR/bin"
printf '#!/usr/bin/env bash\nexit 1\n' >"$TMPDIR/bin/security"
chmod +x "$TMPDIR/bin/security"

LINES_FIXTURE="$TMPDIR/lines.tsv"
{
  printf '%s\t%s\t%s\t%s\n' "3b48f3776f4f80000000000000000u01" 0 to_do "AaUser"
  printf '%s\t%s\t%s\t%s\n' "$THEN_BLOCK" 0 to_do "Then I see a comment anchored to each line the session needs my decision on"
  printf '%s\t%s\t%s\t%s\n' "$AND_BLOCK" 1 to_do "And each comment states the proposed wording and one reason for it"
  printf '%s\t%s\t%s\t%s\n' "3b48f3776f4f80000000000000000a02" 1 to_do "And the session asked me nothing in chat"
} >"$LINES_FIXTURE"

no_credential() {
  PATH="$TMPDIR/bin:$PATH" NOTION_BLOCKS_FIXTURE="$FIXTURE" NOTION_LINES_FIXTURE="$LINES_FIXTURE" \
    bash "$SCRIPT" "$PAGE" "$1" "a suggestion" "a reason" >/dev/null 2>&1
  echo $?
}

assert_eq "a top-level line is told to fall back to a selection" 3 \
  "$(no_credential 'Then I see a comment anchored to each line the session needs my decision on')"

assert_eq "a line written under another goes to the page, not to the line above" 4 \
  "$(no_credential 'And the session asked me nothing in chat')"

assert_eq "a depth nothing could read counts as written under another line" 4 \
  "$(no_credential 'And the ticket carries no Blocked flag')"

assert_eq "a bad line is still refused before the credential is looked at" 2 \
  "$(no_credential 'AaUser')"

printf "\n%d passed, %d failed\n" "$pass" "$fail"
[ "$fail" -eq 0 ]
