#!/usr/bin/env bash

REPO="$(cd "$(dirname "$0")" && cd "$(pwd -P)/../.." && pwd)"
SYNC="$REPO/agents/claude/plugins/sync.plugins.sh"
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

pass=0
fail=0

ACCOUNT_DIR="$TMPDIR/account"
CLAUDE_LOG="$TMPDIR/claude-invocations.log"
MANIFEST="$TMPDIR/base.plugins.json"

mkdir -p "$ACCOUNT_DIR/plugins" "$ACCOUNT_DIR/cache/notion" "$TMPDIR/shared" "$TMPDIR/bin"
: > "$CLAUDE_LOG"
printf 'plugin payload\n' > "$ACCOUNT_DIR/cache/notion/plugin.json"

cp "$REPO/agents/claude/board-accounts.sh" "$TMPDIR/shared/board-accounts.sh"
cat > "$TMPDIR/shared/accounts.sh" <<SHARED
ACCOUNTS=(probe)
acct_dir() { printf '%s' "$ACCOUNT_DIR"; }
SHARED

cat > "$TMPDIR/bin/claude" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$CLAUDE_LOG"
exit 0
STUB
chmod +x "$TMPDIR/bin/claude"

cat > "$MANIFEST" <<MANIFEST_JSON
{
  "marketplaces": { "official": "anthropics/claude-plugins-official" },
  "plugins": { "notion@official": "user" }
}
MANIFEST_JSON

cat > "$ACCOUNT_DIR/plugins/known_marketplaces.json" <<KNOWN
{ "official": { "installLocation": "$ACCOUNT_DIR/marketplaces/official" } }
KNOWN

cat > "$ACCOUNT_DIR/plugins/installed_plugins.json" <<INSTALLED
{
  "plugins": {
    "notion@official": [
      { "scope": "user", "version": "1.0.0", "installPath": "$ACCOUNT_DIR/cache/notion" }
    ],
    "warp@retired": [
      { "scope": "user", "version": "2.0.0", "installPath": "$ACCOUNT_DIR/cache/warp", "projectPath": "$TMPDIR" }
    ]
  }
}
INSTALLED

CLAUDE_LOG="$CLAUDE_LOG" \
CLAUDE_SHARED_DIR="$TMPDIR/shared" \
CLAUDE_BIN="$TMPDIR/bin/claude" \
CLAUDE_PLUGINS_MANIFEST="$MANIFEST" \
  bash "$SYNC" --apply > "$TMPDIR/apply.out" 2>&1 < /dev/null
status=$?
invocations="$(cat "$CLAUDE_LOG")"

assert_logged() {
  local label="$1" pattern="$2"
  if printf '%s' "$invocations" | grep --quiet -- "$pattern"; then
    printf "  OK  %s\n" "$label"
    pass=$((pass + 1))
  else
    printf "  KO  %s — no invocation matched '%s', log: %s\n" "$label" "$pattern" "$invocations"
    fail=$((fail + 1))
  fi
}

assert_not_logged() {
  local label="$1" pattern="$2"
  if printf '%s' "$invocations" | grep --quiet -- "$pattern"; then
    printf "  KO  %s — an invocation matched '%s', log: %s\n" "$label" "$pattern" "$invocations"
    fail=$((fail + 1))
  else
    printf "  OK  %s\n" "$label"
    pass=$((pass + 1))
  fi
}

printf "Test group: an install the manifest dropped comes off the account\n"

assert_logged "the undeclared plugin is uninstalled" "plugin uninstall warp@retired --scope user --yes"
assert_not_logged "the declared plugin is not" "uninstall notion@official"

printf "\nTest group: the apply still never cascades\n"

assert_not_logged "no marketplace is removed" "marketplace remove"

printf "\nTest group: the run survives it\n"

if [ "$status" -eq 0 ]; then
  printf "  OK  the apply exits clean\n"
  pass=$((pass + 1))
else
  printf "  KO  the apply exited %s, output: %s\n" "$status" "$(cat "$TMPDIR/apply.out")"
  fail=$((fail + 1))
fi

printf "\n%d passed, %d failed\n" "$pass" "$fail"
[ "$fail" -eq 0 ]
