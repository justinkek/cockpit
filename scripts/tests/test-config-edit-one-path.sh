#!/usr/bin/env bash

repo_root_through_symlink() {
  cd "$(dirname "$0")" && cd "$(pwd -P)/../.." && pwd
}

REPO="$(repo_root_through_symlink)"
CORE="$REPO/agents/shared/base.AGENTS.md"
ADAPTER="$REPO/agents/claude/claude-md/adapter.CLAUDE.md"
PROJECT_RULE="$REPO/AGENTS.md"
CONFIG_FILES='base\.AGENTS\.md|base\.settings\.json|base\.plugins\.json|adapter\.CLAUDE\.md'
EDIT_TARGET_PATTERN="~/\.(agents|claude)-shared/[A-Za-z0-9._/-]*($CONFIG_FILES)"

REPO_PATHS=(
  "agents/shared/base.AGENTS.md"
  "agents/claude/settings/base.settings.json"
  "agents/claude/plugins/base.plugins.json"
  "agents/claude/claude-md/adapter.CLAUDE.md"
)

ROLE_NAMES=(
  "the shared agent rules"
  "the Claude adapter"
  "the base settings file"
  "the base plugins file"
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

printf "Test group: the always-loaded rules name no config file by a path\n"

named="$(grep --only-matching --extended-regexp "$EDIT_TARGET_PATTERN" "$CORE" "$ADAPTER" | sort --unique)"

if [ -z "$named" ]; then
  assert_ok "neither the core nor the adapter reaches a config file through a symlink"
else
  assert_ko "neither the core nor the adapter reaches a config file through a symlink" "named: $(echo "$named" | tr '\n' ' ')"
fi

printf "\nTest group: the project rule answers for every role\n"

unmapped=""
for path in "${REPO_PATHS[@]}"; do
  grep --quiet --fixed-strings "$path" "$PROJECT_RULE" || unmapped="$unmapped $path"
done

if [ -z "$unmapped" ]; then
  assert_ok "every config file's repo path is in the key mappings"
else
  assert_ko "every config file's repo path is in the key mappings" "missing:$unmapped"
fi

unnamed=""
for role in "${ROLE_NAMES[@]}"; do
  grep --quiet --fixed-strings "$role" "$PROJECT_RULE" || unnamed="$unnamed|$role"
done

if [ -z "$unnamed" ]; then
  assert_ok "and the role the always-loaded rules call it by is what keys the line"
else
  assert_ko "and the role the always-loaded rules call it by is what keys the line" "unnamed:$unnamed"
fi

printf "\nTest group: an executed script keeps its symlink path\n"

if grep --quiet --fixed-strings '"$HOME/.claude-shared/cockpit-cache-query"' "$CORE"; then
  assert_ok "the pattern spares a script the allowlist matches by its literal command"
else
  assert_ko "the pattern spares a script the allowlist matches by its literal command" "the core no longer runs cockpit-cache-query through the symlink"
fi

printf "\n%d passed, %d failed\n" "$pass" "$fail"
[ "$fail" -eq 0 ]
