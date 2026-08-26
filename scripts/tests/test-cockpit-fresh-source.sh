#!/usr/bin/env bash

REPO="$(cd "$(dirname "$0")" && cd "$(pwd -P)/../.." && pwd)"
COMMAND="$REPO/agents/claude/bin/cockpit-fresh"
TEMP="$(cd "$(mktemp -d)" && pwd -P)"
trap 'rm -rf "$TEMP"' EXIT

export GIT_AUTHOR_NAME=probe
export GIT_AUTHOR_EMAIL=probe@example.com
export GIT_COMMITTER_NAME=probe
export GIT_COMMITTER_EMAIL=probe@example.com

pass=0
fail=0

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

assert_holds() {
  local label="$1" actual="$2" needle="$3"
  case "$actual" in
    *"$needle"*)
      printf "  OK  %s\n" "$label"
      pass=$((pass + 1))
      ;;
    *)
      printf "  KO  %s — '%s' does not hold '%s'\n" "$label" "$actual" "$needle"
      fail=$((fail + 1))
      ;;
  esac
}

CHECKOUT="$TEMP/checkout"
mkdir -p "$CHECKOUT/agents/claude/bin"
: > "$CHECKOUT/install.sh"
: > "$CHECKOUT/agents/claude/bin/cockpit"
git -C "$CHECKOUT" init --quiet --initial-branch main
git -C "$CHECKOUT" add --all
git -C "$CHECKOUT" commit --quiet --message "probe"
git -C "$CHECKOUT" worktree add --quiet --detach "$TEMP/tree" >/dev/null 2>&1
git -C "$TEMP/tree" switch --quiet --create feat/probe-branch

ELSEWHERE="$TEMP/elsewhere"
mkdir -p "$ELSEWHERE"

source_from() { ( cd "$1" && bash "$COMMAND" --print-source ); }

printf "Test group: the checkout the caller is standing in is what gets installed\n"

read -r source reference <<< "$(source_from "$CHECKOUT")"
assert_equal "the main checkout installs itself" "$source" "$CHECKOUT"
assert_equal "on its own branch" "$reference" "main"

read -r source reference <<< "$(source_from "$TEMP/tree")"
assert_equal "a worktree installs itself" "$source" "$TEMP/tree"
assert_equal "on the branch it is on" "$reference" "feat/probe-branch"

printf "\nTest group: outside any checkout it falls back to the remote\n"

read -r source reference <<< "$(source_from "$ELSEWHERE")"
assert_holds "the source is the upstream url" "$source" "github.com"
assert_equal "and the reference is main" "$reference" "main"

printf "\nTest group: a directory that is a repo but not this one falls back too\n"

STRANGER="$TEMP/stranger"
mkdir -p "$STRANGER"
git -C "$STRANGER" init --quiet --initial-branch main
read -r source reference <<< "$(source_from "$STRANGER")"
assert_holds "another repository is not mistaken for this one" "$source" "github.com"

printf "\nTest group: the environment variable still wins\n"

read -r source reference <<< "$(COCKPIT_FRESH_REMOTE="$CHECKOUT" source_from "$ELSEWHERE")"
assert_equal "an explicit remote overrides the walk" "$source" "$CHECKOUT"

printf "\n%d passed, %d failed\n" "$pass" "$fail"
[ "$fail" -eq 0 ]
