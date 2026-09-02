#!/usr/bin/env bash

input="$(cat)"

if ! command -v jq >/dev/null 2>&1; then
  exit 0
fi

status="$(printf '%s' "$input" | jq -r '.tool_input.properties.Status // empty')"

[ "$status" = "Sprint Backlog" ] || exit 0

page_id="$(printf '%s' "$input" | jq -r '.tool_input.page_id // empty')"
[ -n "$page_id" ] || exit 0

cat <<MSG
[sprint-backlog-sync] You just moved page ${page_id} to Sprint Backlog. You MUST now:
1. Fetch the Sprints data source - its id comes from `"$HOME/.cockpit/scripts/cockpit-board-id" get sprints-data-source`, see ~/.claude-shared/templates/board-ids.md - to find the sprint whose Start Date <= today <= End Date. If zero or multiple sprints match, ask the user to specify.
2. Fetch the ticket (page ${page_id}) to check its current Sprints relation and Due date.
3. If Sprints is empty, set it to the matching sprint's page URL.
4. If Due is empty, set it to the sprint's End Date.
Do not overwrite existing values.
MSG
exit 0
