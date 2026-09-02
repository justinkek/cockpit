#!/usr/bin/env bash

repo_root_through_symlink() {
  cd "$(dirname "$0")" && cd "$(pwd -P)/../.." && pwd
}

REPO="$(repo_root_through_symlink)"
TEMPLATE="$REPO/agents/claude/templates/pull-request-to-ticket.md"
TEMPLATE_RULE="A link to the ticket page and nothing else"

BODY_SOURCES=(
  "marketplace/plugins/cockpit/skills/cockpit:ticket:4:ready-for-cr/SKILL.md"
  "marketplace/plugins/cockpit/skills/cockpit:ticket:x:destock/SKILL.md"
)

pass=0
fail=0

assert_ok() {
  local label="$1"
  printf "  OK  %s\n" "$label"
  pass=$((pass + 1))
}

assert_ko() {
  local label="$1" detail="$2"
  printf "  KO  %s — %s\n" "$label" "$detail"
  fail=$((fail + 1))
}

printf "Test group: no path that opens a pull request writes a body of its own\n"

for path in "${BODY_SOURCES[@]}"; do
  inlined="$(grep --count -- '--body "\$(cat <<' "$REPO/$path")"
  if [ "$inlined" = "0" ]; then
    assert_ok "$path takes its body from the template"
  else
    assert_ko "$path takes its body from the template" "writes $inlined here-document(s) of its own"
  fi

  if grep --quiet --fixed-strings "pull-request-to-ticket.md" "$REPO/$path"; then
    assert_ok "$path names the template it takes it from"
  else
    assert_ko "$path names the template it takes it from" "no line names pull-request-to-ticket.md"
  fi
done

printf "\nTest group: the template holds the rule and the body it describes\n"

if grep --quiet --fixed-strings "$TEMPLATE_RULE" "$TEMPLATE"; then
  assert_ok "the template states what the body holds"
else
  assert_ko "the template states what the body holds" "no line reads: $TEMPLATE_RULE"
fi

written="$(awk '/^ *## Ticket$/ { found = 1; next } found { print; exit }' "$TEMPLATE")"

if printf '%s' "$written" | grep --quiet '^ *\[.*\](.*)$'; then
  assert_ok "and shows the Ticket heading with the link under it"
else
  assert_ko "and shows the Ticket heading with the link under it" "found under the heading: $written"
fi

printf "\n%d passed, %d failed\n" "$pass" "$fail"
[ "$fail" -eq 0 ]
