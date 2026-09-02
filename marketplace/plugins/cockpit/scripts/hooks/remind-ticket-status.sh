#!/usr/bin/env bash

input="$(cat)"

if command -v jq >/dev/null 2>&1; then
  tool="$(printf '%s' "$input" | jq -r '.tool_name // empty')"
  cmd="$(printf '%s' "$input" | jq -r '.tool_input.command // empty')"
  session_id="$(printf '%s' "$input" | jq -r '.session_id // empty')"
else
  tool="$(printf '%s' "$input" | sed -n 's/.*"tool_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')"
  cmd="$(printf '%s' "$input" | sed -n 's/.*"command"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')"
  session_id="$(printf '%s' "$input" | sed -n 's/.*"session_id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')"
fi

[ -n "$session_id" ] || exit 0

STATE_DIR="$HOME/.local/state/claude-ticket-sessions"
marker="$STATE_DIR/${session_id}.ticket"
[ -f "$marker" ] || exit 0

# --- PreToolUse: Edit/Write (first-edit-only) ---
if [ "$tool" = "Edit" ] || [ "$tool" = "Write" ]; then
  nudged_marker="$STATE_DIR/${session_id}.edit-nudged"
  [ -f "$nudged_marker" ] && exit 0

  touch "$nudged_marker"
  reason="[ticket-status-reminder] First edit in this session. Check whether the cockpit ticket status is behind where the work actually is — if so, prompt to advance it (use the cockpit:ticket:x:status skill)."
  if command -v jq >/dev/null 2>&1; then
    jq -nc --arg r "$reason" \
      '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"allow",permissionDecisionReason:$r}}'
  else
    printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow","permissionDecisionReason":"%s"}}\n' "$reason"
  fi
  exit 0
fi

# --- PostToolUse: Bash (git commit) ---
if [ "$tool" = "Bash" ] && printf '%s' "$cmd" | grep -q 'git commit\|git -C .* commit'; then
  if command -v jq >/dev/null 2>&1; then
    exit_code="$(printf '%s' "$input" | jq --raw-output '.tool_response.exitCode // .tool_result.exitCode // 0')"
  else
    exit_code="0"
  fi
  [ "$exit_code" = "0" ] || exit 0

  : > "$STATE_DIR/${session_id}.dev-committed"
  echo "[ticket-status-reminder] A commit just landed. If the tech steps are built, advance the cockpit ticket to In CR by AI now (use the cockpit:ticket:x:status skill) — do not ask first. If dev is not finished, carry on."
  exit 0
fi

# --- PostToolUse: Bash (git push → advance post-dev) ---
if [ "$tool" = "Bash" ] && printf '%s' "$cmd" | grep -q 'git push\|git -C .* push'; then
  cr_marker="$STATE_DIR/${session_id}.stage-cr"
  [ -f "$cr_marker" ] && exit 0

  if command -v jq >/dev/null 2>&1; then
    exit_code="$(printf '%s' "$input" | jq --raw-output '.tool_response.exitCode // .tool_result.exitCode // 0')"
  else
    exit_code="0"
  fi
  [ "$exit_code" = "0" ] || exit 0

  # Determine the first post-In Dev column not in the project's skip list.
  post_dev_target="In CR by AI"
  conventions_file="./AGENTS.md"
  if [ -f "$conventions_file" ] && grep -q '^## Ticket walk skip' "$conventions_file"; then
    skip_list="$(awk '/^## Ticket walk skip$/{f=1;next} /^## /{f=0} f && /^- /{sub(/^- /,"");print}' "$conventions_file")"
    post_dev_target=""
    while IFS= read -r col; do
      if ! printf '%s\n' "$skip_list" | grep -qxF "$col"; then
        post_dev_target="$col"
        break
      fi
    done <<COLS
In CR by AI
Ready for CR
In CR
Ready for FR
In FR
Ready for Validation
Done
COLS
    [ -z "$post_dev_target" ] && post_dev_target="Done"
  fi

  echo "[auto-advance-cr] A push just landed. Advance the cockpit ticket to ${post_dev_target} (use the cockpit:ticket:x:status skill to walk each column in order), then run \"\$HOME/.cockpit/scripts/ticket-status-confirm cr\" to mark it done. If the ticket is already at or past ${post_dev_target}, just run the confirm command."
  exit 0
fi

exit 0
