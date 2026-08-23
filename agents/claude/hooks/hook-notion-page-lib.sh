#!/usr/bin/env bash

notion_page_markup='</?(details|summary|table|thead|tbody|tr|td|th|colgroup|col|mention-[a-z-]+)([[:space:]][^>]*)?/?>'

notion_page_squash() {
  tr '[:upper:]' '[:lower:]' | sed -E "s#${notion_page_markup}##g" | tr -cd '[:alnum:]'
}

notion_page_id_of() {
  local last_identifier="" identifier
  for identifier in $(printf '%s' "$1" | tr '[:upper:]' '[:lower:]' \
    | grep --only-matching --extended-regexp '[0-9a-f]{8}-?[0-9a-f]{4}-?[0-9a-f]{4}-?[0-9a-f]{4}-?[0-9a-f]{12}'); do
    last_identifier="${identifier//-/}"
  done
  printf '%s' "$last_identifier"
}

notion_page_token() {
  security find-generic-password -a "$USER" -s cockpit-notion-token -w 2>/dev/null || true
}

notion_page_text() {
  local block_id="$1" token="$2" cursor="" url body child
  while :; do
    url="https://api.notion.com/v1/blocks/$block_id/children?page_size=100"
    [ -n "$cursor" ] && url="$url&start_cursor=$cursor"
    body="$(curl --silent --show-error --header "Authorization: Bearer $token" --header "Notion-Version: 2022-06-28" "$url" 2>/dev/null)" || return 0
    printf '%s' "$body" | jq --raw-output '.results[]? | .. | .plain_text? // empty' 2>/dev/null
    for child in $(printf '%s' "$body" | jq --raw-output '.results[]? | select(.has_children == true) | .id' 2>/dev/null); do
      notion_page_text "$child" "$token"
    done
    cursor="$(printf '%s' "$body" | jq --raw-output '.next_cursor // empty' 2>/dev/null)"
    [ -n "$cursor" ] || break
  done
}
