#!/usr/bin/env bash

REPO="$(cd "$(dirname "$0")" && cd "$(pwd -P)/../.." && pwd)"
TEMP="$(mktemp -d)"
trap 'rm -rf "$TEMP"' EXIT

pass=0
fail=0

CLONE="$TEMP/clone"
PROBE_HOME="$TEMP/home"
mkdir -p "$CLONE/agents/claude/bin" "$CLONE/agents/shared" "$CLONE/agents/codex" "$PROBE_HOME"
cp "$REPO/install.sh" "$CLONE/install.sh"
cp "$REPO/agents/claude/bin/cockpit" "$CLONE/agents/claude/bin/cockpit"

assert_link() {
  local label="$1" link="$2" target="$3"
  if [ -L "$link" ] && [ "$(readlink "$link")" = "$target" ]; then
    printf "  OK  %s\n" "$label"
    pass=$((pass + 1))
  else
    printf "  KO  %s — %s points at '%s', expected '%s'\n" "$label" "$link" "$(readlink "$link" 2>/dev/null)" "$target"
    fail=$((fail + 1))
  fi
}

assert_absent() {
  local label="$1" path="$2"
  if [ ! -e "$path" ] && [ ! -L "$path" ]; then
    printf "  OK  %s\n" "$label"
    pass=$((pass + 1))
  else
    printf "  KO  %s — %s is there\n" "$label" "$path"
    fail=$((fail + 1))
  fi
}

assert_runs() {
  local label="$1" command_path="$2"
  if [ -x "$command_path" ]; then
    printf "  OK  %s\n" "$label"
    pass=$((pass + 1))
  else
    printf "  KO  %s — %s is not executable\n" "$label" "$command_path"
    fail=$((fail + 1))
  fi
}

HOME="$PROBE_HOME" bash "$CLONE/install.sh" >/dev/null 2>&1

printf "Test group: a dry run writes nothing\n"

assert_absent "the command is not linked" "$PROBE_HOME/.local/bin/cockpit"

HOME="$PROBE_HOME" bash "$CLONE/install.sh" --apply >/dev/null 2>&1

printf "\nTest group: an apply puts the command where a shell already looks\n"

assert_link "the command is linked into the user's own bin" \
  "$PROBE_HOME/.local/bin/cockpit" "$CLONE/agents/claude/bin/cockpit"
assert_runs "and a shell can run it without chmod" "$PROBE_HOME/.local/bin/cockpit"
assert_link "the shared tree is still linked too" \
  "$PROBE_HOME/.claude-shared" "$CLONE/agents/claude"

printf "\n%d passed, %d failed\n" "$pass" "$fail"
[ "$fail" -eq 0 ]
