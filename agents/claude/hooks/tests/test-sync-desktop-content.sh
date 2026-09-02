#!/usr/bin/env bash

REPO="$(cd "$(dirname "$0")/../../../.." && pwd)"
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

pass=0
fail=0

assert_absent() {
  local label="$1" file="$2" phrase="$3"
  if grep --quiet --fixed-strings "$phrase" "$file"; then
    printf "  KO  %s — '%s' is still in %s\n" "$label" "$phrase" "$file"
    fail=$((fail + 1))
  else
    printf "  OK  %s\n" "$label"
    pass=$((pass + 1))
  fi
}

assert_contains() {
  local label="$1" file="$2" phrase="$3"
  if grep --quiet --fixed-strings "$phrase" "$file"; then
    printf "  OK  %s\n" "$label"
    pass=$((pass + 1))
  else
    printf "  KO  %s — '%s' is not in %s\n" "$label" "$phrase" "$file"
    fail=$((fail + 1))
  fi
}

SHARED="$TMPDIR/shared"
AGENTS_SHARED="$TMPDIR/agents-shared"
DESKTOP_DIR="$TMPDIR/desktop"
BOARD_DIR="$TMPDIR/board"

mkdir -p "$SHARED/claude-md" "$AGENTS_SHARED" "$DESKTOP_DIR" "$BOARD_DIR" "$TMPDIR/home"
cp "$REPO/agents/claude/sync.sh" "$SHARED/sync.sh"
cp "$REPO/agents/claude/board-accounts.sh" "$SHARED/board-accounts.sh"
cp "$REPO/agents/claude/claude-md/sync.claude-md.sh" "$SHARED/claude-md/sync.claude-md.sh"
cp "$REPO/agents/claude/claude-md/adapter.CLAUDE.md" "$SHARED/claude-md/adapter.CLAUDE.md"
cp "$REPO/agents/shared/base.AGENTS.md" "$AGENTS_SHARED/base.AGENTS.md"
cp "$REPO/agents/shared/board.AGENTS.md" "$AGENTS_SHARED/board.AGENTS.md"
cp "$REPO/agents/shared/prompts.sh" "$AGENTS_SHARED/prompts.sh"

cat > "$SHARED/accounts.sh" <<ACCOUNTS
ACCOUNTS=(claude cockpit)
acct_dir() {
  case "\$1" in
    claude) printf '%s' "$DESKTOP_DIR" ;;
    *)      printf '%s' "$BOARD_DIR" ;;
  esac
}
ACCOUNTS

CLAUDE_SHARED_DIR="$SHARED" \
  AGENTS_SHARED_DIR="$AGENTS_SHARED" \
  HOME="$TMPDIR/home" \
  bash "$SHARED/sync.sh" claude-md --apply > "$TMPDIR/apply.out" 2>&1 < /dev/null

DESKTOP="$DESKTOP_DIR/CLAUDE.md"
BOARD="$BOARD_DIR/CLAUDE.md"

if [ ! -f "$DESKTOP" ] || [ ! -f "$BOARD" ]; then
  printf "  KO  the sync wrote a CLAUDE.md for both accounts\n"
  cat "$TMPDIR/apply.out"
  printf "\n%d passed, %d failed\n" "$pass" "$((fail + 1))"
  exit 1
fi

printf "Test group: the account an unwrapped launch lands in loses the board\n"

assert_absent "no ticket registration rule" "$DESKTOP" "Cockpit URL-first"
assert_absent "no worktree rule" "$DESKTOP" "Dev on a ticket happens in that ticket's own worktree"
assert_absent "no claim lock rule" "$DESKTOP" "## Claim locks"
assert_absent "no commit routing through the board" "$DESKTOP" "/cockpit:ticket:4:commit"

printf "\nTest group: and keeps everything that is not the board\n"

assert_contains "the writing rules" "$DESKTOP" "## Plain English"
assert_contains "the reply shape rules" "$DESKTOP" "## Response Formatting"
assert_contains "the comment rule" "$DESKTOP" "## Comments"
assert_contains "the solution ladder" "$DESKTOP" "## Solution ladder"
assert_contains "the shell rules" "$DESKTOP" "## Shell & tooling"
assert_contains "the Claude adapter" "$DESKTOP" "## Claude directories"

printf "\nTest group: an account reached through a wrapper gets the board\n"

assert_contains "the ticket registration rule" "$BOARD" "Cockpit URL-first"
assert_contains "the worktree rule" "$BOARD" "Dev on a ticket happens in that ticket's own worktree"
assert_contains "the claim lock rule" "$BOARD" "## Claim locks"
assert_contains "the commit routing" "$BOARD" "/cockpit:ticket:4:commit"

printf "\nTest group: and takes the rest through the hardcoded global read\n"

assert_absent "the writing rules are not repeated per profile" "$BOARD" "## Plain English"

printf "\n%d passed, %d failed\n" "$pass" "$fail"
[ "$fail" -eq 0 ]
