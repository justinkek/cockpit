#!/usr/bin/env bash
#
# notion-blocks-lib.sh — read a Notion page as blocks, and find the block that
# holds a given line.
#
# Sourced, never run. Callers set NOTION_TOKEN before calling anything here.
#
# Why blocks rather than the MCP fetch: the fetch returns the page as markdown
# and never exposes a block id, and a comment can only be anchored by block id.
# The MCP create-comment tool takes a text selection instead, and on a line
# nested under another line it resolves to the parent — which is the defect this
# file exists to remove.

# Lowercase alnum only, so indentation, list markers and inline markdown (which
# the API stores as annotations rather than characters) cannot break a match.
notion_squash() {
  tr '[:upper:]' '[:lower:]' | tr -cd '[:alnum:]'
}

NOTION_MATCH_MINIMUM_LENGTH=12

# One line per block: <id><TAB><text>. Nested blocks are included, so a clause
# written under another clause is addressable in its own right.
#
# NOTION_BLOCKS_FIXTURE is a test seam: a file in the same format stands in for
# the API, so a test needs no credential and no network.
notion_page_blocks() {
  local block_id="$1" cursor="" url body child

  if [ -n "${NOTION_BLOCKS_FIXTURE:-}" ] && [ -r "${NOTION_BLOCKS_FIXTURE}" ]; then
    cat "$NOTION_BLOCKS_FIXTURE"
    return 0
  fi

  while :; do
    url="https://api.notion.com/v1/blocks/$block_id/children?page_size=100"
    [ -n "$cursor" ] && url="$url&start_cursor=$cursor"
    # Options go in on stdin, never in argv: a token passed as an argument is
    # readable in `ps` by anything running as this user for the life of the
    # request.
    body="$(printf '%s\n' \
      "header = \"Authorization: Bearer ${NOTION_TOKEN:-}\"" \
      'header = "Notion-Version: 2022-06-28"' \
      "url = \"$url\"" \
      'silent' \
      | curl --config - 2>/dev/null)" || return 0

    printf '%s' "$body" | jq -r '
      .results[]?
      | [ .id, ([.. | .plain_text? // empty] | join("")) ]
      | @tsv' 2>/dev/null

    for child in $(printf '%s' "$body" | jq -r '.results[]? | select(.has_children == true) | .id' 2>/dev/null); do
      notion_page_blocks "$child"
    done

    cursor="$(printf '%s' "$body" | jq -r '.next_cursor // empty' 2>/dev/null)"
    [ -n "$cursor" ] || break
  done
}

# The page's text with the ids dropped, for callers that only need to ask
# whether some text is on the page at all.
notion_page_text() {
  notion_page_blocks "$1" | cut -f2-
}

NOTION_LINES_TOKEN_REJECTED=4
NOTION_LINES_UNREADABLE=5
NOTION_LINES_RATE_LIMITED=6

notion_lines_status_for_http() {
  case "$1" in
    200) return 0 ;;
    401|403) return "$NOTION_LINES_TOKEN_REJECTED" ;;
    429) return "$NOTION_LINES_RATE_LIMITED" ;;
    *) return "$NOTION_LINES_UNREADABLE" ;;
  esac
}

notion_page_lines_in_reading_order() {
  local block_id="$1" depth="${2:-0}" cursor="" url body http_status id type children text

  if [ -n "${NOTION_LINES_FIXTURE:-}" ] && [ -r "${NOTION_LINES_FIXTURE}" ]; then
    notion_lines_status_for_http "${NOTION_LINES_FIXTURE_STATUS:-200}" || return "$?"
    cat "$NOTION_LINES_FIXTURE"
    return 0
  fi

  while :; do
    url="https://api.notion.com/v1/blocks/$block_id/children?page_size=100"
    [ -n "$cursor" ] && url="$url&start_cursor=$cursor"
    body="$(printf '%s\n' \
      "header = \"Authorization: Bearer ${NOTION_TOKEN:-}\"" \
      'header = "Notion-Version: 2022-06-28"' \
      "url = \"$url\"" \
      'silent' \
      'write-out = "\n%{http_code}"' \
      | curl --config - 2>/dev/null)" || return "$NOTION_LINES_UNREADABLE"
    http_status="${body##*$'\n'}"
    body="${body%$'\n'*}"
    notion_lines_status_for_http "$http_status" || return "$?"

    while IFS=$'\t' read -r id type children text; do
      [ -n "$id" ] || continue
      printf '%s\t%s\t%s\t%s\n' "$id" "$depth" "$type" "$text"
      if [ "$children" = "true" ]; then
        notion_page_lines_in_reading_order "$id" $((depth + 1)) || return "$?"
      fi
    done <<< "$(printf '%s' "$body" | jq --raw-output '
      .results[]?
      | [ .id,
          (if .type == "to_do" and .to_do.checked then "to_do_checked" else .type end),
          (.has_children | tostring),
          ([ .[.type].rich_text[]?.plain_text ] | join("")) ]
      | @tsv' 2>/dev/null)"

    cursor="$(printf '%s' "$body" | jq --raw-output '.next_cursor // empty' 2>/dev/null)"
    [ -n "$cursor" ] || break
  done
}

notion_unresolved_comments_on_block() {
  local block_id="$1" body

  if [ -n "${NOTION_COMMENTS_FIXTURE:-}" ] && [ -r "${NOTION_COMMENTS_FIXTURE}" ]; then
    jq --raw-output --arg block "$block_id" 'select(.block == $block) | .text' \
      < "$NOTION_COMMENTS_FIXTURE" 2>/dev/null
    return 0
  fi

  body="$(printf '%s\n' \
    "header = \"Authorization: Bearer ${NOTION_TOKEN:-}\"" \
    'header = "Notion-Version: 2022-06-28"' \
    "url = \"https://api.notion.com/v1/comments?block_id=$block_id\"" \
    'silent' \
    | curl --config - 2>/dev/null)" || return 0

  printf '%s' "$body" | jq --raw-output '
    .results[]?
    | ([ .rich_text[]?.plain_text ] | join("")) as $text
    | select($text != "")
    | $text' 2>/dev/null
}

# The id of the one block whose text contains <line>.
#
# Prints nothing and exits non-zero on no match and on more than one. A guess
# would put the comment on the wrong line, and Notion has no delete-comment API
# to take it back with — only the user can remove it by hand.
notion_match_block() {
  local page_id="$1" line="$2" needle hits count

  needle="$(printf '%s' "$line" | notion_squash)"
  # Too little left to match on: a hit would be luck, not evidence.
  if [ "${#needle}" -lt "$NOTION_MATCH_MINIMUM_LENGTH" ]; then
    return 2
  fi

  # `[[ ]]` rather than `case`: bash 3.2, which is what macOS ships, cannot
  # parse a case pattern's `)` inside a command substitution.
  hits="$(notion_page_blocks "$page_id" | while IFS=$'\t' read -r id text; do
    [ -n "$id" ] || continue
    if [[ "$(printf '%s' "$text" | notion_squash)" == *"$needle"* ]]; then
      printf '%s\n' "$id"
    fi
  done)"

  count="$(printf '%s\n' "$hits" | grep -c . || true)"
  [ "$count" -eq 1 ] || return 1
  printf '%s\n' "$hits"
}

notion_match_block_depth() {
  local page_id="$1" line="$2" needle hits count

  needle="$(printf '%s' "$line" | notion_squash)"
  if [ "${#needle}" -lt "$NOTION_MATCH_MINIMUM_LENGTH" ]; then
    return 2
  fi

  hits="$(notion_page_lines_in_reading_order "$page_id" | while IFS=$'\t' read -r id depth type text; do
    [ -n "$id" ] || continue
    if [[ "$(printf '%s' "$text" | notion_squash)" == *"$needle"* ]]; then
      printf '%s\t%s\n' "$id" "$depth"
    fi
  done)"

  count="$(printf '%s\n' "$hits" | grep --count . || true)"
  [ "$count" -eq 1 ] || return 1
  printf '%s\n' "$hits"
}
