#!/usr/bin/env bash

HOOK="$(cd "$(dirname "$0")/.." && pwd)/guard-notion-content-revival.sh"
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

pass=0
fail=0

assert_denies() {
  local label="$1" output="$2"
  if printf '%s' "$output" | jq --exit-status '.hookSpecificOutput.permissionDecision == "deny"' >/dev/null 2>&1; then
    printf "  OK  %s\n" "$label"
    pass=$((pass + 1))
  else
    printf "  KO  %s — expected a deny, got '%s'\n" "$label" "$output"
    fail=$((fail + 1))
  fi
}

assert_allows() {
  local label="$1" output="$2"
  if [ -z "$output" ]; then
    printf "  OK  %s\n" "$label"
    pass=$((pass + 1))
  else
    printf "  KO  %s — expected silence, got '%s'\n" "$label" "$output"
    fail=$((fail + 1))
  fi
}

EARLIER="$TMPDIR/earlier.txt"
cat >"$EARLIER" <<'EOF'
Tech Steps
Agent Layer
extract the page read into a lib both hooks can source
wire the guard into the settings file
<summary>Why this was raised</summary>
Add the <theme> flag to settings
a tech step nobody has argued with yet
EOF

CURRENT="$TMPDIR/current.txt"
cat >"$CURRENT" <<'EOF'
Tech Steps
Agent Layer
Why this was raised
a tech step nobody has argued with yet
EOF

run_hook() {
  local command_name="$1"
  shift
  local updates="[]" new_str
  for new_str in "$@"; do
    updates="$(jq --compact-output --arg new "$new_str" '. + [{old_str:"x", new_str:$new}]' <<<"$updates")"
  done
  jq --null-input --compact-output --arg command "$command_name" --argjson updates "$updates" \
    '{hook_event_name:"PreToolUse",tool_input:{command:$command,page_id:"00000000-0000-0000-0000-000000000001",content_updates:$updates}}' |
    GUARD_NOTION_REVIVAL_EARLIER="$EARLIER" GUARD_NOTION_REVIVAL_CURRENT="$CURRENT" bash "$HOOK" 2>/dev/null
}

printf "Test group: text the page lost between the two reads\n"

assert_denies "a line deleted by hand while the agent drafted" \
  "$(run_hook update_content 'extract the page read into a lib both hooks can source')"

assert_denies "one revived line among several sound ones" \
  "$(run_hook update_content 'a tech step nobody has argued with yet' 'wire the guard into the settings file')"

assert_denies "markup is no way past the guard - the heading it wraps is gone" \
  "$(run_hook update_content '<summary>wire the guard into the settings file</summary>')"

assert_denies "a whole-page rewrite carrying the deleted line" \
  "$(jq --null-input --compact-output '{tool_input:{command:"replace_content",page_id:"00000000-0000-0000-0000-000000000001",new_str:"Tech Steps\nwire the guard into the settings file"}}' |
    GUARD_NOTION_REVIVAL_EARLIER="$EARLIER" GUARD_NOTION_REVIVAL_CURRENT="$CURRENT" bash "$HOOK" 2>/dev/null)"

printf "\nTest group: writes the guard must not block\n"

assert_allows "freshly drafted text, on neither read" \
  "$(run_hook update_content 'a change nobody has written down anywhere before now')"

assert_allows "text still on the page" \
  "$(run_hook update_content 'a tech step nobody has argued with yet')"

assert_allows "too short to match on is skipped, not denied" \
  "$(run_hook update_content 'wire it')"

assert_allows "a toggle heading still on the page, written wrapped in its markup" \
  "$(run_hook update_content '<summary>Why this was raised</summary>')"

assert_allows "a placeholder is not markup, so two lines differing only in one stay apart" \
  "$(run_hook update_content 'Add the <threshold> flag to settings')"

printf "\nTest group: silent when there is nothing to compare\n"

assert_allows "update_properties carries no body" \
  "$(run_hook update_properties 'wire the guard into the settings file')"

assert_allows "insert_content only appends" \
  "$(run_hook insert_content 'wire the guard into the settings file')"

assert_allows "no page id" \
  "$(jq --null-input --compact-output '{tool_input:{command:"update_content",content_updates:[{old_str:"x",new_str:"wire the guard into the settings file"}]}}' |
    GUARD_NOTION_REVIVAL_EARLIER="$EARLIER" GUARD_NOTION_REVIVAL_CURRENT="$CURRENT" bash "$HOOK" 2>/dev/null)"

: >"$TMPDIR/none.txt"

assert_allows "no earlier read of this page" \
  "$(jq --null-input --compact-output '{tool_input:{command:"update_content",page_id:"abc",content_updates:[{old_str:"x",new_str:"wire the guard into the settings file"}]}}' |
    GUARD_NOTION_REVIVAL_EARLIER="$TMPDIR/none.txt" GUARD_NOTION_REVIVAL_CURRENT="$CURRENT" bash "$HOOK" 2>/dev/null)"

assert_allows "the page could not be read back now" \
  "$(jq --null-input --compact-output '{tool_input:{command:"update_content",page_id:"abc",content_updates:[{old_str:"x",new_str:"wire the guard into the settings file"}]}}' |
    GUARD_NOTION_REVIVAL_EARLIER="$EARLIER" GUARD_NOTION_REVIVAL_CURRENT="$TMPDIR/none.txt" bash "$HOOK" 2>/dev/null)"

printf "\nTest group: the earlier read comes off the session transcript\n"

TRANSCRIPT="$TMPDIR/transcript.jsonl"
jq --null-input --compact-output \
  '{type:"user",message:{content:[{type:"tool_result",content:[{type:"text",text:"<page url=\"https://app.notion.com/p/00000000000000000000000000000001\">\nwire the guard into the settings file\n</page>"}]}]}}' \
  >"$TRANSCRIPT"
jq --null-input --compact-output \
  '{type:"user",message:{content:[{type:"tool_result",content:[{type:"text",text:"<page url=\"https://app.notion.com/p/0000000000000000000000000000dead\">\nsomething on a page this write is not touching\n</page>"}]}]}}' \
  >>"$TRANSCRIPT"

run_against_transcript() {
  jq --null-input --compact-output --arg transcript "$TRANSCRIPT" --arg new "$1" \
    '{transcript_path:$transcript,tool_input:{command:"update_content",page_id:"00000000-0000-0000-0000-000000000001",content_updates:[{old_str:"x",new_str:$new}]}}' |
    GUARD_NOTION_REVIVAL_CURRENT="$CURRENT" bash "$HOOK" 2>/dev/null
}

assert_denies "a line read off this page earlier in the session" \
  "$(run_against_transcript 'wire the guard into the settings file')"

assert_allows "a line read off a different page" \
  "$(run_against_transcript 'something on a page this write is not touching')"

printf "\nTest group: the window opens at the person's last prompt\n"

WINDOW="$TMPDIR/window.jsonl"
: >"$WINDOW"

append_prompt() {
  jq --null-input --compact-output --arg text "$1" \
    '{type:"user",message:{content:[{type:"text",text:$text}]}}' >>"$WINDOW"
}

append_page_read() {
  jq --null-input --compact-output --arg text "$1" \
    '{type:"user",message:{content:[{type:"tool_result",content:[{type:"text",text:("<page url=\"https://app.notion.com/p/00000000000000000000000000000001\">\n" + $text + "\n</page>")}]}]}}' >>"$WINDOW"
}

append_prompt_as_plain_text() {
  jq --null-input --compact-output --arg text "$1" \
    '{type:"user",message:{content:$text}}' >>"$WINDOW"
}

run_against_window() {
  jq --null-input --compact-output --arg transcript "$WINDOW" --arg new "$1" \
    '{transcript_path:$transcript,tool_input:{command:"update_content",page_id:"00000000-0000-0000-0000-000000000001",content_updates:[{old_str:"x",new_str:$new}]}}' |
    GUARD_NOTION_REVIVAL_CURRENT="$CURRENT" bash "$HOOK" 2>/dev/null
}

append_page_read 'wire the guard into the settings file'
append_prompt 'go back to the earlier draft'

assert_allows "a line the person asked to bring back" \
  "$(run_against_window 'wire the guard into the settings file')"

append_prompt 'draft the tech steps'
append_page_read 'wire the guard into the settings file'

assert_denies "a line read off the page after the person's last prompt" \
  "$(run_against_window 'wire the guard into the settings file')"

append_prompt '<task-notification>ticket moved</task-notification>'

assert_denies "a board event leaves the earlier read in place" \
  "$(run_against_window 'wire the guard into the settings file')"

append_prompt_as_plain_text '<system-reminder>the tasks tool has not been used</system-reminder>'

assert_denies "a reminder carried as plain text is not the person either" \
  "$(run_against_window 'wire the guard into the settings file')"

printf "\n%d passed, %d failed\n" "$pass" "$fail"
[ "$fail" -eq 0 ]
