#!/usr/bin/env bash

HOOKS_DIR="$(cd "$(dirname "$0")/.." && pwd)"
REPO="$(cd "$HOOKS_DIR/../../.." && pwd)"
CONVENTIONS="$REPO/AGENTS.md"

REVIEW_COLUMNS="Ready for CR
In CR
Ready for FR
In FR
Ready for Validation"

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

skip_list="$(awk '/^## Ticket walk skip$/{f=1;next} /^## /{f=0} f && /^- /{sub(/^- /,"");print}' "$CONVENTIONS")"

printf "Test group: the walk keeps every review the contract names\n"

while IFS= read -r column; do
  skipped="no"
  printf '%s\n' "$skip_list" | grep --quiet --line-regexp --fixed-strings "$column" && skipped="yes"
  assert_eq "$column" "no" "$skipped"
done <<< "$REVIEW_COLUMNS"

printf "\n%d passed, %d failed\n" "$pass" "$fail"
[ "$fail" -eq 0 ]
