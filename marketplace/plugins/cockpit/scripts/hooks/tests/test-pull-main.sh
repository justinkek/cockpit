#!/usr/bin/env bash

HOOK="$(cd "$(dirname "$0")/.." && pwd)/pull-main.sh"
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

REMOTE="$TMPDIR/remote.git"
REPO="$TMPDIR/repo"
UPSTREAM="$TMPDIR/upstream"
OTHER_REMOTE="$TMPDIR/other-remote.git"
OTHER_REPO="$TMPDIR/other-repo"
OTHER_UPSTREAM="$TMPDIR/other-upstream"
SHARED="$REPO/agents/claude"
SYNCED="$TMPDIR/synced"
SYNC_EXIT_CODE="$TMPDIR/sync-exit-code"
NO_HOOKS="$TMPDIR/no-hooks"
mkdir -p "$NO_HOOKS"

repo_git() { git -C "$REPO" "$@"; }
upstream_git() { git -C "$UPSTREAM" "$@"; }
other_git() { git -C "$OTHER_REPO" "$@"; }
other_upstream_git() { git -C "$OTHER_UPSTREAM" "$@"; }

commit_in() {
  local checkout="$1" name="$2"
  printf '%s\n' "$name" > "$checkout/$name"
  git -C "$checkout" add "$name"
  git -C "$checkout" commit --quiet --message "$name"
}

build_fixture() {
  rm -rf "$REMOTE" "$REPO" "$UPSTREAM"
  rm -f "$SYNCED"

  git init --quiet --bare --initial-branch=main "$REMOTE"

  git init --quiet --initial-branch=main "$REPO"
  repo_git config core.hooksPath "$NO_HOOKS"
  repo_git config user.email "test@example.com"
  repo_git config user.name "Test"
  repo_git remote add origin "$REMOTE"

  printf '0\n' > "$SYNC_EXIT_CODE"

  mkdir -p "$SHARED"
  cat > "$SHARED/sync.sh" <<STUB
#!/usr/bin/env bash
printf 'applied %s\n' "\$*" >> "$SYNCED"
exit "\$(cat "$SYNC_EXIT_CODE")"
STUB
  chmod +x "$SHARED/sync.sh"
  repo_git add agents/claude/sync.sh

  commit_in "$REPO" base
  repo_git push --quiet --set-upstream origin main

  repo_git remote set-head origin --auto >/dev/null

  git clone --quiet "$REMOTE" "$UPSTREAM"
  upstream_git config core.hooksPath "$NO_HOOKS"
  upstream_git config user.email "test@example.com"
  upstream_git config user.name "Test"
}

build_other_fixture() {
  rm -rf "$OTHER_REMOTE" "$OTHER_REPO" "$OTHER_UPSTREAM"

  git init --quiet --bare --initial-branch=main "$OTHER_REMOTE"

  git init --quiet --initial-branch=main "$OTHER_REPO"
  other_git config core.hooksPath "$NO_HOOKS"
  other_git config user.email "test@example.com"
  other_git config user.name "Test"
  other_git remote add origin "$OTHER_REMOTE"

  commit_in "$OTHER_REPO" base
  other_git push --quiet --set-upstream origin main
  other_git remote set-head origin --auto >/dev/null

  git clone --quiet "$OTHER_REMOTE" "$OTHER_UPSTREAM"
  other_upstream_git config core.hooksPath "$NO_HOOKS"
  other_upstream_git config user.email "test@example.com"
  other_upstream_git config user.name "Test"
}

advance_the_remote() {
  commit_in "$UPSTREAM" ahead
  upstream_git push --quiet origin main
}

advance_the_other_remote() {
  commit_in "$OTHER_UPSTREAM" ahead
  other_upstream_git push --quiet origin main
}

run_hook() {
  printf '{"session_id": "test"}' \
    | CLAUDE_SHARED_DIR="$SHARED" bash "$HOOK" 2>/dev/null
}

run_hook_for() {
  printf '{"session_id": "test"}' \
    | CLAUDE_SHARED_DIR="$SHARED" bash "$HOOK" "$1" 2>/dev/null
}

hook_exit_status() {
  printf '{"session_id": "test"}' \
    | CLAUDE_SHARED_DIR="$SHARED" bash "$HOOK" >/dev/null 2>&1
  printf '%s' "$?"
}

local_head() { repo_git rev-parse HEAD; }
remote_head() { upstream_git rev-parse HEAD; }
other_local_head() { other_git rev-parse HEAD; }
other_remote_head() { other_upstream_git rev-parse HEAD; }
sync_count() {
  if [ -f "$SYNCED" ]; then grep --count applied "$SYNCED" | tr -d ' '; else printf '0'; fi
}
sync_arguments() {
  if [ -f "$SYNCED" ]; then sed 's/^applied //' "$SYNCED"; fi
}

printf "Test group: a clean checkout behind its remote is carried forward\n"

build_fixture
advance_the_remote
output="$(run_hook)"
assert_eq "the checkout is now at the remote's commit" "$(remote_head)" "$(local_head)"
assert_contains "it says how many it pulled" "pulled 1" "$output"
assert_eq "the generated config was rebuilt" "1" "$(sync_count)"
assert_eq "the apply was asked for without a prompt" "--apply --yes" "$(sync_arguments)"

build_fixture
advance_the_remote
printf '1\n' > "$SYNC_EXIT_CODE"
output="$(run_hook)"
assert_eq "a failed apply — the checkout still moved" "$(remote_head)" "$(local_head)"
assert_contains "a failed apply — it does not claim the rebuild" "could not be rebuilt" "$output"

printf "\nTest group: the checkout is left alone when a pull would not be safe\n"

build_fixture
advance_the_remote
head_before_the_hook="$(local_head)"
printf 'edited\n' > "$REPO/base"
output="$(run_hook)"
assert_eq "uncommitted changes — the checkout did not move" "$head_before_the_hook" "$(local_head)"
assert_contains "uncommitted changes — it says why" "uncommitted changes" "$output"
assert_eq "uncommitted changes — nothing was rebuilt" "0" "$(sync_count)"

build_fixture
advance_the_remote
commit_in "$REPO" diverged
head_before_the_hook="$(local_head)"
output="$(run_hook)"
assert_eq "diverged — the checkout did not move" "$head_before_the_hook" "$(local_head)"
assert_contains "diverged — it says why" "diverged" "$output"
assert_eq "diverged — nothing was rebuilt" "0" "$(sync_count)"

build_fixture
advance_the_remote
repo_git checkout --quiet -b side
head_before_the_hook="$(local_head)"
output="$(run_hook)"
assert_eq "not on the default branch — the checkout did not move" "$head_before_the_hook" "$(local_head)"
assert_contains "not on the default branch — it names the branch it found" "on side, not main" "$output"
assert_eq "not on the default branch — nothing was rebuilt" "0" "$(sync_count)"

printf "\nTest group: nothing to say, and nothing said\n"

build_fixture
assert_eq "already current — no output" "" "$(run_hook)"
assert_eq "already current — nothing was rebuilt" "0" "$(sync_count)"
assert_eq "already current — the hook exits clean" "0" "$(hook_exit_status)"

build_fixture
rm -rf "$REPO/.git"
assert_eq "not a repository — no output" "" "$(run_hook)"
assert_eq "not a repository — the hook exits clean" "0" "$(hook_exit_status)"

printf "\nTest group: a directory argument names which repository moves\n"

build_fixture
build_other_fixture
advance_the_remote
advance_the_other_remote
dotfiles_head_before_the_hook="$(local_head)"
output="$(run_hook_for "$OTHER_REPO")"
assert_eq "the named repository moved to its remote" "$(other_remote_head)" "$(other_local_head)"
assert_eq "the dotfiles checkout was left where it was" "$dotfiles_head_before_the_hook" "$(local_head)"
assert_eq "nothing was rebuilt from a repository that is not dotfiles" "0" "$(sync_count)"
assert_contains "it names the repository it moved" "pulled 1 in" "$output"

build_fixture
build_other_fixture
advance_the_other_remote
other_head_before_the_hook="$(other_local_head)"
printf 'edited\n' > "$OTHER_REPO/base"
output="$(run_hook_for "$OTHER_REPO")"
assert_eq "a dirty named repository did not move" "$other_head_before_the_hook" "$(other_local_head)"
assert_contains "a dirty named repository says why" "uncommitted changes" "$output"

build_fixture
advance_the_remote
output="$(run_hook_for "$REPO")"
assert_eq "naming the dotfiles checkout still moves it" "$(remote_head)" "$(local_head)"
assert_eq "naming the dotfiles checkout still rebuilds the config" "1" "$(sync_count)"

build_fixture
advance_the_remote
head_before_the_hook="$(local_head)"
run_hook_for "$TMPDIR" >/dev/null
assert_eq "a directory in no repository leaves everything alone" "$head_before_the_hook" "$(local_head)"
assert_eq "a directory in no repository rebuilds nothing" "0" "$(sync_count)"

printf "\n%s passed, %s failed\n" "$pass" "$fail"
[ "$fail" -eq 0 ]
