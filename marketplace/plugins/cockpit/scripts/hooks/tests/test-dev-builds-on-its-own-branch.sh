#!/usr/bin/env bash

DEV_SKILL="$(cd "$(dirname "$0")/../../../skills/ticket:3:dev" && pwd)/SKILL.md"
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

squash() {
  awk '{ $1 = $1; printf "%s ", $0 }' "$DEV_SKILL"
}

holds() {
  if squash | grep --quiet --fixed-strings -- "$1"; then
    printf 'yes'
  else
    printf 'no'
  fi
}

first_line_holding() {
  grep --line-number --fixed-strings -- "$1" "$DEV_SKILL" | head -1 | cut -d: -f1
}

printf "Test group: a session in a worktree reads its branch before it calls or renames anything\n"

branch_read="$(first_line_holding 'git branch --show-current')"
worktree_call="$(first_line_holding 'call `EnterWorktree`')"
rename="$(first_line_holding 'git branch --move')"

assert_eq "the skill reads the branch" "yes" "$([ -n "$branch_read" ] && printf 'yes' || printf 'no')"
assert_eq "before the worktree call" "yes" "$([ -n "$worktree_call" ] && [ "$branch_read" -lt "$worktree_call" ] && printf 'yes' || printf 'no')"
assert_eq "and before the rename" "yes" "$([ -n "$rename" ] && [ "$branch_read" -lt "$rename" ] && printf 'yes' || printf 'no')"
assert_eq "a branch that is not the ticket's own stops the session" "yes" "$(holds 'On any other branch, say which one it is and stop')"
assert_eq "and is never renamed into looking like it" "yes" "$(holds "Never rename a worktree's branch to make it read as this ticket's own")"

printf "\nTest group: the branch is checked for work that is not the ticket's\n"

assert_eq "it lists what the branch carries beyond the remote" "yes" "$(holds 'git log origin/<default-branch>..HEAD --oneline')"
assert_eq "it no longer says every new branch lists nothing" "no" "$(holds 'A branch just cut lists nothing')"
assert_eq "it says a branch cut off the local HEAD lists what that HEAD held" "yes" "$(holds 'one cut off the local HEAD lists whatever that HEAD held beyond the remote')"

printf "\nTest group: the files the tech steps edit or remove are looked for on the branch itself\n"

assert_eq "both markers are checked" "yes" "$(holds 'marks `!` or `-`')"
assert_eq "against HEAD" "yes" "$(holds 'git cat-file -e HEAD:<path>')"
assert_eq "and not against a remote reference" "no" "$(holds 'git cat-file -e origin/')"

printf "\nTest group: only HEAD sees a file a branch cut off a stale local default branch lacks\n"

upstream="$TMPDIR/upstream"
checkout="$TMPDIR/checkout"
worktree="$TMPDIR/worktree"

quiet_git() {
  git -c user.name=test -c user.email=test@example.com -c init.defaultBranch=main -c core.hooksPath=/dev/null "$@" >/dev/null 2>&1
}

quiet_git init "$upstream"
printf 'one\n' > "$upstream/kept.txt"
quiet_git -C "$upstream" add kept.txt
quiet_git -C "$upstream" commit --message 'first'
quiet_git clone "$upstream" "$checkout"

printf 'two\n' > "$upstream/added-later.txt"
quiet_git -C "$upstream" add added-later.txt
quiet_git -C "$upstream" commit --message 'second'
quiet_git -C "$checkout" fetch origin

quiet_git -C "$checkout" branch feat/ticket main
quiet_git -C "$checkout" worktree add "$worktree" feat/ticket

on_branch="$(git -C "$worktree" cat-file -e HEAD:kept.txt 2>/dev/null && printf 'found' || printf 'missing')"
on_remote="$(git -C "$worktree" cat-file -e origin/main:added-later.txt 2>/dev/null && printf 'found' || printf 'missing')"
on_head="$(git -C "$worktree" cat-file -e HEAD:added-later.txt 2>/dev/null && printf 'found' || printf 'missing')"
carried="$(git -C "$worktree" log origin/main..HEAD --oneline)"

assert_eq "the branch holds the file it was cut with" "found" "$on_branch"
assert_eq "the remote reference holds the file the steps edit" "found" "$on_remote"
assert_eq "the branch cut off the stale local main does not" "missing" "$on_head"
assert_eq "and the check for carried work lists nothing to stop it" "" "$carried"

printf "\n%d passed, %d failed\n" "$pass" "$fail"
[ "$fail" -eq 0 ]
