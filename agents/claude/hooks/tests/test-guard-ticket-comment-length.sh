#!/usr/bin/env bash

HOOK="$(cd "$(dirname "$0")/.." && pwd)/guard-ticket-comment-length.sh"

pass=0
fail=0

run_hook() {
  jq --null-input --compact-output --arg m "$1" \
    '{hook_event_name:"PreToolUse",tool_name:"mcp__plugin_Notion_notion__notion-create-comment",tool_input:{page_id:"abc",markdown:$m}}' \
    | bash "$HOOK" 2>/dev/null
}

assert_denies() {
  local label="$1" output="$2"
  if printf '%s' "$output" | grep --quiet '"permissionDecision":"deny"'; then
    printf "  OK  %s\n" "$label"
    pass=$((pass + 1))
  else
    printf "  KO  %s — expected a deny, got '%s'\n" "$label" "$output"
    fail=$((fail + 1))
  fi
}

assert_passes() {
  local label="$1" output="$2"
  if [ -z "$output" ]; then
    printf "  OK  %s\n" "$label"
    pass=$((pass + 1))
  else
    printf "  KO  %s — expected silence, got '%s'\n" "$label" "$output"
    fail=$((fail + 1))
  fi
}

characters_of() { printf 'x%.0s' $(seq 1 "$1"); }

printf "Test group: the ceiling\n"

assert_denies "the reply that re-explained the root cause" \
  "$(run_hook 'Yes - and toward a smaller fix. The orphans were not a detection failure: session-end-release-claims.sh already runs on session end, and it only ever releases claims, so it never stopped a watcher. Tech steps redrafted - the hook kills the watchers that descend from the claude that is ending, and neither watcher script is touched. Complexity 3 to 2.')"
assert_denies "one character over" "$(run_hook "$(characters_of 201)")"
assert_passes "the answer the reader needed" \
  "$(run_hook 'Tech steps redrafted, complexity 3 to 2.')"
assert_passes "exactly at the ceiling" "$(run_hook "$(characters_of 200)")"

printf "\nTest group: the fixed formats keep their shape\n"

assert_passes "a blocked flag that names what is needed and who from" \
  "$(run_hook "$(printf '\360\237\244\226 \360\237\232\247 **Blocked** - the venue has not answered on the room booking.\n\n%s\n' "$(characters_of 300)")")"
assert_passes "a bounce-back summary" \
  "$(run_hook "$(printf '\360\237\224\231 Back from CR (#2): %s\n' "$(characters_of 300)")")"
assert_passes "a raised decision quoting the line it concerns" \
  "$(run_hook "$(printf '**On:** Then I see a summary card for each subscription\n**[suggestion]** %s\n' "$(characters_of 300)")")"
assert_denies "a marker further down does not exempt the comment" \
  "$(run_hook "$(printf 'some preamble first\n\360\237\224\231 Back from CR (#2): %s\n' "$(characters_of 300)")")"

printf "\nTest group: the guards\n"

assert_passes "a comment sent as rich text carries no markdown to measure" \
  "$(jq --null-input --compact-output \
    '{hook_event_name:"PreToolUse",tool_input:{page_id:"abc",rich_text:[{text:{content:"hi"}}]}}' \
    | bash "$HOOK" 2>/dev/null)"
assert_passes "no tool input at all" \
  "$(jq --null-input --compact-output '{hook_event_name:"PreToolUse"}' | bash "$HOOK" 2>/dev/null)"

printf "\n%d passed, %d failed\n" "$pass" "$fail"
[ "$fail" -eq 0 ]
