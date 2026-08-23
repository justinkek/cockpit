#!/usr/bin/env bash

input="$(cat)"

if command -v jq >/dev/null 2>&1; then
  session_id="$(printf '%s' "$input" | jq -r '.session_id // empty')"
  prompt="$(printf '%s' "$input" | jq -r '.prompt // empty')"
else
  session_id="$(printf '%s' "$input" | sed -n 's/.*"session_id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')"
  prompt="$(printf '%s' "$input" | sed -n 's/.*"prompt"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')"
fi

[ -n "$session_id" ] || exit 0
[ -n "$prompt" ] || exit 0

STATE_DIR="$HOME/.local/state/claude-ticket-sessions"
[ -f "$STATE_DIR/${session_id}.ticket" ] || exit 0

column_file="$STATE_DIR/${session_id}.column"
[ -f "$column_file" ] || exit 0
column="$(head -n 1 "$column_file")"

# Only the four gates with a Back from counter can be bounced from.
case "$column" in
"In Dev" | "In CR by AI" | "In CR" | "In FR" | "Ready for Validation") ;;
*) exit 0 ;;
esac

# Conservative on purpose. Widening this list buys recall at the cost of a
# counter nobody trusts; the agent's judgement is the backstop for misses.
# `.?` stands in for the apostrophe so both "doesn't" and "doesnt" match.
rejection='does not work|doesn.?t work|did not work|didn.?t work|not working|is broken|still broken|still failing|still wrong|that.?s wrong|you missed|you broke|you forgot|regression|revert|crash'

printf '%s' "$prompt" | grep -qiE "$rejection" || exit 0

printf '%s\n' "[back-from-column] This prompt reads as a rejection of work already at ${column}. Judge whether it is a genuine defect in delivered work rather than a preference, a scope change, or a new requirement. If it is a defect, invoke /cockpit:ticket:x:back-from-column with source and target both set to ${column} — one bounce per defect, not per message."

exit 0
