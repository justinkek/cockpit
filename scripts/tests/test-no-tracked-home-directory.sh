#!/usr/bin/env bash

repo_root_through_symlink() {
  cd "$(dirname "$0")" && cd "$(pwd -P)/../.." && pwd
}

REPO="$(repo_root_through_symlink)"

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

PORTABLE=(agents scripts install.sh)

printf "Test group: nothing the agent workflow needs spells out the home directory it was written on\n"

naming_this_home="$(git -C "$REPO" grep --files-with-matches --fixed-strings "$HOME/" -- "${PORTABLE[@]}" | tr '\n' ' ')"

if [ -z "$naming_this_home" ]; then
  assert_ok "the machine's own home directory appears in none of ${PORTABLE[*]}"
else
  assert_ko "the machine's own home directory appears in none of ${PORTABLE[*]}" \
    "it is in ${naming_this_home% }"
fi

printf "\n%d passed, %d failed\n" "$pass" "$fail"
[ "$fail" -eq 0 ]
