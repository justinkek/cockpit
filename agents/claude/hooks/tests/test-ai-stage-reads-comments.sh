#!/usr/bin/env bash

HOOKS_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CLAUDE_DIR="$(cd "$HOOKS_DIR/.." && pwd)"
PLUGIN_DIR="$(cd "$CLAUDE_DIR/../../marketplace/plugins/cockpit" && pwd)"
TEMPLATE="$CLAUDE_DIR/templates/page-comments.md"
SKILLS_DIR="$PLUGIN_DIR/skills"

pass=0
fail=0

squash() {
  awk '{ $1 = $1; printf "%s ", $0 }' "$1"
}

assert_names() {
  local label="$1" file="$2" needle="$3"
  if squash "$file" | grep --quiet --fixed-strings "$needle"; then
    printf "  OK  %s\n" "$label"
    pass=$((pass + 1))
  else
    printf "  KO  %s — no '%s' in %s\n" "$label" "$needle" "$file"
    fail=$((fail + 1))
  fi
}

assert_absent() {
  local label="$1" file="$2" needle="$3"
  if squash "$file" | grep --quiet --fixed-strings "$needle"; then
    printf "  KO  %s — '%s' is still in %s\n" "$label" "$needle" "$file"
    fail=$((fail + 1))
  else
    printf "  OK  %s\n" "$label"
    pass=$((pass + 1))
  fi
}

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

printf "Test group: every stage an agent runs opens on the comments\n"

for skill in \
  "ticket:1:br" \
  "ticket:2:tr" \
  "ticket:3:dev" \
  "ticket:5:fr" \
  "ticket:6:validation" \
  "ticket:7:done" \
  "ticket:x:back-from-column" \
  "epic:1:fd" \
  "epic:2:td"; do
  assert_names "$skill reads them" \
    "$SKILLS_DIR/$skill/SKILL.md" 'templates/page-comments.md'
done

assert_names "and dev reads them before it edits anything" \
  "$SKILLS_DIR/ticket:3:dev/SKILL.md" 'open comments before the first edit'

printf "\nTest group: one read, taken once, at the start\n"

assert_names "the template takes one read" \
  "$TEMPLATE" 'One read sees everything open:'
assert_names "and that read is the board's own" \
  "$TEMPLATE" 'board-card" comments <card-id>'
assert_names "and page and line-anchored comments come back alike" \
  "$TEMPLATE" 'Page comments and line-anchored ones come back alike'
assert_names "and leaves the resolved threads out" \
  "$TEMPLATE" 'so `--all` is never passed here'
assert_absent "and takes no further read before a write" \
  "$TEMPLATE" 'immediately before the write'

printf "\nTest group: the session reading a raised decision acts on it\n"

assert_names "whether or not its draft touched that line" \
  "$TEMPLATE" 'The session reading it now acts on it, whether or not its draft touched that line'
assert_names "an answered thread is closed by the decision template" \
  "$TEMPLATE" '`## Once it is answered` in `~/.claude-shared/templates/raise-a-decision.md`'
assert_names "and a reply that asks something back keeps it open" \
  "$TEMPLATE" 'A reply that asks something back is not an answer'
assert_names "an unanswered one past a gate is resolved with the card left alone" \
  "$TEMPLATE" 'Resolve it and change nothing on the card'
assert_names "whatever the card holds, a person's own value or a declined redraft included" \
  "$TEMPLATE" 'a value a person put there instead, or the original a redraft was offered against'
assert_absent "and never only while the card carries the default" \
  "$TEMPLATE" 'so long as the card still carries the default it names'
assert_absent "and never reads a declined redraft as accepted" \
  "$TEMPLATE" 'counts as accepted'
assert_names "a drag back is not moving past the gate" \
  "$TEMPLATE" 'A card a person dragged back to a gate or before it has not moved past that gate'
assert_names "and Done is past every gate" \
  "$TEMPLATE" 'A card in `Done` has moved past every gate'
assert_names "the time each comment was posted is read off the JSON" \
  "$TEMPLATE" 'board-card" comments <card-id> --json'
assert_names "and so are the card's column and its gate dates" \
  "$TEMPLATE" 'board-card" show <card-id> --json'
assert_absent "and the pointer at the contract carries no summary of it" \
  "$TEMPLATE" 'Moving the card on is the approval'

printf "\nTest group: the two reads carry what the gate rule compares\n"

SCRATCH="$(mktemp -d)"
trap 'rm -rf "$SCRATCH"' EXIT
export COCKPIT_BOARD_DIR="$SCRATCH/board"
export TICKET_CLAIM_LOCK_DIR="$SCRATCH/claims"
export TICKET_STATE_DIR="$SCRATCH/state"
export CLAUDE_SHARED_DIR="$CLAUDE_DIR"
export GIT_CONFIG_GLOBAL=/dev/null
export GIT_CONFIG_NOSYSTEM=1

board() { bash "$PLUGIN_DIR/scripts/board-card" "$@"; }

moved_past() {
  local id="$1" gate="$2" posted card order
  posted="$(board comments "$id" --json | jq --raw-output '.[0].comments[0].at')"
  card="$(board show "$id" --json)"
  order="$(board statuses | jq --raw-input --slurp 'split("\n")')"
  jq --null-input --raw-output --argjson card "$card" --argjson order "$order" --arg gate "$gate" --arg posted "$posted" '
    ($order | index($card.status)) > ($order | index($gate)) and (($card.dates[$gate] // "") > $posted)'
}

board init >/dev/null
board create --kind project --name Home --key HOM >/dev/null
board create --kind epic --name Home --project PRJ-1 >/dev/null
printf '## Validation Steps\n\n- [ ] AaUser I see a thing\n' \
  | board create --epic EPIC-1 --name Probe --type Feature --status "In BR by AI" --body - >/dev/null
printf '**[suggestion]** a redraft\n**[why]** a reason\n' \
  | COCKPIT_AUTHOR="claude abcdef12" board comment HOM-1 --anchor "I see a thing" >/dev/null
sleep 1
board walk HOM-1 "In TR by AI" >/dev/null

assert_eq "each comment carries when it was posted" "true" \
  "$(board comments HOM-1 --json | jq '.[0].comments[0].at | type == "string"')"
assert_eq "a card walked on out of In BR has moved past it" "true" "$(moved_past HOM-1 "In BR")"
assert_eq "but not past In TR, which it has not reached" "false" "$(moved_past HOM-1 "In TR")"

board move HOM-1 "Ready for BR by AI" >/dev/null
assert_eq "a card dragged back before In BR has not moved past it" "false" "$(moved_past HOM-1 "In BR")"

printf "\n%d passed, %d failed\n" "$pass" "$fail"
[ "$fail" -eq 0 ]
