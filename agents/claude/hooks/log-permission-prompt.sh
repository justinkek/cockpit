#!/usr/bin/env bash

input="$(cat)"
log="$HOME/.claude-logs/prompt-audit.jsonl"
mkdir -p "$HOME/.claude-logs" 2>/dev/null

acct="${CLAUDE_CONFIG_DIR##*/}"; [ -n "$acct" ] || acct="unknown"
ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

if command -v jq >/dev/null 2>&1; then
  sid="$(printf '%s' "$input" | jq -r '.session_id // empty')"
  cwd="$(printf '%s' "$input" | jq -r '.cwd // empty')"
  jq -nc --arg ts "$ts" --arg a "$acct" --arg s "$sid" --arg c "$cwd" \
    '{ts:$ts, account:$a, session_id:$s, cwd:$c}' >> "$log" 2>/dev/null
else
  sid="$(printf '%s' "$input" | sed -n 's/.*"session_id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')"
  printf '{"ts":"%s","account":"%s","session_id":"%s"}\n' "$ts" "$acct" "$sid" >> "$log" 2>/dev/null
fi

exit 0
