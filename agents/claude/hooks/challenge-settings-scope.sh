#!/usr/bin/env bash

input="$(cat)"

if command -v jq >/dev/null 2>&1; then
  tool="$(printf '%s' "$input" | jq -r '.tool_name // empty')"
  session_id="$(printf '%s' "$input" | jq -r '.session_id // empty')"
  fp="$(printf '%s' "$input" | jq -r '.tool_input.file_path // empty')"
  cmd="$(printf '%s' "$input" | jq -r '.tool_input.command // empty')"
else
  tool="$(printf '%s' "$input" | sed -n 's/.*"tool_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')"
  session_id="$(printf '%s' "$input" | sed -n 's/.*"session_id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')"
  fp="$(printf '%s' "$input" | sed -n 's/.*"file_path"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')"
  cmd="$(printf '%s' "$input" | sed -n 's/.*"command"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')"
fi

[ -n "$session_id" ] || exit 0

STATE_DIR="$HOME/.local/state/claude-settings-scope"
mkdir -p "$STATE_DIR"
find "$STATE_DIR" -type f -mtime +7 -delete 2>/dev/null

marker="$STATE_DIR/$session_id"

# Intercept the confirm command: write the marker and auto-approve.
if [ "$tool" = "Bash" ] && printf '%s' "$cmd" | grep -q 'settings-scope-confirm'; then
  scope="$(printf '%s' "$cmd" | awk '{print $NF}' | tr -d '"'"'")"
  printf '%s\n' "$scope" > "$marker"

  residue="$(printf '%s' "$cmd" | sed -E "s/'[^']*'//g; s/\"[^\"]*\"//g")"
  first="$(printf '%s' "$cmd" | sed -E 's/^[[:space:]]*//' | awk '{print $1}' | tr -d '"'"'")"
  case "$residue" in *'|'*|*'&'*|*';'*|*'<'*|*'>'*|*'$('*) exit 0 ;; esac
  case "$first" in *.claude-shared/settings-scope-confirm) ;; *) exit 0 ;; esac

  reason="settings-scope-confirm (scope confirmed: $scope) — allowed"
  if command -v jq >/dev/null 2>&1; then
    jq -nc --arg r "$reason" \
      '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"allow",permissionDecisionReason:$r}}'
  else
    printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow","permissionDecisionReason":"%s"}}\n' "$reason"
  fi
  exit 0
fi

# Already confirmed -> pass.
[ -f "$marker" ] && exit 0

# Only gate Edit/Write — let other tools through.
case "$tool" in
  Edit|Write) ;;
  *) exit 0 ;;
esac

# Only gate settings files (not base.settings.json).
case "$fp" in
  */settings.json|*/settings.local.json) ;;
  *) exit 0 ;;
esac

reason="Settings scope gate: before writing to this settings file, confirm with the user which scope is appropriate. Ask: is this setting for the team on this repo (settings.json), just for you on this repo (settings.local.json), or for you everywhere (base.settings.json via dotfiles)? After the user confirms, run \"\$HOME/.claude-shared/settings-scope-confirm <scope>\" (where <scope> is project, project-local, or global) to unlock, then retry the edit."
if command -v jq >/dev/null 2>&1; then
  jq -nc --arg r "$reason" \
    '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'
else
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"%s"}}\n' "$reason"
fi
exit 0
