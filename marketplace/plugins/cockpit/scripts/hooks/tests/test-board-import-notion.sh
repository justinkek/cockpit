#!/usr/bin/env bash

SCRIPTS="$(cd "$(dirname "$0")/../.." && pwd)"
export CLAUDE_SHARED_DIR="$(cd "$SCRIPTS/../../../../agents/claude" && pwd)"
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

export COCKPIT_BOARD_DIR="$TMPDIR/board"
export COCKPIT_BOARDS_FILE="$TMPDIR/boards.json"
export NOTION_QUERY_FIXTURE_DIR="$TMPDIR/notion"
mkdir -p "$NOTION_QUERY_FIXTURE_DIR"

pass=0
fail=0

assert_eq() {
  local label="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then
    printf "  OK  %s\n" "$label"
    pass=$((pass + 1))
  else
    printf "  KO  %s — expected '%s', got '%s'\n" "$label" "$expected" "$actual"
    fail=$((fail + 1))
  fi
}

importer() { bash "$SCRIPTS/board-import-notion" "$@"; }
field() { bash "$SCRIPTS/board-card" show "$1" --json | jq --raw-output "$2"; }

cat > "$COCKPIT_BOARDS_FILE" <<'JSON'
{"boards": [{"name": "Cockpit", "ids": {
  "tickets-database": "tickets", "epics-database": "epics",
  "projects-database": "projects", "reference-tickets-database": "references",
  "sprints-view": "https://app.notion.com/p/aaaabbbbccccddddeeeeffff00001111?v=1"}}]}
JSON

ticket() {
  jq --null-input --compact-output --arg id "$1" --arg number "$2" --arg type "$3" --arg name "$4" --arg epic "$5" '{
    id: $id, created_time: "2026-10-01T00:00:00.000Z", url: "https://app.notion.com/p/\($id)",
    properties: {
      "Ticket No.": {unique_id: {prefix: "COC", number: ($number | tonumber)}},
      Name: {title: [{plain_text: $name}]},
      Type: {select: {name: $type}},
      Status: {status: {name: "Backlog"}},
      Epic: {relation: (if $epic == "" then [] else [{id: $epic}] end)},
      Assignee: {people: [{name: "someone"}]},
      "Source Ticket URL": {rich_text: [{plain_text: "https://elsewhere.example/1"}]},
      "Date: In Dev": {type: "date", date: {start: "2026-10-02"}}}}'
}

{
  ticket "11111111111111111111111111111111" 5 Feature "A feature" "e1e1e1e1e1e1e1e1e1e1e1e1e1e1e1e1"
  ticket "22222222222222222222222222222222" 6 Bug "A bug" ""
} > "$NOTION_QUERY_FIXTURE_DIR/tickets.json"
jq --null-input --compact-output '{id: "e1e1e1e1e1e1e1e1e1e1e1e1e1e1e1e1", created_time: "2026-09-01T00:00:00.000Z",
  url: "https://app.notion.com/p/e1e1e1e1e1e1e1e1e1e1e1e1e1e1e1e1",
  properties: {Name: {type: "title", title: [{plain_text: "An epic"}]}, Status: {status: {name: "In FD by AI"}}}}' \
  > "$NOTION_QUERY_FIXTURE_DIR/epics.json"
: > "$NOTION_QUERY_FIXTURE_DIR/projects.json"
: > "$NOTION_QUERY_FIXTURE_DIR/references.json"
: > "$NOTION_QUERY_FIXTURE_DIR/aaaabbbbccccddddeeeeffff00001111.json"
{
  jq --null-input --compact-output '{id: "b1", type: "heading_2", has_children: false, heading_2: {rich_text: [{plain_text: "Context"}]}}'
  jq --null-input --compact-output '{id: "b2", type: "to_do", has_children: false, to_do: {checked: true, rich_text: [{plain_text: "done step"}]}}'
} > "$NOTION_QUERY_FIXTURE_DIR/blocks-11111111111111111111111111111111.json"

printf "Test group: the ids are read from boards.json\n"

importer >/dev/null 2>&1
assert_eq "the import succeeds" "0" "$?"
assert_eq "a feature is numbered with FEAT" "A feature" "$(field FEAT-5 .name)"
assert_eq "a bug is numbered with BUG" "A bug" "$(field BUG-6 .name)"
assert_eq "the epic is its own record" "An epic" "$(field EPIC-1 .name)"
assert_eq "a card names its epic by id" "EPIC-1" "$(field FEAT-5 .epic)"
assert_eq "dates come across" "2026-10-02" "$(field FEAT-5 '.dates["In Dev"]')"
assert_eq "no assignee comes across" "false" "$(field FEAT-5 'has("assignee")')"
assert_eq "no source link comes across" "false" "$(field FEAT-5 'has("source_ticket")')"

printf "\nTest group: content comes across on its own\n"

importer --content FEAT-5 >/dev/null 2>&1
assert_eq "the body is markdown" "## Context|- [x] done step" "$(field FEAT-5 .body | paste -sd '|' -)"

printf "\nTest group: a missing board list is named\n"

COCKPIT_BOARDS_FILE="$TMPDIR/absent.json" bash "$SCRIPTS/board-import-notion" >/dev/null 2>&1
assert_eq "with no boards.json the import exits 2" "2" "$?"

printf "\n%d passed, %d failed\n" "$pass" "$fail"
[ "$fail" -eq 0 ]
