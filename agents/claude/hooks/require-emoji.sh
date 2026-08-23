#!/usr/bin/env bash

input="$(cat)"

command -v jq >/dev/null 2>&1 || exit 0

ds_id="$(printf '%s' "$input" | jq -r '.tool_input.parent.data_source_id // empty' | tr -d '-')"
[ -n "$ds_id" ] || exit 0

case "$ds_id" in
  a758f3776f4f83c6ba2007fdca79919b|\
  3928f3776f4f804485bf000b726df449|\
  3928f3776f4f80c88605000b567bbdeb) ;;
  *) exit 0 ;;
esac

missing="$(printf '%s' "$input" | jq '[.tool_input.pages // [] | .[] | select((.icon // "") == "")] | length')"
[ "$missing" -gt 0 ] || exit 0

reason="Cockpit pages require an emoji icon — $missing page(s) missing. Add an icon (emoji) to every page in the create-pages call, then retry."
jq -nc --arg r "$reason" \
  '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'
exit 0
