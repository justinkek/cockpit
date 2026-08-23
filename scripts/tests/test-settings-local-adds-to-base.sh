#!/usr/bin/env bash

repo_root_through_symlink() {
	cd "$(dirname "$0")" && cd "$(pwd -P)/../.." && pwd
}

REPO="$(repo_root_through_symlink)"
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

pass=0
fail=0

SHARED="$TMPDIR/shared"
ACCOUNT_DIR="$TMPDIR/account"
PROBE_HOME="$TMPDIR/probe-home"
SETTINGS="$ACCOUNT_DIR/settings.json"

mkdir -p "$SHARED/settings/overrides" "$ACCOUNT_DIR" "$PROBE_HOME" "$TMPDIR/agents-shared"
cp "$REPO/agents/claude/sync.sh" "$SHARED/sync.sh"
cp "$REPO/agents/claude/settings/sync.settings.sh" "$SHARED/settings/sync.settings.sh"
cp "$REPO/agents/shared/prompts.sh" "$TMPDIR/agents-shared/prompts.sh"

cat > "$SHARED/accounts.sh" <<ACCOUNTS
ACCOUNTS=(probe)
acct_dir() { printf '%s' "$ACCOUNT_DIR"; }
ACCOUNTS

cat > "$SHARED/settings/base.settings.json" <<'BASE'
{
	"permissions": {
		"allow": ["Bash(git status:*)"],
		"deny": ["Bash(rm -rf /:*)"]
	},
	"env": { "COMMITTED": "1" }
}
BASE

cat > "$SHARED/settings/base.settings.local.json" <<'LOCAL'
{
	"permissions": {
		"allow": ["Read(/machine-only/**)"]
	},
	"env": { "MACHINE_ONLY": "1" }
}
LOCAL

CLAUDE_SHARED_DIR="$SHARED" \
AGENTS_SHARED_DIR="$TMPDIR/agents-shared" \
HOME="$PROBE_HOME" \
	bash "$SHARED/sync.sh" settings --apply > "$TMPDIR/apply.out" 2>&1 < /dev/null
status=$?

written="$(cat "$SETTINGS" 2>/dev/null)"

assert_holds() {
	local label="$1" filter="$2" entry="$3"
	if printf '%s' "$written" | jq --exit-status --arg entry "$entry" \
		"$filter | index(\$entry) != null" >/dev/null 2>&1; then
		printf "  OK  %s\n" "$label"
		pass=$((pass + 1))
	else
		printf "  KO  %s — %s does not hold '%s', written: %s\n" "$label" "$filter" "$entry" "$written"
		fail=$((fail + 1))
	fi
}

assert_equal() {
	local label="$1" expected="$2" actual="$3"
	if [ "$expected" = "$actual" ]; then
		printf "  OK  %s\n" "$label"
		pass=$((pass + 1))
	else
		printf "  KO  %s — expected '%s', got '%s'\n" "$label" "$expected" "$actual"
		fail=$((fail + 1))
	fi
}

printf "Test group: the local file adds to the committed allowlist rather than replacing it\n"

assert_holds "the committed entry survives" ".permissions.allow" 'Bash(git status:*)'
assert_holds "and the machine's own entry is written beside it" \
	".permissions.allow" 'Read(/machine-only/**)'
assert_holds "a deny list the local file never mentions is left alone" \
	".permissions.deny" 'Bash(rm -rf /:*)'

printf "\nTest group: every other key merges as before\n"

assert_equal "the committed env survives" "1" \
	"$(printf '%s' "$written" | jq --raw-output '.env.COMMITTED')"
assert_equal "and the machine's own env is merged in" "1" \
	"$(printf '%s' "$written" | jq --raw-output '.env.MACHINE_ONLY')"

printf "\nTest group: the run survives it\n"

assert_equal "the apply exits clean" "0" "$status"

printf "\n%d passed, %d failed\n" "$pass" "$fail"
[ "$fail" -eq 0 ]
