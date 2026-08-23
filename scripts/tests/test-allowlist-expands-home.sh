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
		"allow": [
			"Bash($HOME/probe-script:*)",
			"Bash(\"$HOME/probe-script\":*)",
			"Read($HOME/.probe/**)",
			"Bash(git status:*)"
		],
		"deny": [
			"Bash($HOME/.probe-secret:*)"
		]
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
	local label="$1" list="$2" entry="$3"
	if printf '%s' "$written" | jq --exit-status --arg entry "$entry" \
		"$list | index(\$entry) != null" >/dev/null 2>&1; then
		printf "  OK  %s\n" "$label"
		pass=$((pass + 1))
	else
		printf "  KO  %s — %s does not hold '%s', written: %s\n" "$label" "$list" "$entry" "$written"
		fail=$((fail + 1))
	fi
}

assert_counted_once() {
	local label="$1" entry="$2" count
	count="$(printf '%s' "$written" | jq --arg entry "$entry" \
		'[ .permissions.allow[] | select(. == $entry) ] | length')"
	if [ "$count" = "1" ]; then
		printf "  OK  %s\n" "$label"
		pass=$((pass + 1))
	else
		printf "  KO  %s — written %s times\n" "$label" "$count"
		fail=$((fail + 1))
	fi
}

printf "Test group: an entry naming a home directory is written both ways\n"

assert_holds "the committed form is kept" ".permissions.allow" 'Bash($HOME/probe-script:*)'
assert_holds "and the run's own home directory is spelled out beside it" \
	".permissions.allow" "Bash($PROBE_HOME/probe-script:*)"
assert_holds "the quoted form is kept" ".permissions.allow" 'Bash("$HOME/probe-script":*)'
assert_holds "and spelled out too" ".permissions.allow" "Bash(\"$PROBE_HOME/probe-script\":*)"
assert_holds "a Read pattern is spelled out" ".permissions.allow" "Read($PROBE_HOME/.probe/**)"
assert_holds "and the deny list is spelled out the same way" \
	".permissions.deny" "Bash($PROBE_HOME/.probe-secret:*)"

printf "\nTest group: an entry naming no home directory is left alone\n"

assert_counted_once "it is written once" 'Bash(git status:*)'

printf "\nTest group: the home directory of the machine running the test stays out of it\n"

if printf '%s' "$written" | grep --quiet --fixed-strings "$HOME/"; then
	printf "  KO  the machine's own home directory is not written — it is\n"
	fail=$((fail + 1))
else
	printf "  OK  the machine's own home directory is not written\n"
	pass=$((pass + 1))
fi

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
