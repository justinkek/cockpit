#!/usr/bin/env bash

repo_root_through_symlink() {
  cd "$(dirname "$0")" && cd "$(pwd -P)/../.." && pwd
}

REPO="$(repo_root_through_symlink)"
SKILLS="$REPO/marketplace/plugins/cockpit/skills"

pass=0
fail=0

assert_ok() {
  printf "  OK  %s\n" "$1"
  pass=$((pass + 1))
}

assert_ko() {
  printf "  KO  %s — %s\n" "$1" "$2"
  fail=$((fail + 1))
}

description_of() {
  awk '/^description: / { sub(/^description: /, ""); print; exit }' "$1"
}

assert_carries() {
  local skill="$1" phrase="$2"
  case "$(description_of "$SKILLS/$skill/SKILL.md")" in
  *"$phrase"*) assert_ok "$skill keeps \"$phrase\"" ;;
  *) assert_ko "$skill keeps \"$phrase\"" "the phrase is gone from its description" ;;
  esac
}

printf "Test group: no description names a slash command\n"

for manifest in "$SKILLS"/*/SKILL.md; do
  skill="$(basename "$(dirname "$manifest")")"
  named="$(description_of "$manifest" | grep --only-matching --extended-regexp '(^|[[:space:]])/[A-Za-z][A-Za-z0-9:-]*' | tr -d '[:space:]')"
  if [ -n "$named" ]; then
    assert_ko "$skill" "its description names $(printf '%s' "$named" | tr '\n' ' ')"
  else
    assert_ok "$skill"
  fi
done

printf "\nTest group: the phrase name resolution would miss is still there\n"

assert_carries "ticket:x:destock" "save my work"
assert_carries "ticket:x:destock" "de-stock"

printf "\nTest group: the half that fires a skill unprompted is still there\n"

assert_carries "ticket:1:br" "when a ticket enters BR by AI"
assert_carries "ticket:2:tr" "when a ticket enters TR by AI"
assert_carries "epic:1:fd" "when an epic enters FD by AI"
assert_carries "ticket:3:dev" "when the require-dev-status hook blocks an edit"
assert_carries "ticket:4:ready-for-cr" "Fires on clean gates"

printf "\n%d passed, %d failed\n" "$pass" "$fail"
[ "$fail" -eq 0 ]
