#!/usr/bin/env bash

export CLAUDE_SHARED_DIR="$(cd "$(dirname "$0")/../../../../../../agents/claude" && pwd)"

HOOK_SRC="$(cd "$(dirname "$0")/.." && pwd)/session-end-release-claims.sh"
BOARD_CARD="$(cd "$(dirname "$0")/../.." && pwd)/board-card"
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

ROOT="$TMPDIR/agents"
BIN="$TMPDIR/bin"
mkdir -p "$ROOT/hooks" "$BIN"
cp "$HOOK_SRC" "$ROOT/hooks/"

SESSION="test-session-end-$$"

ln -s "$BOARD_CARD" "$ROOT/board-card"
export COCKPIT_BOARD_DIR="$TMPDIR/board"
"$ROOT/board-card" init >/dev/null
for name in mine "mine, mid-dev" theirs unclaimed; do
  "$ROOT/board-card" create --name "$name" >/dev/null
done
cat > "$ROOT/ticket-claim-lock" <<STUB
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$TMPDIR/locks"
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

chmod +x "$ROOT/ticket-claim-lock" "$BIN/ps" "$BIN/pgrep"

CLAUDE_SESSION_ID="$SESSION" "$ROOT/board-card" claim FEAT-1 >/dev/null
CLAUDE_SESSION_ID="$SESSION" "$ROOT/board-card" claim FEAT-2 >/dev/null
CLAUDE_SESSION_ID=someone-else "$ROOT/board-card" claim FEAT-3 >/dev/null
: > "$TMPDIR/locks"

holder_of() { "$ROOT/board-card" show "$1" "Agent: Session Id" | cut -f2; }

printf '{"session_id":"%s","reason":"prompt_input_exit"}' "$SESSION" \
  | PATH="$BIN:$PATH" bash "$ROOT/hooks/session-end-release-claims.sh"
status=$?

printf "Test group: the claims this session holds are released\n"

assert_eq "exits zero" "0" "$status"
assert_contains "releases the local locks" "release-all" "$(cat "$TMPDIR/locks")"
assert_eq "clears the card it claimed" "" "$(holder_of FEAT-1)"
assert_eq "clears the card it was holding mid-dev" "" "$(holder_of FEAT-2)"

printf "\nTest group: nothing else is touched\n"

assert_eq "leaves another session's claim alone" "someone-else" "$(holder_of FEAT-3)"
assert_eq "leaves an unclaimed card unclaimed" "" "$(holder_of FEAT-4)"

printf "\nTest group: no board is a quiet no-op, not a failure\n"

printf '{"session_id":"%s","reason":"other"}' "$SESSION" \
  | COCKPIT_BOARD_DIR="$TMPDIR/no-board" PATH="$BIN:$PATH" bash "$ROOT/hooks/session-end-release-claims.sh"
assert_eq "exits zero without a board" "0" "$?"

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
