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
PROBE_HOME="$TMPDIR/probe-home"
SETTINGS="$PROBE_HOME/.claude-first/settings.json"

mkdir -p "$SHARED/settings/overrides" "$PROBE_HOME" "$TMPDIR/agents-shared"
cp "$REPO/agents/claude/sync.sh" "$SHARED/sync.sh"
cp "$REPO/agents/claude/settings/sync.settings.sh" "$SHARED/settings/sync.settings.sh"
cp "$REPO/agents/shared/prompts.sh" "$TMPDIR/agents-shared/prompts.sh"

cp "$REPO/agents/claude/board-accounts.sh" "$SHARED/board-accounts.sh"
cat > "$SHARED/accounts.sh" <<'ACCOUNTS'
ACCOUNTS=(first second)
acct_dir() { printf '%s' "$HOME/.claude-$1"; }
ACCOUNTS

cat > "$SHARED/settings/base.settings.json" <<'BASE'
{
	"permissions": {
		"allow": ["Bash(git status:*)"]
	}
}
BASE

CLAUDE_SHARED_DIR="$SHARED" \
AGENTS_SHARED_DIR="$TMPDIR/agents-shared" \
HOME="$PROBE_HOME" \
	bash "$SHARED/sync.sh" settings --apply > "$TMPDIR/apply.out" 2>&1 < /dev/null
status=$?

written="$(cat "$SETTINGS" 2>/dev/null)"

assert_holds() {
	local label="$1" entry="$2"
	if printf '%s' "$written" | jq --exit-status --arg entry "$entry" \
		'.permissions.allow | index($entry) != null' >/dev/null 2>&1; then
		printf "  OK  %s\n" "$label"
		pass=$((pass + 1))
	else
		printf "  KO  %s — the allow list holds no '%s', written: %s\n" "$label" "$entry" "$written"
		fail=$((fail + 1))
	fi
}

printf "Test group: every account in the list is readable without naming one in a tracked file\n"

assert_holds "the first account is allowed, tilde form" 'Read(~/.claude-first/**)'
assert_holds "and its variable form" 'Read($HOME/.claude-first/**)'
assert_holds "and its spelled-out form" "Read($PROBE_HOME/.claude-first/**)"
assert_holds "the second account is allowed too" 'Read(~/.claude-second/**)'
assert_holds "and spelled out" "Read($PROBE_HOME/.claude-second/**)"

printf "\nTest group: the committed entries are untouched\n"

assert_holds "a committed entry survives the derivation" 'Bash(git status:*)'

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
