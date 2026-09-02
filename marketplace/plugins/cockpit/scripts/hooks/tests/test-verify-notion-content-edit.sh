#!/usr/bin/env bash

HOOK="$(cd "$(dirname "$0")/.." && pwd)/verify-notion-content-edit.sh"
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

pass=0
fail=0

assert_fires() {
  local label="$1" output="$2"
  if printf '%s' "$output" | grep -qF "[verify-edit]"; then
    printf "  OK  %s\n" "$label"
    pass=$((pass + 1))
  else
    printf "  KO  %s — expected a warning, got '%s'\n" "$label" "$output"
    fail=$((fail + 1))
  fi
}

assert_silent() {
  local label="$1" output="$2"
  if [ -z "$output" ]; then
    printf "  OK  %s\n" "$label"
    pass=$((pass + 1))
  else
    printf "  KO  %s — expected silence, got '%s'\n" "$label" "$output"
    fail=$((fail + 1))
  fi
}

# The page as the REST API returns it: plain_text, one block per line.
PAGE="$TMPDIR/page.txt"
cat >"$PAGE" <<'EOF'
Validation Steps
AaUser
Given I asked for several edits to a Notion page
When the agent reports the work done
Then only the edits actually present on the page are reported as done
Why this was raised
Strategy comparison
Back from CR
Root cause and fix
input="$(cat)"
command -v jq >/dev/null 2>&1 || exit 0
EOF

run_hook() {
  local command_name="$1"
  shift
  local updates="[]" new_str
  for new_str in "$@"; do
    updates="$(jq -c --arg n "$new_str" '. + [{old_str:"x", new_str:$n}]' <<<"$updates")"
  done
  jq -nc --arg c "$command_name" --argjson u "$updates" \
    '{hook_event_name:"PostToolUse",tool_input:{command:$c,page_id:"3b38f377-6f4f-8138-957c-e5f2dcb91ac7",content_updates:$u}}' |
    VERIFY_NOTION_CONTENT_EDIT_TEXT="$PAGE" bash "$HOOK" 2>/dev/null
}

printf "Test group: an edit whose text is on the page\n"

assert_silent "present verbatim" \
  "$(run_hook update_content 'Then only the edits actually present on the page are reported as done')"

assert_silent "sent tab-indented inside a toggle, stored de-indented" \
  "$(run_hook update_content '			command -v jq >/dev/null 2>&1 || exit 0')"

assert_silent "target line carries an inline comment, so plain_text drops the span" \
  "$(run_hook update_content 'Given I asked for several edits to a Notion page')"

assert_silent "inline markdown the page stores as annotations, not characters" \
  "$(run_hook update_content '**When** the agent `reports` the work done')"

assert_silent "a toggle heading, written wrapped in its markup" \
  "$(run_hook update_content '<summary>Why this was raised</summary>')"

assert_silent "the same heading written with the tag capitalised" \
  "$(run_hook update_content '<Summary>Why this was raised</Summary>')"

assert_silent "the longest raw line is markup, so a shorter line carries more words" \
  "$(run_hook update_content '<summary>Back from CR</summary>
Root cause and fix')"

assert_silent "a table row carrying its column widths" \
  "$(run_hook update_content '<col width="200"><col width="400">Strategy comparison')"

assert_silent "every edit in a multi-edit call is present" \
  "$(run_hook update_content 'When the agent reports the work done' 'Given I asked for several edits to a Notion page')"

printf "\nTest group: an edit whose text is not on the page\n"

assert_fires "absent entirely" \
  "$(run_hook update_content 'Then every edit reported as done is present on the page')"

assert_fires "one of several edits absent" \
  "$(run_hook update_content 'When the agent reports the work done' 'a line that was never written to the page at all')"

assert_fires "too short to verify is reported, not passed" \
  "$(run_hook update_content 'ok')"

printf "\nTest group: silent when there is nothing to verify\n"

assert_silent "insert_content cannot no-op" \
  "$(run_hook insert_content 'a line that was never written to the page at all')"

assert_silent "update_properties carries no content" \
  "$(run_hook update_properties 'a line that was never written to the page at all')"

assert_silent "no content_updates" \
  "$(jq -nc '{tool_input:{command:"update_content",page_id:"abc",content_updates:[]}}' |
    VERIFY_NOTION_CONTENT_EDIT_TEXT="$PAGE" bash "$HOOK" 2>/dev/null)"

assert_silent "no page id" \
  "$(jq -nc '{tool_input:{command:"update_content",content_updates:[{old_str:"x",new_str:"nowhere on the page at all"}]}}' |
    VERIFY_NOTION_CONTENT_EDIT_TEXT="$PAGE" bash "$HOOK" 2>/dev/null)"

printf "\nTest group: the page could not be read back\n"

: >"$TMPDIR/empty.txt"
assert_fires "unreadable page text is unconfirmed, not assumed fine" \
  "$(jq -nc '{tool_input:{command:"update_content",page_id:"abc",content_updates:[{old_str:"x",new_str:"When the agent reports the work done"}]}}' |
    VERIFY_NOTION_CONTENT_EDIT_TEXT="$TMPDIR/empty.txt" bash "$HOOK" 2>/dev/null)"

printf "\n%d passed, %d failed\n" "$pass" "$fail"
[ "$fail" -eq 0 ]
