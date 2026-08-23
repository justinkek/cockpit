#!/usr/bin/env bash

HOOK="$(cd "$(dirname "$0")/.." && pwd)/redirect-default-profile-reads.sh"

pass=0
fail=0

read_hook() {
  jq -nc --arg p "$1" '{tool_name:"Read",tool_input:{file_path:$p}}' | bash "$HOOK" 2>/dev/null
}

bash_hook() {
  jq -nc --arg c "$1" '{tool_name:"Bash",tool_input:{command:$c}}' | bash "$HOOK" 2>/dev/null
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

assert_denies() {
  local label="$1" output="$2"
  if printf '%s' "$output" | grep -q '"permissionDecision":"deny"'; then
    printf "  OK  %s\n" "$label"
    pass=$((pass + 1))
  else
    printf "  KO  %s — expected a deny, got '%s'\n" "$label" "$output"
    fail=$((fail + 1))
  fi
}

printf "Test group: transcripts are readable\n"

assert_allows "Read a transcript in the default profile" \
  "$(read_hook "$HOME/.claude/projects/-Users-me-repo/abc.jsonl")"
assert_allows "Read a transcript in a named profile" \
  "$(read_hook "$HOME/.claude-work/projects/-Users-me-repo/abc.jsonl")"
assert_allows "Bash listing a profile's projects dir" \
  "$(bash_hook "ls -t \"\$HOME/.claude-work/projects/-Users-me-repo/\"")"

printf "\nTest group: everything else stays denied\n"

assert_denies "Read a profile's settings" \
  "$(read_hook "$HOME/.claude-work/settings.json")"
assert_denies "Read the default profile's CLAUDE.md" \
  "$(read_hook "$HOME/.claude/CLAUDE.md")"
assert_denies "Bash reading a profile's settings" \
  "$(bash_hook "cat \"\$HOME/.claude-work/settings.json\"")"
assert_denies "a projects dir outside any profile is not the exemption" \
  "$(read_hook "$HOME/.claude-work/skills/projects/notes.md")"

printf "\nTest group: a .claude directory outside the home directory is another repository's\n"

assert_allows "Bash writing another checkout's project settings" \
  "$(bash_hook "cat > \"\$HOME/Desktop/Repositories/personal/cockpit/.claude/settings.json\"")"
assert_allows "Bash copying into another checkout's skills" \
  "$(bash_hook "cp -R src /tmp/somewhere/.claude/skills/a-skill")"
assert_denies "Bash reading the home directory's profile is still denied" \
  "$(bash_hook "cat \"\$HOME/.claude/settings.json\"")"
assert_denies "the spelled-out home directory is caught too" \
  "$(bash_hook "cat $HOME/.claude-work/settings.json")"

printf "\nTest group: the existing allowances still hold\n"

assert_allows "~/.claude-shared" "$(read_hook "$HOME/.claude-shared/settings/base.settings.json")"
assert_allows "~/.claude-logs" "$(read_hook "$HOME/.claude-logs/prompt-audit.jsonl")"

printf "\n%d passed, %d failed\n" "$pass" "$fail"
[ "$fail" -eq 0 ]
