#!/usr/bin/env bash

HOOK_SRC="$(cd "$(dirname "$0")/.." && pwd)/session-end-release-claims.sh"
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

pass=0
fail=0

assert_eq() {
  local label="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then
    printf "  OK  %s\n" "$label"
    pass=$((pass + 1))
  else
    printf "  KO  %s — expected '%s', got '%s'\n" "$label" "$expected" "$actual"
    fail=$((fail + 1))
  fi
}

assert_contains() {
  local label="$1" expected="$2" output="$3"
  if printf '%s' "$output" | grep -qF -- "$expected"; then
    printf "  OK  %s\n" "$label"
    pass=$((pass + 1))
  else
    printf "  KO  %s — expected '%s' in output '%s'\n" "$label" "$expected" "$output"
    fail=$((fail + 1))
  fi
}

assert_absent() {
  local label="$1" needle="$2" output="$3"
  if printf '%s' "$output" | grep -qF -- "$needle"; then
    printf "  KO  %s — '%s' should not appear in output '%s'\n" "$label" "$needle" "$output"
    fail=$((fail + 1))
  else
    printf "  OK  %s\n" "$label"
    pass=$((pass + 1))
  fi
}

ROOT="$TMPDIR/agents"
BIN="$TMPDIR/bin"
mkdir -p "$ROOT/hooks" "$BIN"
cp "$HOOK_SRC" "$ROOT/hooks/"

SESSION="test-session-end-$$"

# Field order is the contract under test: board, page id, status, claim, name,
# liveness. The In Dev row is the case the column listing could not answer: a
# claim runs from pickup to Done, so a session ending mid-dev is holding a card
# no by-AI column contains.
cat > "$ROOT/ticket-waiting-cards" <<STUB
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$TMPDIR/waiting-args"
# %b, not %s: the tabs are the field separators the hook parses on.
printf '%b\n' \\
  "Cockpit\tpage-mine\tReady for BR by AI\t$SESSION @ 2026-08-06T13:00:00Z\tmine\tlive" \\
  "ProjectBoard\tpage-cross\tReady for TR by AI\t$SESSION @ 2026-08-06T13:00:00Z\tmine too\tlive" \\
  "Cockpit\tpage-dev\tIn Dev\t$SESSION @ 2026-08-06T13:00:00Z\tmine, mid-dev\tlive" \\
  "Cockpit\tpage-theirs\tReady for BR by AI\tsomeone-else @ 2026-08-06T13:00:00Z\ttheirs\tlive" \\
  "Cockpit\tpage-free\tReady for BR by AI\t-\tunclaimed\t-"
STUB

cat > "$ROOT/ticket-claim-lock" <<STUB
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$TMPDIR/locks"
STUB

cat > "$BIN/security" <<'STUB'
#!/usr/bin/env bash
printf 'stub-token\n'
STUB

# Record the request rather than making one. The url line names the page.
cat > "$BIN/curl" <<STUB
#!/usr/bin/env bash
cat >> "$TMPDIR/requests"
STUB

CLAUDE_RUNNING_THE_HOOK=9001
CLAUDE_RUNNING_ANOTHER_SESSION=9002

: > "$TMPDIR/ps-table"
: > "$TMPDIR/watcher-pids"

cat > "$BIN/ps" <<STUB
#!/usr/bin/env bash
field="\$2"
pid="\$4"
while read -r row_pid row_comm row_ppid; do
  [ "\$row_pid" = "\$pid" ] || continue
  case "\$field" in
    comm=) printf '%s\n' "\$row_comm" ;;
    ppid=) printf '%s\n' "\$row_ppid" ;;
  esac
  exit 0
done < "$TMPDIR/ps-table"
case "\$field" in
  comm=) printf 'bash\n' ;;
  ppid=) printf '%s\n' "$CLAUDE_RUNNING_THE_HOOK" ;;
esac
STUB

cat > "$BIN/pgrep" <<STUB
#!/usr/bin/env bash
cat "$TMPDIR/watcher-pids"
STUB

chmod +x "$ROOT/ticket-waiting-cards" "$ROOT/ticket-claim-lock" "$BIN/security" "$BIN/curl" \
  "$BIN/ps" "$BIN/pgrep"

: > "$TMPDIR/requests"
: > "$TMPDIR/locks"
: > "$TMPDIR/waiting-args"

printf '{"session_id":"%s","reason":"prompt_input_exit"}' "$SESSION" \
  | PATH="$BIN:$PATH" bash "$ROOT/hooks/session-end-release-claims.sh"
status=$?

requests="$(cat "$TMPDIR/requests")"

printf "Test group: the claims this session holds are released\n"

assert_eq "exits zero" "0" "$status"
assert_contains "releases the local locks first" "release-all" "$(cat "$TMPDIR/locks")"
assert_contains "asks for this session's cards, not for the waiting ones" \
  "--claimed-by $SESSION" "$(cat "$TMPDIR/waiting-args")"
assert_contains "patches the cockpit card it claimed" "/v1/pages/page-mine" "$requests"
assert_contains "patches the card it claimed on another board" "/v1/pages/page-cross" "$requests"
assert_contains "patches the card it was holding mid-dev" "/v1/pages/page-dev" "$requests"
assert_eq "three pages patched, no more" "3" \
  "$(printf '%s' "$requests" | grep -c 'v1/pages/' | tr -d ' ')"

printf "\nTest group: nothing else is touched\n"

assert_absent "leaves another session's claim alone" "page-theirs" "$requests"
assert_absent "leaves an unclaimed card alone" "page-free" "$requests"

printf "\nTest group: the fields read are the fields meant\n"

assert_absent "never mistakes the board name for a page id" "/v1/pages/Cockpit" "$requests"
assert_absent "never mistakes the status for a claim" "/v1/pages/Ready" "$requests"
assert_absent "never mistakes the liveness verdict for a claim" "/v1/pages/live" "$requests"
assert_contains "sends a property update, not a read" 'request = "PATCH"' "$requests"

printf "\nTest group: a missing credential is a quiet no-op, not a failure\n"

: > "$TMPDIR/requests"
cat > "$BIN/security" <<'STUB'
#!/usr/bin/env bash
exit 1
STUB
chmod +x "$BIN/security"

printf '{"session_id":"%s","reason":"other"}' "$SESSION" \
  | PATH="$BIN:$PATH" bash "$ROOT/hooks/session-end-release-claims.sh"
assert_eq "exits zero without a token" "0" "$?"
assert_eq "patches nothing" "0" \
  "$(grep -c 'v1/pages/' "$TMPDIR/requests" | tr -d ' ')"

printf "\nTest group: the watchers this session armed are stopped\n"

bash -c 'trap "exit 0" TERM; sleep 5 & wait' &
watcher_mine=$!
bash -c 'trap "exit 0" TERM; sleep 5 & wait' &
watcher_theirs=$!

printf '%s sleep %s\n%s sleep %s\n%s claude 1\n%s claude 1\n' \
  "$watcher_mine" "$CLAUDE_RUNNING_THE_HOOK" \
  "$watcher_theirs" "$CLAUDE_RUNNING_ANOTHER_SESSION" \
  "$CLAUDE_RUNNING_THE_HOOK" \
  "$CLAUDE_RUNNING_ANOTHER_SESSION" > "$TMPDIR/ps-table"
printf '%s\n%s\n' "$watcher_mine" "$watcher_theirs" > "$TMPDIR/watcher-pids"

printf '{"session_id":"%s","reason":"prompt_input_exit"}' "$SESSION" \
  | PATH="$BIN:$PATH" bash "$ROOT/hooks/session-end-release-claims.sh"

wait "$watcher_mine" 2>/dev/null

assert_eq "kills the watcher this session armed" "1" \
  "$(kill -0 "$watcher_mine" 2>/dev/null; echo $?)"
assert_eq "leaves another session's watcher running" "0" \
  "$(kill -0 "$watcher_theirs" 2>/dev/null; echo $?)"

kill "$watcher_theirs" 2>/dev/null

printf "\n%d passed, %d failed\n" "$pass" "$fail"
[ "$fail" -eq 0 ]
