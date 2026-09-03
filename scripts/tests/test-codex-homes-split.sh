#!/usr/bin/env bash

repo_root_through_symlink() {
  cd "$(dirname "$0")" && cd "$(pwd -P)/../.." && pwd
}

REPO="$(repo_root_through_symlink)"
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

pass=0
fail=0

assert_absent() {
  local label="$1" file="$2" phrase="$3"
  if grep --quiet --fixed-strings "$phrase" "$file"; then
    printf "  KO  %s — '%s' is still in %s\n" "$label" "$phrase" "$file"
    fail=$((fail + 1))
  else
    printf "  OK  %s\n" "$label"
    pass=$((pass + 1))
  fi
}

assert_contains() {
  local label="$1" file="$2" phrase="$3"
  if grep --quiet --fixed-strings "$phrase" "$file"; then
    printf "  OK  %s\n" "$label"
    pass=$((pass + 1))
  else
    printf "  KO  %s — '%s' is not in %s\n" "$label" "$phrase" "$file"
    fail=$((fail + 1))
  fi
}

AGENTS_SHARED="$TMPDIR/agents-shared"
PROBE_HOME="$TMPDIR/home"
mkdir -p "$AGENTS_SHARED" "$PROBE_HOME"
cp "$REPO/agents/shared/base.AGENTS.md" "$AGENTS_SHARED/base.AGENTS.md"
cp "$REPO/agents/shared/board.AGENTS.md" "$AGENTS_SHARED/board.AGENTS.md"
cp "$REPO/agents/shared/prompts.sh" "$AGENTS_SHARED/prompts.sh"

AGENTS_SHARED_DIR="$AGENTS_SHARED" HOME="$PROBE_HOME" \
  bash "$REPO/agents/codex/sync.sh" agents-md --apply > "$TMPDIR/apply.out" 2>&1 < /dev/null

UNWRAPPED="$PROBE_HOME/.codex/AGENTS.md"
WRAPPED="$PROBE_HOME/.codex-cockpit/AGENTS.md"

if [ ! -f "$UNWRAPPED" ] || [ ! -f "$WRAPPED" ]; then
  printf "  KO  the sync wrote an AGENTS.md for both homes\n"
  cat "$TMPDIR/apply.out"
  printf "\n%d passed, %d failed\n" "$pass" "$((fail + 1))"
  exit 1
fi

printf "Test group: the home an unwrapped launch lands in loses the board\n"

assert_absent "no ticket registration rule" "$UNWRAPPED" "Cockpit URL-first"
assert_absent "no claim lock rule" "$UNWRAPPED" "## Claim locks"
assert_contains "and keeps the writing rules" "$UNWRAPPED" "## Solution ladder"
assert_contains "and the solution ladder" "$UNWRAPPED" "## Solution ladder"

printf "\nTest group: the home a wrapper points at gets the board\n"

assert_contains "the ticket registration rule" "$WRAPPED" "Cockpit URL-first"
assert_contains "the claim lock rule" "$WRAPPED" "## Claim locks"
assert_contains "and the writing rules too" "$WRAPPED" "## Solution ladder"

printf "\nTest group: the ticket gate is in the board hooks profile alone\n"

assert_absent "the shared profile does not require a ticket" \
  "$REPO/agents/codex/settings/base.hooks-profile.toml" "require-ticket.sh"
assert_contains "the board profile does" \
  "$REPO/agents/codex/settings/board.hooks-profile.toml" "require-ticket.sh"
assert_contains "and the shared profile keeps the secret guard" \
  "$REPO/agents/codex/settings/base.hooks-profile.toml" "guard-bash-secret-read.sh"

printf "\n%d passed, %d failed\n" "$pass" "$fail"
[ "$fail" -eq 0 ]
