#!/usr/bin/env bash

CLEAN="$(cd "$(dirname "$0")/../.." && pwd)/agents/claude/git-worktrees-clean"
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

pass=0
fail=0

mkdir -p "$TMPDIR/bin"
cat > "$TMPDIR/bin/gh" <<'STUB'
#!/usr/bin/env bash
[ "$3" = "${GH_STUB_MERGED_BRANCH:-}" ] || exit 1
case "$5" in
  state) printf 'MERGED\n' ;;
  headRefOid) printf '%s\n' "$GH_STUB_MERGED_SHA" ;;
  *) printf 'MERGED %s\n' "$GH_STUB_MERGED_SHA" ;;
esac
STUB
chmod +x "$TMPDIR/bin/gh"
export PATH="$TMPDIR/bin:$PATH"

export HOME="$TMPDIR/home"
mkdir -p "$HOME/.claude-shared" "$HOME/.cockpit/scripts"
cp "$(cd "$(dirname "$0")/../.." && pwd)/marketplace/plugins/cockpit/scripts/worktree-give-back" \
  "$HOME/.cockpit/scripts/worktree-give-back"
chmod +x "$HOME/.cockpit/scripts/worktree-give-back"

export GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@example.com
export GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@example.com
export GIT_CONFIG_GLOBAL="$TMPDIR/gitconfig"
export GIT_CONFIG_SYSTEM=/dev/null

origin="$TMPDIR/origin.git"
checkout="$TMPDIR/checkout"

git init --quiet --bare --initial-branch=main "$origin"
git init --quiet --initial-branch=main "$checkout"
git -C "$checkout" remote add origin "$origin"
printf 'one\n' > "$checkout/file"
git -C "$checkout" add file
git -C "$checkout" commit --quiet --message "initial"
git -C "$checkout" push --quiet --set-upstream origin main
git -C "$checkout" fetch --quiet origin

make_worktree() {
  local branch="$1" content="$2"
  git -C "$checkout" branch "$branch" main
  git -C "$checkout" worktree add --quiet "$TMPDIR/$branch" "$branch"
  printf '%s\n' "$content" > "$TMPDIR/$branch/file"
}

make_worktree_whose_branch_is_an_ancestor_of_main() {
  make_worktree merged two
  git -C "$TMPDIR/merged" commit --quiet --all --message "merged work"
  git -C "$checkout" merge --quiet merged
  git -C "$checkout" push --quiet origin main
}

make_worktree_whose_branch_never_reached_main() {
  make_worktree ahead three
  git -C "$TMPDIR/ahead" commit --quiet --all --message "unmerged work"
}

make_worktree_with_uncommitted_changes() {
  make_worktree dirty edited
}

make_worktree_whose_branch_went_in_as_a_squash_commit() {
  make_worktree squashed four
  git -C "$TMPDIR/squashed" commit --quiet --all --message "squashed work"
  printf 'four\n' > "$checkout/file"
  git -C "$checkout" commit --quiet --all --message "squashed work, as one commit"
  git -C "$checkout" push --quiet origin main
  export GH_STUB_MERGED_BRANCH=squashed
  GH_STUB_MERGED_SHA="$(git -C "$checkout" rev-parse squashed)"
  export GH_STUB_MERGED_SHA
}

make_worktree_locked_by_a_running_session() {
  make_worktree locked five
  git -C "$TMPDIR/locked" commit --quiet --all --message "locked work"
  git -C "$checkout" merge --quiet locked
  git -C "$checkout" push --quiet origin main
  git -C "$checkout" worktree lock "$TMPDIR/locked"
}

make_worktree_whose_directory_has_gone() {
  make_worktree vanished six
  git -C "$TMPDIR/vanished" commit --quiet --all --message "vanished work"
  git -C "$checkout" merge --quiet vanished
  git -C "$checkout" push --quiet origin main
  rm -rf "$TMPDIR/vanished"
}

make_worktree_whose_branch_is_an_ancestor_of_main
make_worktree_whose_branch_never_reached_main
make_worktree_with_uncommitted_changes
make_worktree_whose_branch_went_in_as_a_squash_commit
make_worktree_locked_by_a_running_session
make_worktree_whose_directory_has_gone

output="$(cd "$checkout" && "$CLEAN" 2>&1)"
status=$?

assert_gone() {
  local label="$1" branch="$2"
  if [ ! -e "$TMPDIR/$branch" ] &&
    ! git -C "$checkout" rev-parse --verify --quiet "refs/heads/$branch" > /dev/null; then
    printf "  OK  %s\n" "$label"
    pass=$((pass + 1))
  else
    printf "  KO  %s — worktree or branch still there\n" "$label"
    fail=$((fail + 1))
  fi
}

assert_stays() {
  local label="$1" branch="$2"
  if [ -e "$TMPDIR/$branch" ] &&
    git -C "$checkout" rev-parse --verify --quiet "refs/heads/$branch" > /dev/null; then
    printf "  OK  %s\n" "$label"
    pass=$((pass + 1))
  else
    printf "  KO  %s — worktree or branch was taken\n" "$label"
    fail=$((fail + 1))
  fi
}

assert_reports() {
  local label="$1" expected="$2"
  if printf '%s' "$output" | grep --quiet --fixed-strings -- "$expected"; then
    printf "  OK  %s\n" "$label"
    pass=$((pass + 1))
  else
    printf "  KO  %s — '%s' not in:\n%s\n" "$label" "$expected" "$output"
    fail=$((fail + 1))
  fi
}

printf "Test group: the run itself\n"

if [ "$status" -eq 0 ]; then
  printf "  OK  exits 0\n"
  pass=$((pass + 1))
else
  printf "  KO  exits %s\n%s\n" "$status" "$output"
  fail=$((fail + 1))
fi

printf "\nTest group: what the clean takes\n"

assert_gone "a branch merged into main goes" merged
assert_gone "a squash merge the pull request confirms goes" squashed

printf "\nTest group: what the clean leaves\n"

assert_stays "a branch with commits of its own stays" ahead
assert_stays "a worktree with uncommitted changes stays" dirty
assert_stays "a locked worktree stays even though its work is on main" locked

if [ -e "$checkout/file" ]; then
  printf "  OK  the main checkout is never a candidate\n"
  pass=$((pass + 1))
else
  printf "  KO  the main checkout was taken\n"
  fail=$((fail + 1))
fi

printf "\nTest group: the report says what happened and why\n"

assert_reports "counts what went" "removed 2"
assert_reports "counts what stayed" "kept 4"
assert_reports "passes on the give-back's word for a vanished worktree" "is not a directory"
assert_reports "passes on the give-back's word for uncommitted changes" "has uncommitted changes"
assert_reports "passes on the give-back's word for work not on main" "is not an ancestor of origin/main"
assert_reports "names the lock as the reason" "locked by a running session"

printf "\n%d passed, %d failed\n" "$pass" "$fail"
[ "$fail" -eq 0 ]
