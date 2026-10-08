#!/usr/bin/env bash

repo_root_through_symlink() {
  cd "$(dirname "$0")" && cd "$(pwd -P)/../.." && pwd
}

REPO="$(repo_root_through_symlink)"
SETTINGS="$REPO/agents/claude/settings/base.settings.json"
CLOSE_OUT="$REPO/agents/claude/templates/status-done-close-out.md"

ALLOWED_FORMS=(
  'Bash(git worktrees-clean)'
  'Bash(git worktrees-clean:*)'
)

RAW_FORMS=(
  'Bash(git worktree remove:*)'
  'Bash(git * worktree remove:*)'
  'Bash(git branch --delete --force:*)'
  'Bash(git * branch --delete --force:*)'
)

pass=0
fail=0

assert_ok() {
  printf "  OK  %s\n" "$1"
  pass=$((pass + 1))
}

assert_ko() {
  printf "  KO  %s — %s\n" "$1" "$2"
  fail=$((fail + 1))
}

allow_list() { jq --raw-output '.permissions.allow[]' "$SETTINGS"; }
deny_list() { jq --raw-output '.permissions.deny[]' "$SETTINGS"; }

printf "Test group: a worktree is ended through git worktrees-clean, never the raw command\n"

for form in "${ALLOWED_FORMS[@]}"; do
  if allow_list | grep --quiet --line-regexp --fixed-strings "$form"; then
    assert_ok "$form is allowed"
  else
    assert_ko "$form is allowed" "no such entry under permissions.allow"
  fi
done

for form in "${RAW_FORMS[@]}"; do
  if deny_list | grep --quiet --line-regexp --fixed-strings "$form"; then
    assert_ok "$form is denied"
  else
    assert_ko "$form is denied" "no such entry under permissions.deny"
  fi

  if allow_list | grep --quiet --line-regexp --fixed-strings "$form"; then
    assert_ko "$form is not also allowed" "the same entry sits under permissions.allow"
  else
    assert_ok "$form is not also allowed"
  fi
done

if grep --quiet --fixed-strings "git worktrees-clean <worktree-path>" "$CLOSE_OUT"; then
  assert_ok "the close-out reaches for git worktrees-clean"
else
  assert_ko "the close-out reaches for git worktrees-clean" "no line names it in $CLOSE_OUT"
fi

printf "\n%d passed, %d failed\n" "$pass" "$fail"
[ "$fail" -eq 0 ]
