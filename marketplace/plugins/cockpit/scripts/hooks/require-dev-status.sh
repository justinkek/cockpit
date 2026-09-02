#!/usr/bin/env bash

input="$(cat)"

if command -v jq >/dev/null 2>&1; then
  tool="$(printf '%s' "$input" | jq -r '.tool_name // empty')"
  session_id="$(printf '%s' "$input" | jq -r '.session_id // empty')"
  cmd="$(printf '%s' "$input" | jq -r '.tool_input.command // empty')"
  file_path="$(printf '%s' "$input" | jq --raw-output '.tool_input.file_path // empty')"
  cwd="$(printf '%s' "$input" | jq --raw-output '.cwd // empty')"
else
  tool="$(printf '%s' "$input" | sed -n 's/.*"tool_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')"
  session_id="$(printf '%s' "$input" | sed -n 's/.*"session_id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')"
  cmd="$(printf '%s' "$input" | sed -n 's/.*"command"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')"
  file_path="$(printf '%s' "$input" | grep --only-matching '"file_path"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed -n 's/.*"\([^"]*\)"$/\1/p')"
  cwd="$(printf '%s' "$input" | grep --only-matching '"cwd"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed -n 's/.*"\([^"]*\)"$/\1/p')"
fi

deny() {
  if command -v jq >/dev/null 2>&1; then
    jq --null-input --compact-output --arg r "$1" \
      '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'
  else
    printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"%s"}}\n' "$1"
  fi
  exit 0
}

[ -n "$session_id" ] || exit 0

STATE_DIR="$HOME/.local/state/claude-ticket-sessions"
ticket_marker="$STATE_DIR/$session_id.ticket"
stage_marker="$STATE_DIR/${session_id}.stage-dev"

# No registered ticket -> defer (require-ticket.sh owns that gate).
[ -f "$ticket_marker" ] || exit 0

if [ "$tool" = "Bash" ] && printf '%s' "$cmd" | grep -q 'ticket-status-confirm'; then
  residue="$(printf '%s' "$cmd" | sed -E "s/'[^']*'//g; s/\"[^\"]*\"//g")"
  first="$(printf '%s' "$cmd" | sed -E 's/^[[:space:]]*//' | awk '{print $1}' | tr -d '"'"'")"
  case "$residue" in *'|'*|*'&'*|*';'*|*'<'*|*'>'*|*'$('*) exit 0 ;; esac
  case "$first" in *.cockpit/scripts/ticket-status-confirm) ;; *) exit 0 ;; esac

  : > "$stage_marker"

  reason="ticket-status-confirm (stage advancement confirmed) — allowed"
  if command -v jq >/dev/null 2>&1; then
    jq -nc --arg r "$reason" \
      '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"allow",permissionDecisionReason:$r}}'
  else
    printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow","permissionDecisionReason":"%s"}}\n' "$reason"
  fi
  exit 0
fi

# Only gate Edit/Write — let Bash through (require-ticket.sh gates Bash separately).
case "$tool" in
  Edit|Write) ;;
  *) exit 0 ;;
esac

if [ -z "$file_path" ]; then
  target_dir="$cwd"
elif [ "${file_path#/}" != "$file_path" ]; then
  target_dir="$(dirname "$file_path")"
else
  target_dir="$(dirname "$cwd/$file_path")"
fi
while [ ! -d "$target_dir" ] && [ "$target_dir" != "/" ] && [ "$target_dir" != "." ]; do
  target_dir="$(dirname "$target_dir")"
done
git_dirs="$(git -C "$target_dir" rev-parse --path-format=absolute --git-dir --git-common-dir 2>/dev/null)"
own_git_dir="$(printf '%s\n' "$git_dirs" | head -1)"
shared_git_dir="$(printf '%s\n' "$git_dirs" | tail -1)"
in_main_checkout=false
[ -n "$own_git_dir" ] && [ "$own_git_dir" = "$shared_git_dir" ] && in_main_checkout=true

if [ "$in_main_checkout" = true ]; then
  deny "Worktree gate: dev happens in the ticket's own worktree, never the main checkout — two sessions sharing one checkout share its branch. Assistant: do not ask the user — invoke the cockpit:ticket:3:dev skill (/cockpit:ticket:3:dev), which enters one, then retry the edit."
fi

# Already confirmed -> pass.
[ -f "$stage_marker" ] && exit 0

deny "Ticket status gate: the ticket must be advanced to In Dev before editing files. Assistant: do not ask the user — invoke the cockpit:ticket:3:dev skill (/cockpit:ticket:3:dev) to start dev. It will advance the ticket and unlock file edits. Retry the edit after /cockpit:ticket:3:dev completes."
