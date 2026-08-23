#!/usr/bin/env bash

. "$(dirname "$0")/hook-argv-lib.sh"

input="$(cat)"

if command -v jq >/dev/null 2>&1; then
  tool="$(printf '%s' "$input" | jq -r '.tool_name // empty')"
  session_id="$(printf '%s' "$input" | jq -r '.session_id // empty')"
  transcript="$(printf '%s' "$input" | jq -r '.transcript_path // empty')"
  cmd="$(printf '%s' "$input" | jq -r '.tool_input.command // empty')"
else
  tool="$(printf '%s' "$input" | sed -n 's/.*"tool_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')"
  session_id="$(printf '%s' "$input" | sed -n 's/.*"session_id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')"
  transcript="$(printf '%s' "$input" | sed -n 's/.*"transcript_path"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')"
  cmd="$(printf '%s' "$input" | sed -n 's/.*"command"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')"
fi

# No session id (shouldn't happen) -> defer rather than brick the session.
[ -n "$session_id" ] || exit 0

STATE_DIR="$HOME/.local/state/claude-rename-gate"
mkdir -p "$STATE_DIR"
find "$STATE_DIR" -type f -mtime +7 -delete 2>/dev/null

marker="$STATE_DIR/$session_id"

# Intercept the auto-rename command: write the custom-title record to the
# transcript, create the marker, and auto-approve. Same pattern as
# require-ticket.sh's intercept of ticket-register.
if [ "$tool" = "Bash" ] && printf '%s' "$cmd" | grep -q 'auto-rename'; then
  # The session name is the first argument after the script token — read as a
  # shell word, so a name that itself contains "auto-rename" cannot be
  # mistaken for the command token (see hook-argv-lib.sh).
  name="$(hook_argv_after "$cmd" auto-rename | sed -n 1p)"

  if [ -n "$name" ] && [ -n "$transcript" ] && [ -f "$transcript" ]; then
    printf '{"type":"custom-title","customTitle":"%s","sessionId":"%s"}\n' \
      "$name" "$session_id" >> "$transcript"
  fi

  : > "$marker"

  # Validate: only auto-approve clean invocations of the auto-rename script.
  residue="$(printf '%s' "$cmd" | sed -E "s/'[^']*'//g; s/\"[^\"]*\"//g")"
  first="$(printf '%s' "$cmd" | sed -E 's/^[[:space:]]*//' | awk '{print $1}' | tr -d '"'"'")"
  case "$residue" in *'|'*|*'&'*|*';'*|*'<'*|*'>'*|*'`'*|*'$('*) exit 0 ;; esac
  case "$first" in *.claude-shared/auto-rename) ;; *) exit 0 ;; esac

  reason="auto-rename (session naming) — allowed"
  if command -v jq >/dev/null 2>&1; then
    jq -nc --arg r "$reason" \
      '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"allow",permissionDecisionReason:$r}}'
  else
    printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow","permissionDecisionReason":"%s"}}\n' "$reason"
  fi
  exit 0
fi

[ -f "$marker" ] && exit 0

# Cross-allow: let the copilot skill work out which ticket to take. The name
# comes from that ticket, so every one of these necessarily runs before the
# session has a name. Two of them write — ticket-claim-lock takes a lock, and
# cockpit-board-claim records which board serves this checkout — but each writes
# one known thing, which is why they are named here one by one rather than by a
# pattern that would let anything through.
if [ "$tool" = "Bash" ] && printf '%s' "$cmd" | grep -qE 'ticket-board-members|ticket-claim-lock|ticket-waiting-cards|cockpit-board-claim|cockpit-board-id|cockpit-cache-query'; then
  first="$(printf '%s' "$cmd" | sed -E 's/^[[:space:]]*//' | awk '{print $1}' | tr -d '"'"'")"
  case "$first" in *.claude-shared/ticket-board-members|*.claude-shared/ticket-claim-lock|*.claude-shared/ticket-waiting-cards|*.claude-shared/cockpit-board-claim|*.claude-shared/cockpit-board-id|*.claude-shared/cockpit-cache-query) exit 0 ;; esac
fi

# Cross-allow: let ticket-register through without writing the rename marker.
# Without this, ticket-register is denied by the rename gate before the ticket
# gate can intercept it — a chicken-and-egg deadlock between the two hooks.
if [ "$tool" = "Bash" ] && printf '%s' "$cmd" | grep -q 'ticket-register'; then
  first="$(printf '%s' "$cmd" | sed -E 's/^[[:space:]]*//' | awk '{print $1}' | tr -d '"'"'")"
  case "$first" in
    *.claude-shared/ticket-register|*.claude-shared/ticket-register-source-ticket|*.claude-shared/ticket-register-type) exit 0 ;;
  esac
fi

# Cross-allow: let the copilot skill claim a waiting card before the session is
# named. The name is built from the claimed ticket, so requiring a name first
# forces a throwaway one — which is exactly the workaround this prevents.
if [ "$tool" = "mcp__plugin_Notion_notion__notion-update-page" ] && hook_is_cockpit_claim "$input"; then
  reason="notion-update-page writing only the cockpit ticket claim — allowed"
  if command -v jq >/dev/null 2>&1; then
    jq -nc --arg r "$reason" \
      '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"allow",permissionDecisionReason:$r}}'
  else
    printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow","permissionDecisionReason":"%s"}}\n' "$reason"
  fi
  exit 0
fi

# Cross-allow: let notion-create-pages through when targeting cockpit data
# sources (Tickets, Epics, Projects). The ticket skill needs this to create
# stubs and epics before the session is named.
if [ "$tool" = "mcp__plugin_Notion_notion__notion-create-pages" ]; then
  if command -v jq >/dev/null 2>&1; then
    ds_id="$(printf '%s' "$input" | jq -r '.tool_input.parent.data_source_id // empty')"
  else
    ds_id="$(printf '%s' "$input" | sed -n 's/.*"data_source_id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')"
  fi
  case "$ds_id" in
    a758f377-6f4f-83c6-ba20-07fdca79919b|a758f3776f4f83c6ba2007fdca79919b|\
    3928f377-6f4f-8044-85bf-000b726df449|3928f3776f4f804485bf000b726df449|\
    3928f377-6f4f-80c8-8605-000b567bbdeb|3928f3776f4f80c88605000b567bbdeb)
      reason="notion-create-pages targeting cockpit data source — allowed"
      if command -v jq >/dev/null 2>&1; then
        jq -nc --arg r "$reason" \
          '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"allow",permissionDecisionReason:$r}}'
      else
        printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow","permissionDecisionReason":"%s"}}\n' "$reason"
      fi
      exit 0
      ;;
  esac
fi

# A command that only reads is not a mutation, and looking around is exactly
# what a session does before it knows what to call itself. exit 0 is "no
# opinion": the normal allowlist or permission prompt still decides.
if [ "$tool" = "Bash" ] && hook_is_readonly_bash "$cmd"; then
  exit 0
fi

# Check transcript for a custom-title record (written by /rename or auto-rename).
if [ -n "$transcript" ] && [ -f "$transcript" ] && grep -q '"type":"custom-title"' "$transcript"; then
  : > "$marker"
  exit 0
fi

reason="This session has no name yet — Edit/Write/Agent, shell commands that change something, and Notion MCP write tools are DENIED until it is named. Commands that only read are free. Assistant: do not reply to the user, retry this tool call, or work around the block — derive a name and run \$HOME/.claude-shared/auto-rename NOW, passing the name as its single quoted argument. Read \$HOME/.claude-shared/templates/session-name.md for the name to pass — it is the one place the convention is stated, and reading is free while the session is unnamed. This hook intercepts that call, records the name, and unlocks the session; naming is self-serve. Ask the user for a name only when nothing in the session gives you a basis for one."
if command -v jq >/dev/null 2>&1; then
  jq -nc --arg r "$reason" \
    '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'
else
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"%s"}}\n' "$reason"
fi
exit 0
