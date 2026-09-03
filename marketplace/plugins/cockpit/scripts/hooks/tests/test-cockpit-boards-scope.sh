#!/usr/bin/env bash

LIB="$(cd "$(dirname "$0")/../../../../../../agents/claude" && pwd)/ticket-state-lib.sh"
TMPDIR="$(cd "$(mktemp -d)" && pwd -P)"
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

source "$LIB"

# The names the function returns, in order, on one line — the whole answer a
# caller cares about, and short enough to compare literally.
names() {
  COCKPIT_REPO="$1" cockpit_boards 2>/dev/null | cut -f1 | tr '\n' ' ' | sed 's/ $//'
}

# The exit code alone. It is what tells the copilot skill whether to ask.
status() {
  COCKPIT_REPO="$1" cockpit_boards >/dev/null 2>&1
  echo $?
}

cat > "$TMPDIR/boards.json" <<JSON
{"boards":[
  {"name":"Cockpit","ids":{"tickets-database":"db-cockpit"},"view_id":"v-cockpit","checkouts":["$TMPDIR/dotfiles"]},
  {"name":"Project","ids":{"tickets-database":"db-project"},"checkouts":["$TMPDIR/project"]}
]}
JSON

printf '{"boards":[]}' > "$TMPDIR/empty.json"

printf '{"boards":[{"name":"Home","ids":{"tickets-database":"db-home"},"repos":["~/dotfiles"]},{"name":"Other","ids":{"tickets-database":"db-other"},"repos":["/tmp/other"]}]}' \
  > "$TMPDIR/tilde.json"

printf "Test group: the board claiming this checkout is the only one offered\n"

COCKPIT_BOARDS_FILE="$TMPDIR/boards.json"

assert_eq "a session in the project checkout gets its own board" \
  "Project" "$(names "$TMPDIR/project")"
assert_eq "a session in the dotfiles checkout gets the cockpit" \
  "Cockpit" "$(names "$TMPDIR/dotfiles")"

printf "\nTest group: a checkout no board claims is a question, not a default\n"

assert_eq "no board is offered" "" "$(names "$TMPDIR/unclaimed")"
assert_eq "and exit 3 tells the skill to ask" "3" "$(status "$TMPDIR/unclaimed")"

printf "\nTest group: COCKPIT_BOARD carries the user's answer\n"

assert_eq "it names a board outright, whatever the checkout" "Project" \
  "$(COCKPIT_BOARD=Project names "$TMPDIR/unclaimed")"
assert_eq "it overrides a checkout that claims another board" "Project" \
  "$(COCKPIT_BOARD=Project names "$TMPDIR/dotfiles")"
assert_eq "a name no board has exits 4, never falls through to a board" "4" \
  "$(COCKPIT_BOARD=Nope status "$TMPDIR/dotfiles")"

printf "\nTest group: a file with no boards is a broken config, not a question\n"

COCKPIT_BOARDS_FILE="$TMPDIR/empty.json"

assert_eq "exit 5, so nobody asks the user to pick from nothing" "5" \
  "$(status "$TMPDIR/dotfiles")"

printf "\nTest group: a leading ~ means the home directory, on a file still using the old key\n"

COCKPIT_BOARDS_FILE="$TMPDIR/tilde.json"

assert_eq "matches the same checkout written in full" \
  "Home" "$(names "$HOME/dotfiles")"

printf "\nTest group: a checkout no board claims keeps the reported defect fixed\n"

assert_eq "a session in no known checkout is offered nothing, and asks" \
  "3" "$(status "/tmp/nowhere")"

printf "\nTest group: a machine with no boards recorded yet\n"

COCKPIT_BOARDS_FILE="$TMPDIR/never-written.json"

assert_eq "the missing file is reported rather than crashing jq" \
  "5" "$(status "$HOME/dotfiles")"
assert_eq "and nothing reaches stdout to be read as a board" \
  "" "$(names "$HOME/dotfiles")"

printf "\nTest group: a worktree is served by the board claiming its main checkout\n"

COCKPIT_BOARDS_FILE="$TMPDIR/boards.json"

git init --quiet --initial-branch main "$TMPDIR/dotfiles"
: > "$TMPDIR/dotfiles/seed"
git -C "$TMPDIR/dotfiles" add seed
GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@example.invalid \
GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@example.invalid \
  git -C "$TMPDIR/dotfiles" commit --quiet --message seed

worktree="$TMPDIR/dotfiles/.claude/worktrees/some-ticket"
git -C "$TMPDIR/dotfiles" worktree add --quiet --detach "$worktree"

assert_eq "a worktree resolves to the checkout it was made from" \
  "$TMPDIR/dotfiles" "$(cd "$worktree" && cockpit_main_checkout)"
assert_eq "the main checkout resolves to itself" \
  "$TMPDIR/dotfiles" "$(cd "$TMPDIR/dotfiles" && cockpit_main_checkout)"
assert_eq "so a session in the worktree is offered that checkout's board" \
  "Cockpit	db-cockpit	v-cockpit" \
  "$(cd "$worktree" && cockpit_boards)"

printf "\nTest group: the fields a caller reads are unchanged\n"

COCKPIT_BOARDS_FILE="$TMPDIR/boards.json"

assert_eq "name, database id and view id, tab separated" \
  "Cockpit	db-cockpit	v-cockpit" \
  "$(COCKPIT_REPO="$TMPDIR/dotfiles" cockpit_boards)"
assert_eq "a board with no view id still returns three fields" \
  "Project	db-project	" \
  "$(COCKPIT_REPO="$TMPDIR/project" cockpit_boards)"

printf "\nTest group: a board missing its tickets-database id says so\n"

printf '{"boards":[{"name":"Idless","ids":{"tickets-data-source":"collection://x"},"repos":["%s/idless"]}]}' \
  "$TMPDIR" > "$TMPDIR/idless.json"
COCKPIT_BOARDS_FILE="$TMPDIR/idless.json"

assert_eq "it exits non-zero rather than handing back an empty id" \
  "1" "$(status "$TMPDIR/idless")"
assert_eq "and nothing reaches stdout to be read as a board" \
  "" "$(names "$TMPDIR/idless")"

printf "\n%d passed, %d failed\n" "$pass" "$fail"
[ "$fail" -eq 0 ]
