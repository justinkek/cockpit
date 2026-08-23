#!/usr/bin/env bash

HOOK="$(cd "$(dirname "$0")/.." && pwd)/auto-sync-config.sh"
TEMPORARY_DIRECTORY="$(cd "$(mktemp -d)" && pwd -P)"
trap 'rm -rf "$TEMPORARY_DIRECTORY"' EXIT

passed=0
failed=0

assert_equal() {
  local label="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then
    printf "  OK  %s\n" "$label"
    passed=$((passed + 1))
  else
    printf "  KO  %s — expected '%s', got '%s'\n" "$label" "$expected" "$actual"
    failed=$((failed + 1))
  fi
}

checkout="$TEMPORARY_DIRECTORY/cockpit"
shared="$checkout/agents/claude"
elsewhere="$TEMPORARY_DIRECTORY/dotfiles/agents/claude/settings"
mkdir -p "$shared/settings" "$checkout/agents/shared" "$elsewhere"

printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$1" >> "%s/synced"\n' "$TEMPORARY_DIRECTORY" > "$shared/sync.sh"
chmod +x "$shared/sync.sh"

: > "$shared/settings/base.settings.json"
: > "$checkout/agents/shared/base.AGENTS.md"
: > "$elsewhere/base.settings.json"

run_hook() {
  printf '{"tool_input":{"file_path":"%s"}}' "$1" | CLAUDE_SHARED_DIR="$shared" bash "$HOOK" >/dev/null 2>&1
}

times_synced() {
  if [ -f "$TEMPORARY_DIRECTORY/synced" ]; then
    grep --count "" "$TEMPORARY_DIRECTORY/synced"
  else
    printf '0'
  fi
}

printf "Test group: the checkout is read from the shared symlink\n"

run_hook "$shared/settings/base.settings.json"
assert_equal "a settings edit in the resolved checkout syncs" "1" "$(times_synced)"

run_hook "$checkout/agents/shared/base.AGENTS.md"
assert_equal "a shared rules edit in the resolved checkout syncs" "2" "$(times_synced)"

run_hook "$elsewhere/base.settings.json"
assert_equal "a settings edit in another checkout does not sync" "2" "$(times_synced)"

printf "\n%d passed, %d failed\n" "$passed" "$failed"
[ "$failed" -eq 0 ]
