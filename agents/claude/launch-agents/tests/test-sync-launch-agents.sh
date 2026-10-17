#!/usr/bin/env bash

CONCERN_DIR="$(cd "$(dirname "$0")/.." && pwd)"
WORKER="$CONCERN_DIR/sync.launch-agents.sh"
REPO="$(cd "$CONCERN_DIR/../../.." && pwd)"
if [ "$(uname -s)" != Darwin ]; then
  printf "  OK  launchd is macOS only, so there is nothing to test here\n"
  exit 0
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

pass=0
fail=0

assert_contains() {
  local label="$1" needle="$2" haystack="$3"
  case "$haystack" in
    *"$needle"*)
      printf "  OK  %s\n" "$label"
      pass=$((pass + 1))
      ;;
    *)
      printf "  KO  %s — expected to find '%s' in '%s'\n" "$label" "$needle" "$haystack"
      fail=$((fail + 1))
      ;;
  esac
}

assert_absent() {
  local label="$1" needle="$2" haystack="$3"
  case "$haystack" in
    *"$needle"*)
      printf "  KO  %s — expected not to find '%s' in '%s'\n" "$label" "$needle" "$haystack"
      fail=$((fail + 1))
      ;;
    *)
      printf "  OK  %s\n" "$label"
      pass=$((pass + 1))
      ;;
  esac
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

LABEL="com.cockpit.board-maintenance"
PLIST="$WORK/home/Library/LaunchAgents/$LABEL.plist"
DOMAIN="gui/$(id -u)"
export CALLS_FILE="$WORK/calls"
export LOADED_FILE="$WORK/loaded"

build_fixture() {
  local accounts="$1"
  rm -rf "$WORK/home" "$WORK/shared" "$CALLS_FILE" "$LOADED_FILE"
  mkdir -p "$WORK/home" "$WORK/shared"
  cp "$REPO/agents/claude/board-accounts.sh" "$WORK/shared/board-accounts.sh"
  cat > "$WORK/shared/accounts.sh" <<ACCOUNTS
ACCOUNTS=($accounts)
acct_dir() { printf '%s' "\$HOME/.claude-\$1"; }
ACCOUNTS
  : > "$CALLS_FILE"

  cat > "$WORK/stub-launchctl" <<'STUB'
#!/usr/bin/env bash
case "$1" in
  print) [ -f "$LOADED_FILE" ] ;;
  bootstrap) printf '%s\n' "$*" >> "$CALLS_FILE"; : > "$LOADED_FILE" ;;
  bootout) printf '%s\n' "$*" >> "$CALLS_FILE"; rm -f "$LOADED_FILE" ;;
  *) printf '%s\n' "$*" >> "$CALLS_FILE" ;;
esac
STUB
  chmod +x "$WORK/stub-launchctl"
}

run_worker() {
  output="$(HOME="$WORK/home" \
    CLAUDE_SHARED_DIR="$WORK/shared" \
    LAUNCHCTL_BIN="$WORK/stub-launchctl" \
    BASH_ENV="$REPO/agents/shared/prompts.sh" \
    bash "$WORKER" "$@" 2>&1 < /dev/null)"
  status=$?
}

printf "Test group: check reports drift and writes nothing\n"

build_fixture "probe"
run_worker --check
assert_equal "check exits 1 when the job is not installed" "1" "$status"
assert_contains "check shows the plist it would write" "<string>$LABEL</string>" "$output"
assert_contains "check says the job is not loaded" "not loaded in $DOMAIN" "$output"
[ -e "$PLIST" ] && written=yes || written=no
assert_equal "check writes no plist" "no" "$written"
assert_equal "check calls neither bootstrap nor bootout" "" "$(cat "$CALLS_FILE")"

printf "\nTest group: apply writes the plist and loads it\n"

run_worker --apply --yes
assert_equal "apply exits 0" "0" "$status"
plist="$(cat "$PLIST" 2>/dev/null)"
assert_contains "the job runs board-card through the cockpit symlink" "<string>$WORK/home/.cockpit/scripts/board-card</string>" "$plist"
assert_contains "it asks for the maintenance sweep" "<string>maintenance</string>" "$plist"
assert_contains "and only the sweep" "<string>--close</string>" "$plist"
assert_contains "it runs on the 1st" "<key>Day</key>
		<integer>1</integer>" "$plist"
assert_contains "at five past the hour" "<key>Minute</key>
		<integer>5</integer>" "$plist"
assert_absent "every hour of the 1st, so a zone ahead of UTC still reaches the new month" "<key>Hour</key>" "$plist"
assert_contains "its output goes to the cockpit state directory" "<string>$WORK/home/.local/state/cockpit/board-maintenance.log</string>" "$plist"
assert_contains "it can find jq where Homebrew puts it" "/opt/homebrew/bin" "$plist"
if command -v plutil >/dev/null 2>&1; then
  plutil -lint "$PLIST" >/dev/null 2>&1 && lint=ok || lint=bad
  assert_equal "the plist parses" "ok" "$lint"
fi
[ -d "$WORK/home/.local/state/cockpit" ] && logdir=yes || logdir=no
assert_equal "apply makes the log's directory" "yes" "$logdir"
assert_equal "apply loads the job once and unloads nothing" "bootstrap $DOMAIN $PLIST" "$(cat "$CALLS_FILE")"

printf "\nTest group: a second run has nothing to do\n"

: > "$CALLS_FILE"
run_worker --check
assert_equal "check exits 0 once installed and loaded" "0" "$status"
run_worker --apply --yes
assert_equal "apply calls launchctl for nothing once in sync" "" "$(cat "$CALLS_FILE")"

printf "\nTest group: a changed plist is reloaded\n"

printf '<!-- edited -->\n' >> "$PLIST"
: > "$CALLS_FILE"
run_worker --apply --yes
assert_equal "the loaded job is booted out before the new one is bootstrapped" "bootout $DOMAIN/$LABEL
bootstrap $DOMAIN $PLIST" "$(cat "$CALLS_FILE")"
assert_absent "the plist is rewritten" "edited" "$(cat "$PLIST")"

printf "\nTest group: a written plist that is not loaded is loaded\n"

rm -f "$LOADED_FILE"
: > "$CALLS_FILE"
run_worker --apply --yes
assert_equal "only bootstrap runs" "bootstrap $DOMAIN $PLIST" "$(cat "$CALLS_FILE")"

printf "\nTest group: a machine with no board account gets no job\n"

build_fixture "claude"
run_worker --apply --yes
assert_equal "apply exits 0" "0" "$status"
[ -e "$PLIST" ] && written=yes || written=no
assert_equal "no plist is written" "no" "$written"
assert_equal "launchctl is not asked to load anything" "" "$(cat "$CALLS_FILE")"

printf "\n%d passed, %d failed\n" "$pass" "$fail"
[ "$fail" -eq 0 ]
