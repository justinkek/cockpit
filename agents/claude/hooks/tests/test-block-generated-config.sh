#!/usr/bin/env bash

HOOKS="$(cd "$(dirname "$0")/.." && pwd)"

pass=0
fail=0

decision() {
  local hook="$1" path="$2"
  jq -nc --arg path "$path" \
    '{tool_name:"Edit",tool_input:{file_path:$path,old_string:"a",new_string:"b"}}' \
    | bash "$HOOKS/$hook" >/dev/null 2>&1
  printf '%s' "$?"
}

message() {
  local hook="$1" path="$2"
  jq -nc --arg path "$path" \
    '{tool_name:"Edit",tool_input:{file_path:$path,old_string:"a",new_string:"b"}}' \
    | bash "$HOOKS/$hook" 2>&1 >/dev/null
}

assert_equal() {
  local label="$1" expected="$2" actual="$3"
  if [ "$actual" = "$expected" ]; then
    printf "  OK  %s\n" "$label"
    pass=$((pass + 1))
  else
    printf "  KO  %s — expected '%s', got '%s'\n" "$label" "$expected" "$actual"
    fail=$((fail + 1))
  fi
}

assert_names() {
  local label="$1" needle="$2" haystack="$3"
  if printf '%s' "$haystack" | grep -qF "$needle"; then
    printf "  OK  %s\n" "$label"
    pass=$((pass + 1))
  else
    printf "  KO  %s — '%s' is not named in the refusal\n" "$label" "$needle"
    fail=$((fail + 1))
  fi
}

printf "Test group: a sync-generated file in any account directory is refused\n"

assert_equal "the default profile's memory file" "2" \
  "$(decision block-user-claudemd.sh "$HOME/.claude/CLAUDE.md")"
assert_equal "a named account's memory file" "2" \
  "$(decision block-user-claudemd.sh "$HOME/.claude-work/CLAUDE.md")"
assert_equal "the default profile's settings file" "2" \
  "$(decision block-user-settings.sh "$HOME/.claude/settings.json")"
assert_equal "a named account's settings file" "2" \
  "$(decision block-user-settings.sh "$HOME/.claude-work/settings.json")"

printf "\nTest group: the refusal names a path the same guard lets through, so following it cannot loop\n"

assert_names "the memory refusal points at the shared source" \
  ".agents-shared/base.AGENTS.md" \
  "$(message block-user-claudemd.sh "$HOME/.claude/CLAUDE.md")"
assert_equal "and that source is editable" "0" \
  "$(decision block-user-claudemd.sh "$HOME/.claude-shared/claude-md/base.CLAUDE.md")"
assert_names "the settings refusal points at the shared source" \
  ".claude-shared/settings/base.settings.json" \
  "$(message block-user-settings.sh "$HOME/.claude/settings.json")"
assert_equal "and that source is editable" "0" \
  "$(decision block-user-settings.sh "$HOME/.claude-shared/settings/base.settings.json")"

printf "\nTest group: a project's own config is out of scope, being nobody's generated output\n"

assert_equal "a project memory file" "0" \
  "$(decision block-user-claudemd.sh "$PWD/CLAUDE.md")"
assert_equal "a project settings file" "0" \
  "$(decision block-user-settings.sh "$PWD/.claude/settings.json")"
assert_equal "a project's local settings file" "0" \
  "$(decision block-user-settings.sh "$PWD/.claude/settings.local.json")"

printf "\n%d passed, %d failed\n" "$pass" "$fail"
[ "$fail" -eq 0 ]
