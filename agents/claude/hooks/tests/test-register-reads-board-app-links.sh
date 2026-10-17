#!/usr/bin/env bash

AGENTS="$(cd "$(dirname "$0")/../../.." && pwd)"
REPO="$(dirname "$AGENTS")"
REGISTER="$REPO/marketplace/plugins/cockpit/skills/ticket:0:register/SKILL.md"
APP="$REPO/board"

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

has() { grep --fixed-strings --quiet -- "$1" "$2" && echo yes || echo no; }

line_of() {
  local hit
  hit="$(grep --line-number --fixed-strings -- "$1" "$2" | head -n 1)"
  printf '%s' "${hit%%:*}"
}

printf "Test group: the links register reads are the ones the app serves\n"

assert_eq "the app listens on 4646" "yes" "$(has '--port 4646' "$APP/package.json")"
assert_eq "the app serves a card page at /card/<id>" "yes" "$([ -f "$APP/app/card/[id]/page.tsx" ] && echo yes || echo no)"
assert_eq "the board opens a card at /?open=<id>" "yes" "$(has 'return `/?open=${id}`' "$APP/lib/shared.ts")"
assert_eq "the board reads the record to open from ?open=" "yes" "$(has '.get("open")' "$APP/app/record-overlay.tsx")"
assert_eq "the epics board opens an epic at /epics?open=<id>" "yes" "$(has '/epics?open=${' "$APP/app/markdown.tsx")"

printf "\nTest group: register takes a board app link as the id it names\n"

assert_eq "a /card/<id> link is named" "yes" "$(has 'http://<host>:4646/card/<id>' "$REGISTER")"
assert_eq "a /?open=<id> link is named" "yes" "$(has 'http://<host>:4646/?open=<id>' "$REGISTER")"
assert_eq "an /epics?open=<id> link is named" "yes" "$(has 'http://<host>:4646/epics?open=<id>' "$REGISTER")"
assert_eq "the id is resolved as case 1" "yes" "$(has 'Take the id out of it and resolve that id as case 1.' "$REGISTER")"
assert_eq "a link never creates a card" "yes" "$(has "It is never case 3's URL" "$REGISTER")"

link="$(line_of 'http://<host>:4646/card/<id>' "$REGISTER")"
cases="$(line_of '1. **Ticket id**' "$REGISTER")"
assert_eq "the link is read before the cases are" "yes" "$([ -n "$link" ] && [ -n "$cases" ] && [ "$link" -lt "$cases" ] && echo yes || echo no)"

printf "\n%d passed, %d failed\n" "$pass" "$fail"
[ "$fail" -eq 0 ]
