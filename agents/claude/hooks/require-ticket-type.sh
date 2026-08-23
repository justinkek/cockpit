#!/usr/bin/env bash

input="$(cat)"

command -v jq >/dev/null 2>&1 || exit 0

ds_id="$(printf '%s' "$input" | jq -r '.tool_input.parent.data_source_id // empty' | tr -d '-')"
[ -n "$ds_id" ] || exit 0

case "$ds_id" in
  a758f3776f4f83c6ba2007fdca79919b) ;;
  *) exit 0 ;;
esac

missing="$(printf '%s' "$input" | jq '[.tool_input.pages // [] | .[] | select((.properties.Type // "") == "")] | length')"
[ "$missing" -gt 0 ] || exit 0

reason="Cockpit tickets require a Type property — $missing page(s) missing. Set Type to \"Feature\", \"Bug\", or \"Timebox\" on every page in the create-pages call, then retry. If the type is not obvious from context, ask the user before creating."
jq -nc --arg r "$reason" \
  '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'
exit 0
