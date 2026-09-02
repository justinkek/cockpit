#!/usr/bin/env bash

CATCHER="$(cd "$(dirname "$0")/../.." && pwd)/pr-catch-up-with-base"
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
  if printf '%s' "$output" | grep --quiet --fixed-strings "$expected"; then
    printf "  OK  %s\n" "$label"
    pass=$((pass + 1))
  else
    printf "  KO  %s — expected '%s' in output '%s'\n" "$label" "$expected" "$output"
    fail=$((fail + 1))
  fi
}

BIN="$TMPDIR/bin"
mkdir -p "$BIN"

cat > "$BIN/gh" <<'STUB'
#!/usr/bin/env bash
[ -n "${PR_CATCH_UP_TEST_BASE:-}" ] || exit 1
printf '%s %s\n' "$PR_CATCH_UP_TEST_BASE" "${PR_CATCH_UP_TEST_REVIEWS:-0}"
STUB

chmod +x "$BIN/gh"

build_repository() {
  local name="$1"
  local remote="$TMPDIR/$name-remote"
  local clone="$TMPDIR/$name"

  git init --quiet --bare --initial-branch=main "$remote"
  git clone --quiet "$remote" "$clone" 2>/dev/null

  git -C "$clone" config user.email "test@example.com"
  git -C "$clone" config user.name "Test"
  git -C "$clone" config core.hooksPath /dev/null
  printf 'one\n' > "$clone/base.txt"
  git -C "$clone" add base.txt
  git -C "$clone" commit --quiet --message "base"
  git -C "$clone" push --quiet origin main

  git -C "$clone" switch --quiet --create feature
  printf 'branch\n' > "$clone/branch.txt"
  git -C "$clone" add branch.txt
  git -C "$clone" commit --quiet --message "branch"
  git -C "$clone" push --quiet --set-upstream origin feature

  printf '%s' "$clone"
}

remote_tip() {
  git -C "$1" ls-remote origin refs/heads/feature | awk '{ print $1 }'
}

move_branch_ahead() {
  local clone="$1"
  local mirror="$TMPDIR/branch-mirror-$RANDOM"

  git clone --quiet --branch feature "$(git -C "$clone" remote get-url origin)" "$mirror" 2>/dev/null
  git -C "$mirror" config user.email "test@example.com"
  git -C "$mirror" config user.name "Test"
  git -C "$mirror" config core.hooksPath /dev/null
  printf 'someone else\n' > "$mirror/theirs.txt"
  git -C "$mirror" add theirs.txt
  git -C "$mirror" commit --quiet --message "pushed by someone else"
  git -C "$mirror" push --quiet origin feature
  rm -rf "$mirror"
}

move_base_ahead() {
  local clone="$1" file="$2" content="$3"
  local mirror="$TMPDIR/mirror-$file-$RANDOM"

  git clone --quiet "$(git -C "$clone" remote get-url origin)" "$mirror" 2>/dev/null
  git -C "$mirror" config user.email "test@example.com"
  git -C "$mirror" config user.name "Test"
  git -C "$mirror" config core.hooksPath /dev/null
  printf '%s\n' "$content" > "$mirror/$file"
  git -C "$mirror" add "$file"
  git -C "$mirror" commit --quiet --message "moved on"
  git -C "$mirror" push --quiet origin main
  rm -rf "$mirror"
}

run_catcher() {
  local clone="$1" base="${2:-main}" reviews="${3:-0}"
  (cd "$clone" && PATH="$BIN:$PATH" PR_CATCH_UP_TEST_BASE="$base" PR_CATCH_UP_TEST_REVIEWS="$reviews" bash "$CATCHER" 2>&1)
}

printf "Test group: nothing to do is silent\n"

clone="$(build_repository no-pull-request)"
output="$( (cd "$clone" && PATH="$BIN:$PATH" bash "$CATCHER" 2>&1) )"
status=$?
assert_eq "no open pull request prints nothing" "" "$output"
assert_eq "and exits 0" "0" "$status"

clone="$(build_repository up-to-date)"
before="$(git -C "$clone" rev-parse HEAD)"
output="$(run_catcher "$clone")"
status=$?
assert_eq "a base that has not moved prints nothing" "" "$output"
assert_eq "and exits 0" "0" "$status"
assert_eq "and leaves the branch where it was" "$before" "$(git -C "$clone" rev-parse HEAD)"

clone="$(build_repository unknown-base)"
move_base_ahead "$clone" "moved.txt" "moved"
before="$(git -C "$clone" rev-parse HEAD)"
output="$(run_catcher "$clone" "release-42")"
status=$?
assert_eq "a base the remote does not carry prints nothing" "" "$output"
assert_eq "and exits 0" "0" "$status"
assert_eq "and never claims a conflict" "$before" "$(git -C "$clone" rev-parse HEAD)"

printf "\nTest group: a pull request carrying no review is rebased and force-pushed\n"

clone="$(build_repository behind)"
move_base_ahead "$clone" "moved.txt" "moved"
output="$(run_catcher "$clone")"
status=$?
assert_eq "exits 0" "0" "$status"
assert_contains "names the base it rebased onto" "rebased onto origin/main" "$output"
assert_eq "one line only" "1" "$(printf '%s' "$output" | grep --count . | tr -d ' ')"
git -C "$clone" merge-base --is-ancestor origin/main HEAD
assert_eq "the branch now sits on top of the base" "0" "$?"
assert_eq "and its own commit survived" "branch" "$(tr -d '\n' < "$clone/branch.txt")"
assert_eq "and the pull request carries what the branch does" \
  "$(git -C "$clone" rev-parse HEAD)" "$(remote_tip "$clone")"

printf "\nTest group: a pull request carrying a review is merged, never rebased\n"

clone="$(build_repository reviewed)"
own_commit="$(git -C "$clone" rev-parse HEAD)"
move_base_ahead "$clone" "moved.txt" "moved"
output="$(run_catcher "$clone" "main" "2")"
status=$?
assert_eq "exits 0" "0" "$status"
assert_contains "names the merge, not a rebase" "merged origin/main in" "$output"
git -C "$clone" merge-base --is-ancestor origin/main HEAD
assert_eq "the base is now an ancestor of the branch" "0" "$?"
assert_eq "and the commit reviewers commented on kept its hash" "0" \
  "$(git -C "$clone" merge-base --is-ancestor "$own_commit" HEAD > /dev/null 2>&1; printf '%s' $?)"
assert_eq "and the pull request carries what the branch does" \
  "$(git -C "$clone" rev-parse HEAD)" "$(remote_tip "$clone")"

printf "\nTest group: a merge conflict is undone, never left half-applied\n"

clone="$(build_repository merge-conflict)"
printf 'branch side\n' > "$clone/contested.txt"
git -C "$clone" add contested.txt
git -C "$clone" commit --quiet --message "contested on the branch"
move_base_ahead "$clone" "contested.txt" "base side"
before="$(git -C "$clone" rev-parse HEAD)"
output="$(run_catcher "$clone" "main" "2")"
status=$?
assert_eq "exits 4" "4" "$status"
assert_contains "says the merge was undone" "the merge stopped on a conflict and was undone" "$output"
assert_eq "the branch is back where it started" "$before" "$(git -C "$clone" rev-parse HEAD)"
assert_eq "no merge is left in progress" "absent" \
  "$(test -e "$clone/.git/MERGE_HEAD" && printf 'present' || printf 'absent')"

printf "\nTest group: a push the remote refuses is reported, not swallowed\n"

clone="$(build_repository push-refused)"
move_base_ahead "$clone" "moved.txt" "moved"
move_branch_ahead "$clone"
output="$(run_catcher "$clone" "main" "2")"
status=$?
assert_eq "exits 5" "5" "$status"
assert_contains "names the refused push" "the push the pull request needs was refused" "$output"
git -C "$clone" merge-base --is-ancestor origin/main HEAD
assert_eq "and the branch keeps the merge it just built" "0" "$?"

printf "\nTest group: uncommitted work is never rebased over\n"

clone="$(build_repository dirty)"
move_base_ahead "$clone" "moved.txt" "moved"
printf 'work in progress' > "$clone/branch.txt"
before="$(git -C "$clone" rev-parse HEAD)"
output="$(run_catcher "$clone")"
status=$?
assert_eq "exits 3" "3" "$status"
assert_contains "says why it was left alone" "uncommitted changes" "$output"
assert_eq "the branch did not move" "$before" "$(git -C "$clone" rev-parse HEAD)"
assert_eq "the working tree is untouched" "work in progress" "$(cat "$clone/branch.txt")"

printf "\nTest group: a watcher says a standing refusal once, not once per poll\n"

clone="$(build_repository repeated-refusal)"
move_base_ahead "$clone" "moved.txt" "moved"
printf 'work in progress' > "$clone/branch.txt"
watched="$TMPDIR/watched-output"
(cd "$clone" && PATH="$BIN:$PATH" PR_CATCH_UP_TEST_BASE="main" PR_CATCH_UP_TEST_REVIEWS="0" \
  PR_CATCH_UP_INTERVAL=1 bash "$CATCHER" > "$watched" 2>&1) &
watcher="$!"
sleep 4
kill "$watcher" 2>/dev/null || true
wait "$watcher" 2>/dev/null || true
assert_contains "the refusal is said" "uncommitted changes" "$(cat "$watched")"
assert_eq "and said once across several polls" "1" "$(grep --count . < "$watched" | tr -d ' ')"

printf "\nTest group: a conflict is undone, never left half-applied\n"

clone="$(build_repository conflict)"
printf 'branch side\n' > "$clone/contested.txt"
git -C "$clone" add contested.txt
git -C "$clone" commit --quiet --message "contested on the branch"
move_base_ahead "$clone" "contested.txt" "base side"
before="$(git -C "$clone" rev-parse HEAD)"
output="$(run_catcher "$clone")"
status=$?
assert_eq "exits 4" "4" "$status"
assert_contains "says the rebase was undone" "stopped on a conflict and was undone" "$output"
assert_eq "the branch is back where it started" "$before" "$(git -C "$clone" rev-parse HEAD)"
assert_eq "no rebase is left in progress" "absent" \
  "$(test -e "$clone/.git/rebase-merge" -o -e "$clone/.git/rebase-apply" && printf 'present' || printf 'absent')"

printf "\nTest group: a rebase already in progress is left alone\n"

clone="$(build_repository in-progress)"
move_base_ahead "$clone" "moved.txt" "moved"
mkdir -p "$clone/.git/rebase-merge"
output="$(run_catcher "$clone")"
status=$?
assert_eq "prints nothing" "" "$output"
assert_eq "and exits 0" "0" "$status"
rm -rf "$clone/.git/rebase-merge"

printf "\nTest group: the ready-for-cr skill is what arms it\n"

READY_FOR_CR="$(cd "$(dirname "$0")/../../../skills/ticket:4:ready-for-cr" && pwd)/SKILL.md"
assert_contains "the skill names the script" "pr-catch-up-with-base" "$(cat "$READY_FOR_CR")"
assert_contains "and the interval that makes it poll" "PR_CATCH_UP_INTERVAL" "$(cat "$READY_FOR_CR")"
assert_contains "and arms it persistently" "persistent" "$(cat "$READY_FOR_CR")"

printf "\n%d passed, %d failed\n" "$pass" "$fail"
[ "$fail" -eq 0 ]
