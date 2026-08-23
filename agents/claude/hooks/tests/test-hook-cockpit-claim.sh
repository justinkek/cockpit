#!/usr/bin/env bash

HOOKS="$(cd "$(dirname "$0")/.." && pwd)"
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

pass=0
fail=0

assert_decision() {
  local label="$1" expected="$2" hook="$3" input="$4"
  local out decision
  out="$(printf '%s' "$input" | HOME="$TMPDIR" bash "$HOOKS/$hook" 2>/dev/null)"
  decision="$(printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecision // "none"' 2>/dev/null)"
  if [ "$decision" = "$expected" ]; then
    printf "  OK  %s\n" "$label"
    pass=$((pass + 1))
  else
    printf "  KO  %s — expected '%s', got '%s'\n" "$label" "$expected" "$decision"
    fail=$((fail + 1))
  fi
}

claim='{"session_id":"claim-test","transcript_path":"","tool_name":"mcp__plugin_Notion_notion__notion-update-page","tool_input":{"page_id":"abc","command":"update_properties","properties":{"Agent: Session Id":"claiming-1-ab12","Assignee":["user-1"]}}}'
release='{"session_id":"claim-test","transcript_path":"","tool_name":"mcp__plugin_Notion_notion__notion-update-page","tool_input":{"page_id":"abc","command":"update_properties","properties":{"Agent: Session Id":null}}}'
with_status='{"session_id":"claim-test","transcript_path":"","tool_name":"mcp__plugin_Notion_notion__notion-update-page","tool_input":{"page_id":"abc","command":"update_properties","properties":{"Agent: Session Id":"claiming-1-ab12","Status":"In Dev"}}}'
content='{"session_id":"claim-test","transcript_path":"","tool_name":"mcp__plugin_Notion_notion__notion-update-page","tool_input":{"page_id":"abc","command":"replace_content","new_str":"## Tech Steps"}}'
empty_props='{"session_id":"claim-test","transcript_path":"","tool_name":"mcp__plugin_Notion_notion__notion-update-page","tool_input":{"page_id":"abc","command":"update_properties","properties":{}}}'

for hook in require-ticket.sh require-rename.sh; do
  printf "Test group: %s\n" "$hook"
  assert_decision "allows the claim"                      allow "$hook" "$claim"
  assert_decision "allows the release"                    allow "$hook" "$release"
  assert_decision "denies a claim carrying a status write" deny  "$hook" "$with_status"
  assert_decision "denies a page content write"            deny  "$hook" "$content"
  assert_decision "denies an empty property map"           deny  "$hook" "$empty_props"
  printf "\n"
done

printf "%d passed, %d failed\n" "$pass" "$fail"
[ "$fail" -eq 0 ]
