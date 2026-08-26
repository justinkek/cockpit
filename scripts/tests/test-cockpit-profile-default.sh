#!/usr/bin/env bash

REPO="$(cd "$(dirname "$0")" && cd "$(pwd -P)/../.." && pwd)"
TEMP="$(mktemp -d)"
trap 'rm -rf "$TEMP"' EXIT

pass=0
fail=0

cp "$REPO/agents/claude/accounts.sh" "$TEMP/accounts.sh"
cp "$REPO/agents/claude/accounts.local.sh.example" "$TEMP/example.sh"
export HOME="$TEMP/home"

read_list() { bash -c 'source "$1"; printf "%s" "${ACCOUNTS[*]}"' _ "$1"; }
read_directory() { bash -c 'source "$1"; acct_dir "$2"' _ "$TEMP/accounts.sh" "$1"; }

assert_equal() {
  local label="$1" actual="$2" expected="$3"
  if [ "$actual" = "$expected" ]; then
    printf "  OK  %s\n" "$label"
    pass=$((pass + 1))
  else
    printf "  KO  %s — got '%s', expected '%s'\n" "$label" "$actual" "$expected"
    fail=$((fail + 1))
  fi
}

assert_unequal() {
  local label="$1" actual="$2" forbidden="$3"
  if [ "$actual" != "$forbidden" ]; then
    printf "  OK  %s\n" "$label"
    pass=$((pass + 1))
  else
    printf "  KO  %s — it is '%s'\n" "$label" "$actual"
    fail=$((fail + 1))
  fi
}

assert_empty() {
  local label="$1" actual="$2"
  if [ -z "$actual" ]; then
    printf "  OK  %s\n" "$label"
    pass=$((pass + 1))
  else
    printf "  KO  %s — it holds '%s'\n" "$label" "$actual"
    fail=$((fail + 1))
  fi
}

printf "Test group: a clone with no overlay writes to the cockpit profile alone\n"

assert_equal "the committed list names cockpit and nothing else" "$(read_list "$TEMP/accounts.sh")" "cockpit"
assert_equal "the scaffolded example names it too" "$(read_list "$TEMP/example.sh")" "cockpit"
assert_equal "cockpit maps to a directory of its own" "$(read_directory cockpit)" "$HOME/.claude-cockpit"

printf "\nTest group: the profile the user already runs is left out of the list\n"

for account in $(read_list "$TEMP/accounts.sh"); do
  assert_unequal "$account is not the desktop profile" "$(read_directory "$account")" "$HOME/.claude"
done

printf "\nTest group: nobody's own per-account settings travel with the clone\n"

assert_empty "git tracks no file in the overrides directory" \
  "$(git -C "$REPO" ls-files agents/claude/settings/overrides)"

printf "\n%d passed, %d failed\n" "$pass" "$fail"
[ "$fail" -eq 0 ]
