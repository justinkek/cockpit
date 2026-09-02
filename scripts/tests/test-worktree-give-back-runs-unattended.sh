#!/usr/bin/env bash

repo_root_through_symlink() {
  cd "$(dirname "$0")" && cd "$(pwd -P)/../.." && pwd
}

REPO="$(repo_root_through_symlink)"
SETTINGS="$REPO/agents/claude/settings/base.settings.json"
CLOSE_OUT="$REPO/agents/claude/templates/status-done-close-out.md"
GIVE_BACK="$REPO/marketplace/plugins/cockpit/scripts/worktree-give-back"

ALLOWED_FORMS=(
  'Bash($HOME/.cockpit/scripts/worktree-give-back:*)'
  'Bash("$HOME/.cockpit/scripts/worktree-give-back":*)'
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

assert_exits() {
  local label="$1" expected="$2" actual="$3"
  if [ "$actual" = "$expected" ]; then
    assert_ok "$label"
  else
    assert_ko "$label" "expected exit $expected, got $actual"
  fi
}

allow_list() { jq --raw-output '.permissions.allow[]' "$SETTINGS"; }
deny_list() { jq --raw-output '.permissions.deny[]' "$SETTINGS"; }

printf "Test group: the give-back is reached through the script, never the raw command\n"

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

if grep --quiet --fixed-strings "worktree-give-back" "$CLOSE_OUT"; then
  assert_ok "the close-out reaches for the script"
else
  assert_ko "the close-out reaches for the script" "no line names it in $CLOSE_OUT"
fi

sandbox="$(mktemp -d)"
trap 'rm -rf "$sandbox"' EXIT

export GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@example.com
export GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@example.com

upstream="$sandbox/upstream"
git init --quiet --initial-branch=main "$upstream"
printf 'first\n' > "$upstream/file.txt"
git -C "$upstream" add file.txt
git -C "$upstream" commit --quiet --message "first"

checkout="$sandbox/checkout"
git clone --quiet "$upstream" "$checkout" 2>/dev/null

make_worktree() {
  local branch="$1" path="$sandbox/$1"
  git -C "$checkout" worktree add --quiet --detach "$path" 2>/dev/null
  git -C "$path" switch --quiet --create "$branch" 2>/dev/null
  printf '%s' "$path"
}

reached="$(make_worktree reached-main)"
dirty="$(make_worktree has-uncommitted)"
printf 'uncommitted\n' > "$dirty/file.txt"
never="$(make_worktree never-merged)"
printf 'second\n' > "$never/file.txt"
git -C "$never" commit --quiet --all --message "second"
squashed="$(make_worktree squashed-onto-main)"
printf 'third\n' > "$squashed/file.txt"
git -C "$squashed" commit --quiet --all --message "third"

export SQUASHED_BRANCH=squashed-onto-main
SQUASHED_HEAD="$(git -C "$checkout" rev-parse squashed-onto-main)"
export SQUASHED_HEAD

mkdir -p "$sandbox/bin"
cat > "$sandbox/bin/gh" <<'STUB'
#!/usr/bin/env bash
case "$*" in
  *"$SQUASHED_BRANCH"*)
    case "$*" in
      *headRefOid*) printf '%s\n' "$SQUASHED_HEAD" ;;
      *state*) printf 'MERGED\n' ;;
      *) exit 1 ;;
    esac ;;
  *) exit 1 ;;
esac
STUB
chmod +x "$sandbox/bin/gh"
export PATH="$sandbox/bin:$PATH"

run_give_back() {
  (cd "$checkout" && bash "$GIVE_BACK" "$@" >/dev/null 2>&1; printf '%s' "$?")
}

printf "\nTest group: the script refuses every give-back that would lose work\n"

assert_exits "the main checkout is not a worktree to give back" 3 \
  "$(run_give_back "$checkout" reached-main)"
assert_exits "a path this repository does not know as a worktree" 3 \
  "$(run_give_back "$sandbox/upstream" reached-main)"
assert_exits "a worktree with uncommitted changes" 4 \
  "$(run_give_back "$dirty" has-uncommitted)"
assert_exits "the default branch" 5 \
  "$(run_give_back "$reached" main)"
assert_exits "a branch checked out in another worktree" 5 \
  "$(run_give_back "$reached" never-merged)"
assert_exits "a branch whose work never reached main" 6 \
  "$(run_give_back "$never" never-merged)"
assert_exits "a call naming no branch" 2 "$(run_give_back "$reached")"

printf "\nTest group: a give-back whose work reached main goes through\n"

assert_exits "a branch that is an ancestor of origin/main" 0 \
  "$(run_give_back "$reached" reached-main)"
assert_exits "a branch whose merged pull request still matches its local tip" 0 \
  "$(run_give_back "$squashed" squashed-onto-main)"

if [ -d "$reached" ]; then
  assert_ko "the worktree is gone" "$reached is still on disk"
else
  assert_ok "the worktree is gone"
fi

if git -C "$checkout" show-ref --quiet --verify refs/heads/reached-main; then
  assert_ko "the branch is gone" "refs/heads/reached-main is still there"
else
  assert_ok "the branch is gone"
fi

printf "\n%d passed, %d failed\n" "$pass" "$fail"
[ "$fail" -eq 0 ]
