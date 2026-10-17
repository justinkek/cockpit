#!/usr/bin/env bash

REPO="$(cd "$(dirname "$0")/../../../.." && pwd)"
REGISTER="$REPO/marketplace/plugins/cockpit/skills/ticket:0:register/SKILL.md"
PR_TEMPLATE="$REPO/agents/claude/templates/pull-request-to-ticket.md"

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

printf "Test group: the pre-existing PR step gates on the card before it looks\n"

gated="no"
grep --fixed-strings --quiet 'Run this step only for a ticket at `In Dev` or later, and never for a ticket this run created.' "$REGISTER" && gated="yes"
assert_eq "step 4.75 runs only for an In Dev card this run did not create" "yes" "$gated"

printf "\nTest group: the lookup keeps a PR only when its body names this card\n"

lookup="$(grep '^gh pr view ' "$REGISTER" | head -n 1)"
filter="$(printf '%s' "$lookup" | sed -n "s/.*--jq '\([^']*\)'.*/\1/p")"
assert_eq "register carries a gh pr view lookup with a --jq filter" "yes" "$([ -n "$filter" ] && echo yes || echo no)"

link_line="$(grep --fixed-strings '/card/<ticket-id>' "$PR_TEMPLATE" | head -n 1)"
assert_eq "the pull request template links the card page" "yes" "$([ -n "$link_line" ] && echo yes || echo no)"

body_for() {
  local card="$1" line="$link_line"
  line="${line//<ticket-id>/$card}"
  line="${line//<ticket-name>/Draw the diagrams}"
  printf '## Ticket\n%s\n' "$line"
}

kept_url() {
  local card="$1" body="$2"
  jq --null-input --raw-output --arg body "$body" '{url: "https://github.com/owner/repo/pull/9", body: $body}' |
    jq --raw-output "${filter//<ticket-id>/$card}" 2>/dev/null
}

url="https://github.com/owner/repo/pull/9"

assert_eq "a PR the flow opened for FEAT-7 is kept" "$url" "$(kept_url FEAT-7 "$(body_for FEAT-7)")"
assert_eq "a PR the flow opened for FEAT-72 is not taken for FEAT-7" "" "$(kept_url FEAT-7 "$(body_for FEAT-72)")"
assert_eq "a PR the flow opened for BUG-7 is not taken for FEAT-7" "" "$(kept_url FEAT-7 "$(body_for BUG-7)")"
assert_eq "a PR on the branch for other work is not taken" "" "$(kept_url FEAT-7 "Lands the board handoff")"
assert_eq "a PR with an empty body is not taken" "" "$(kept_url FEAT-7 "")"

printf "\n%d passed, %d failed\n" "$pass" "$fail"
[ "$fail" -eq 0 ]
