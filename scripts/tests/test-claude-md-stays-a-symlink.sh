#!/usr/bin/env bash

repo_root_through_symlink() {
  cd "$(dirname "$0")" && cd "$(pwd -P)/../.." && pwd
}

REPO="$(repo_root_through_symlink)"

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

printf "Test group: the root CLAUDE.md is a link and never a second copy\n"

assert_eq "git tracks it as a symlink" "120000" \
  "$(git -C "$REPO" ls-files --stage CLAUDE.md | awk '{print $1}')"
assert_eq "and it points at AGENTS.md" "AGENTS.md" \
  "$(git -C "$REPO" cat-file blob "$(git -C "$REPO" ls-files --stage CLAUDE.md | awk '{print $2}')")"
assert_eq "the working tree holds a link too" "AGENTS.md" \
  "$(readlink "$REPO/CLAUDE.md")"

printf "\n%d passed, %d failed\n" "$pass" "$fail"
[ "$fail" -eq 0 ]
