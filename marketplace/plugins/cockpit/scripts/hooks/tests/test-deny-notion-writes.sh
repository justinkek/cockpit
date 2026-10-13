#!/usr/bin/env bash

HOOK="$(cd "$(dirname "$0")/.." && pwd)/deny-notion-writes.sh"
HOOKS_JSON="$(cd "$(dirname "$0")/../../.." && pwd)/hooks/hooks.json"

pass=0
fail=0

decision_for() {
  jq --null-input --compact-output --arg tool "$1" \
    '{session_id:"deny-notion-test",tool_name:$tool,tool_input:{}}' \
    | bash "$HOOK" 2>/dev/null \
    | jq --raw-output '.hookSpecificOutput.permissionDecision // "none"' 2>/dev/null
}

assert_decision() {
  local tool="$1" expected="$2" actual
  actual="$(decision_for "$tool")"
  [ -n "$actual" ] || actual="none"
  if [ "$actual" = "$expected" ]; then
    printf "  OK  %s -> %s\n" "$tool" "$expected"
    pass=$((pass + 1))
  else
    printf "  KO  %s — expected '%s', got '%s'\n" "$tool" "$expected" "$actual"
    fail=$((fail + 1))
  fi
}

matched_by_hooks_json() {
  jq --raw-output '.hooks.PreToolUse[] | select(.hooks[].command | endswith("deny-notion-writes.sh")) | .matcher' "$HOOKS_JSON" \
    | while IFS= read -r matcher; do
        printf '%s' "$1" | grep --quiet --extended-regexp "^($matcher)$" && echo yes
      done | head -1
}

assert_matched() {
  local tool="$1"
  if [ "$(matched_by_hooks_json "$tool")" = "yes" ]; then
    printf "  OK  the matcher reaches %s\n" "$tool"
    pass=$((pass + 1))
  else
    printf "  KO  the matcher does not reach %s\n" "$tool"
    fail=$((fail + 1))
  fi
}

printf "Test group: every Notion write is denied, whatever the connector is named\n"

for tool in \
  mcp__plugin_Notion_notion__notion-create-pages \
  mcp__plugin_Notion_notion__notion-update-page \
  mcp__plugin_Notion_notion__notion-move-pages \
  mcp__plugin_Notion_notion__notion-duplicate-page \
  mcp__plugin_Notion_notion__notion-create-comment \
  mcp__plugin_Notion_notion__notion-create-attachment \
  mcp__Notion__notion-update-page \
  mcp__Notion__API-patch-page \
  mcp__Notion__API-post-page \
  mcp__150a1334-4dd6-4563-8f6c-52182f5b5fe1__notion-create-pages \
  mcp__150a1334-4dd6-4563-8f6c-52182f5b5fe1__notion-update-data-source \
  mcp__150a1334-4dd6-4563-8f6c-52182f5b5fe1__notion-restore-pages \
  mcp__150a1334-4dd6-4563-8f6c-52182f5b5fe1__notion-create-file-upload \
  mcp__150a1334-4dd6-4563-8f6c-52182f5b5fe1__notion-create-comment; do
  assert_decision "$tool" deny
  assert_matched "$tool"
done

printf "\nTest group: reading Notion stays open\n"

for tool in \
  mcp__plugin_Notion_notion__notion-fetch \
  mcp__plugin_Notion_notion__notion-search \
  mcp__plugin_Notion_notion__notion-get-comments \
  mcp__150a1334-4dd6-4563-8f6c-52182f5b5fe1__notion-query-data-sources \
  mcp__150a1334-4dd6-4563-8f6c-52182f5b5fe1__notion-get-comments \
  mcp__Notion__API-retrieve-a-page; do
  assert_decision "$tool" none
done

printf "\nTest group: a tool that is not Notion's is none of its business\n"

for tool in Bash Edit mcp__github__create_issue mcp__a37a2b65-e42b-4fcd-a9d7-8b7c43abe7f5__update_file; do
  assert_decision "$tool" none
done

printf "\nTest group: the reason sends the agent to the local board\n"

reason="$(jq --null-input --compact-output '{tool_name:"mcp__plugin_Notion_notion__notion-update-page"}' \
  | bash "$HOOK" | jq --raw-output '.hookSpecificOutput.permissionDecisionReason')"
if printf '%s' "$reason" | grep --quiet --fixed-strings 'board-card' \
  && printf '%s' "$reason" | grep --quiet --fixed-strings 'read-only'; then
  printf "  OK  names board-card and says Notion is read-only\n"
  pass=$((pass + 1))
else
  printf "  KO  reason was '%s'\n" "$reason"
  fail=$((fail + 1))
fi

printf "\n%d passed, %d failed\n" "$pass" "$fail"
[ "$fail" -eq 0 ]
