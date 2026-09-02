#!/usr/bin/env bash

input="$(cat)"

if ! command -v jq >/dev/null 2>&1; then
  exit 0
fi

# insert_content appends and cannot no-op; only update_content can.
command_name="$(printf '%s' "$input" | jq -r '.tool_input.command // empty')"
[ "$command_name" = "update_content" ] || exit 0

page_id="$(printf '%s' "$input" | jq -r '.tool_input.page_id // empty' | tr -d '-')"
[ -n "$page_id" ] || exit 0

. "$(dirname "$0")/hook-notion-page-lib.sh"

wordiest_line_of_each_edit="$(printf '%s' "$input" | jq --raw-output --arg markup "$notion_page_markup" '
  .tool_input.content_updates[]?
  | .new_str
  | split("\n")
  | map(gsub("^[\t ]+"; "") | gsub("[\t ]+$"; ""))
  | max_by(ascii_downcase | gsub($markup; "") | gsub("[^a-z0-9]"; "") | length) // empty
')"
[ -n "$wordiest_line_of_each_edit" ] || exit 0

# Test seam: a file of page text stands in for the REST call, so the test needs
# no credential and no network.
if [ -n "${VERIFY_NOTION_CONTENT_EDIT_TEXT:-}" ] && [ -r "${VERIFY_NOTION_CONTENT_EDIT_TEXT}" ]; then
  haystack="$(notion_page_squash <"$VERIFY_NOTION_CONTENT_EDIT_TEXT")"
else
  token="$(notion_page_token)"
  if [ -z "$token" ]; then
    echo "[verify-edit] No credential, so this edit could not be confirmed. Re-read page ${page_id} before reporting it done."
    exit 0
  fi
  haystack="$(notion_page_text "$page_id" "$token" | notion_page_squash)"
fi

if [ -z "$haystack" ]; then
  echo "[verify-edit] Could not read page ${page_id} back, so this edit is unconfirmed. Re-read it before reporting it done."
  exit 0
fi

missing=""
while IFS= read -r line; do
  [ -n "$line" ] || continue
  needle="$(printf '%s' "$line" | notion_page_squash)"
  # Too little left to match on: a hit would be luck, not evidence.
  if [ "${#needle}" -lt 12 ]; then
    missing="${missing}
  - (too short to verify) ${line}"
    continue
  fi
  case "$haystack" in
  *"$needle"*) ;;
  *) missing="${missing}
  - ${line}" ;;
  esac
done <<EOF
$wordiest_line_of_each_edit
EOF

[ -n "$missing" ] || exit 0

echo "[verify-edit] These edits are NOT on page ${page_id} — old_str matched nothing:${missing}

Do not report them as done. Fetch the page again, rebuild old_str from what it actually says, and redo them. Report only the edits you can see on the page."
exit 0
