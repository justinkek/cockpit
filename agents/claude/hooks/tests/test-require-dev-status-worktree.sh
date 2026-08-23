#!/usr/bin/env bash

here="$(cd "$(dirname "$0")" && pwd -P)"
HOOK="$here/../require-dev-status.sh"

[ -x "$HOOK" ] || { printf "KO  hook not found at %s\n" "$HOOK"; exit 1; }

pass=0
fail=0

assert_contains() {
  local label="$1" want="$2" out="$3"
  case "$out" in
    *"$want"*) printf "  OK  %s\n" "$label"; pass=$((pass + 1)) ;;
    *) printf "  KO  %s — expected '%s' in the verdict, got '%s'\n" "$label" "$want" "$out"
       fail=$((fail + 1)) ;;
  esac
}

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

sandbox="$(mktemp -d)"
trap 'rm -rf "$sandbox"' EXIT

export HOME="$sandbox/home"
state_directory="$HOME/.local/state/claude-ticket-sessions"
mkdir -p "$state_directory"

session="test-session"
printf 'https://example.invalid/ticket\n' > "$state_directory/$session.ticket"

main_checkout="$sandbox/repo"
git init --quiet --initial-branch main "$main_checkout"
: > "$main_checkout/seed"
git -C "$main_checkout" add seed
GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@example.invalid \
GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@example.invalid \
  git -C "$main_checkout" commit --quiet --message seed

linked_worktree="$main_checkout/.claude/worktrees/feat/some-ticket"
git -C "$main_checkout" worktree add --quiet --detach "$linked_worktree"

verdict() {
  local tool="$1" directory="$2" edited="${3-$2/edited.txt}"
  printf '{"tool_name":"%s","session_id":"%s","cwd":"%s","tool_input":{"file_path":"%s"}}' \
    "$tool" "$session" "$directory" "$edited" \
    | "$HOOK"
}

printf "Test group: the main checkout is refused whatever the ticket status\n"

assert_contains "edit from the main checkout, no stage marker" "Worktree gate" \
  "$(verdict Edit "$main_checkout")"

: > "$state_directory/$session.stage-dev"

assert_contains "edit from the main checkout, stage marker written" "Worktree gate" \
  "$(verdict Edit "$main_checkout")"
assert_contains "write from the main checkout" "Worktree gate" \
  "$(verdict Write "$main_checkout")"

mkdir -p "$main_checkout/deep/nested"
assert_contains "edit from a subdirectory of the main checkout" "Worktree gate" \
  "$(verdict Edit "$main_checkout/deep/nested")"

assert_contains "write creating a directory that does not exist yet" "Worktree gate" \
  "$(verdict Write "$main_checkout" "$main_checkout/absent/deeper/new.txt")"

assert_contains "edit of a path relative to the main checkout" "Worktree gate" \
  "$(verdict Edit "$main_checkout" "deep/nested/edited.txt")"
assert_contains "edit carrying no path at all" "Worktree gate" \
  "$(verdict Edit "$main_checkout" "")"

printf "\nTest group: a linked worktree passes once dev has started\n"

assert_silent "edit from a linked worktree" "$(verdict Edit "$linked_worktree")"

mkdir -p "$linked_worktree/deep/nested"
assert_silent "edit from a subdirectory of a linked worktree" \
  "$(verdict Edit "$linked_worktree/deep/nested")"

rm -f "$state_directory/$session.stage-dev"

assert_contains "edit from a linked worktree before dev" "Ticket status gate" \
  "$(verdict Edit "$linked_worktree")"

printf "\nTest group: a session outside any repo is not the worktree gate's business\n"

: > "$state_directory/$session.stage-dev"

assert_silent "edit from a directory with no repo" "$(verdict Edit "$sandbox")"

printf "\nTest group: a file no checkout owns is judged by its own path\n"

scratchpad="$sandbox/scratchpad"
mkdir -p "$scratchpad"
ticket_marker="$state_directory/$session.ticket"

assert_silent "write to the scratchpad from the main checkout" \
  "$(verdict Write "$main_checkout" "$scratchpad/notes.md")"
assert_silent "write to the ticket session state from the main checkout" \
  "$(verdict Write "$main_checkout" "$ticket_marker")"

rm -f "$state_directory/$session.stage-dev"

assert_contains "write to the scratchpad before dev" "Ticket status gate" \
  "$(verdict Write "$main_checkout" "$scratchpad/notes.md")"
assert_contains "write to the ticket session state before dev" "Ticket status gate" \
  "$(verdict Write "$main_checkout" "$ticket_marker")"

: > "$state_directory/$session.stage-dev"

printf "\nTest group: tools other than Edit and Write are never gated here\n"

assert_silent "bash from the main checkout" "$(verdict Bash "$main_checkout")"

printf "\n%d passed, %d failed\n" "$pass" "$fail"
[ "$fail" -eq 0 ]
