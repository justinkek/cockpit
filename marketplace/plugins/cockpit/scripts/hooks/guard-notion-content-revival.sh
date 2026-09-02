#!/usr/bin/env bash

input="$(cat)"

command -v jq >/dev/null 2>&1 || exit 0

command_name="$(printf '%s' "$input" | jq --raw-output '.tool_input.command // empty')"
case "$command_name" in
update_content | replace_content) ;;
*) exit 0 ;;
esac

page_id="$(printf '%s' "$input" | jq --raw-output '.tool_input.page_id // empty' | tr -d '-')"
[ -n "$page_id" ] || exit 0

written="$(printf '%s' "$input" | jq --raw-output '
  [ .tool_input.new_str // empty ] + [ .tool_input.content_updates[]?.new_str ]
  | join("\n")
  | split("\n")
  | map(gsub("^[\t ]+"; "") | gsub("[\t ]+$"; ""))
  | .[]
')"
[ -n "$written" ] || exit 0

. "$(dirname "$0")/hook-notion-page-lib.sh"

if [ -n "${GUARD_NOTION_REVIVAL_EARLIER:-}" ] && [ -r "${GUARD_NOTION_REVIVAL_EARLIER}" ]; then
  earlier="$(notion_page_squash <"$GUARD_NOTION_REVIVAL_EARLIER")"
else
  transcript_path="$(printf '%s' "$input" | jq --raw-output '.transcript_path // empty')"
  [ -r "$transcript_path" ] || exit 0
  dashed="$(printf '%s' "$page_id" | sed 's/^\(.\{8\}\)\(.\{4\}\)\(.\{4\}\)\(.\{4\}\)/\1-\2-\3-\4-/')"
  earlier="$(jq --raw-output --slurp --arg pattern "$page_id|$dashed" '
    def texts: if type == "string" then [ . ]
      else [ .[]? | select(.type == "text") | .text // "" ] end;
    def written_by_a_person:
      any(.[]; test("^<(task-notification|system-reminder)>") | not);
    [ to_entries[]
      | select(.value.type == "user")
      | select(.value.message.content | texts | written_by_a_person)
      | .key ] as $prompts
    | [ to_entries[] | select(.key > (($prompts | last) // -1)) | .value ]
    | map(select(.type == "user"))
    | map(.message.content? // [])
    | map(select(type == "array") | .[])
    | map(select(.type == "tool_result") | .content)
    | map(if type == "array" then map(select(.type == "text") | .text) | join("\n") else tostring end)
    | map(select(test($pattern)))
    | join("\n")
  ' "$transcript_path" 2>/dev/null | notion_page_squash)"
fi
[ -n "$earlier" ] || exit 0

if [ -n "${GUARD_NOTION_REVIVAL_CURRENT:-}" ] && [ -r "${GUARD_NOTION_REVIVAL_CURRENT}" ]; then
  current="$(notion_page_squash <"$GUARD_NOTION_REVIVAL_CURRENT")"
else
  token="$(notion_page_token)"
  [ -n "$token" ] || exit 0
  current="$(notion_page_text "$page_id" "$token" | notion_page_squash)"
fi
[ -n "$current" ] || exit 0

revived=""
while IFS= read -r line; do
  [ -n "$line" ] || continue
  needle="$(printf '%s' "$line" | notion_page_squash)"
  [ "${#needle}" -ge 12 ] || continue
  case "$current" in
  *"$needle"*) continue ;;
  esac
  case "$earlier" in
  *"$needle"*) revived="${revived}
  - ${line}" ;;
  esac
done <<EOF
$written
EOF

[ -n "$revived" ] || exit 0

reason="These lines are not on page ${page_id} now but were on an earlier read of it, so a person deleted them while you were drafting:${revived}

Leave them out of new_str, rebuild new_str from a fetch taken now, and say they went. Never put them back."
jq --null-input --compact-output --arg reason "$reason" \
  '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$reason}}'
exit 0
