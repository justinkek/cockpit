#!/usr/bin/env bash

here="$(cd "$(dirname "$0")" && pwd -P)"
POLICY="$here/../../../shared/hooks/confine-to-repo-policy.sh"
REPO="$(cd "$here/../../.." && pwd -P)"

[ -x "$POLICY" ] || { printf "KO  policy not found at %s\n" "$POLICY"; exit 1; }
git -C "$REPO" rev-parse --show-toplevel >/dev/null 2>&1 \
  || { printf "KO  %s is not a git worktree\n" "$REPO"; exit 1; }

pass=0
fail=0

assert_silent() {
  local label="$1" out="$2"
  if [ -z "$out" ]; then
    printf "  OK  %s\n" "$label"
    pass=$((pass + 1))
  else
    printf "  KO  %s — expected silence, got '%s'\n" "$label" "$out"
    fail=$((fail + 1))
  fi
}

assert_starts() {
  local label="$1" want="$2" out="$3"
  case "$out" in
    "$want"*) printf "  OK  %s\n" "$label"; pass=$((pass + 1)) ;;
    *) printf "  KO  %s — expected '%s …', got '%s'\n" "$label" "$want" "$out"
       fail=$((fail + 1)) ;;
  esac
}

session=/private/tmp/claude-501/-Users-someone-repo/1111-2222

printf "Test group: agent-owned directories outside the repo\n"

assert_silent "read a scratchpad file" \
  "$("$POLICY" read "$session/scratchpad/notes.txt" "$REPO" Read)"
assert_silent "write a scratchpad file" \
  "$("$POLICY" write "$session/scratchpad/notes.txt" "$REPO" Write)"
assert_silent "read a background task's output" \
  "$("$POLICY" read "$session/tasks/bo6jhz4kz.output" "$REPO" Read)"
assert_silent "read the tasks directory itself" \
  "$("$POLICY" read "$session/tasks" "$REPO" Read)"

printf "\nTest group: everything else outside the repo still gates\n"

assert_starts "read some other temp file" "ask" \
  "$("$POLICY" read "/private/tmp/claude-501/elsewhere/notes.txt" "$REPO" Read)"
assert_starts "write outside the worktree" "deny" \
  "$("$POLICY" write "$HOME/somewhere-else/file.txt" "$REPO" Write)"

printf "\nTest group: inside the repo is never the policy's business\n"

assert_silent "read a repo file" "$("$POLICY" read "$REPO/README.md" "$REPO" Read)"
assert_silent "write a repo file" "$("$POLICY" write "$REPO/README.md" "$REPO" Write)"

printf "\n%d passed, %d failed\n" "$pass" "$fail"
[ "$fail" -eq 0 ]
