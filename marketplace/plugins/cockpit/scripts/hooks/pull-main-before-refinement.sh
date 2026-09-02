#!/usr/bin/env bash

input="$(cat)"

command -v jq >/dev/null 2>&1 || exit 0

skill="$(printf '%s' "$input" | jq --raw-output '.tool_input.skill // empty')"
case "$skill" in
cockpit:ticket:1:br | cockpit:ticket:2:tr) ;;
*) exit 0 ;;
esac

working_directory="$(printf '%s' "$input" | jq --raw-output '.cwd // empty')"
[ -n "$working_directory" ] || exit 0

PLUGIN_DIRECTORY="${COCKPIT_PLUGIN_DIR:-$HOME/.cockpit}"

"$PLUGIN_DIRECTORY/scripts/hooks/pull-main.sh" "$working_directory" </dev/null
