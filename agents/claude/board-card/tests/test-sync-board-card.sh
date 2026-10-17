#!/usr/bin/env bash

CONCERN_DIR="$(cd "$(dirname "$0")/.." && pwd)"
WORKER="$CONCERN_DIR/sync.board-card.sh"
REPO="$(cd "$CONCERN_DIR/../../.." && pwd)"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

pass=0
fail=0

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

assert_equal() {
  local label="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then
    printf "  OK  %s\n" "$label"
    pass=$((pass + 1))
  else
    printf "  KO  %s — expected '%s', got '%s'\n" "$label" "$expected" "$actual"
    fail=$((fail + 1))
  fi
}

CRATE="$WORK/crate"
BINARY="$CRATE/target/release/board-card"
export CALLS_FILE="$WORK/calls"

build_fixture() {
  local accounts="$1"
  rm -rf "$WORK/shared" "$CRATE" "$WORK/bin" "$CALLS_FILE"
  mkdir -p "$WORK/shared" "$CRATE/src" "$WORK/bin"
  cp "$REPO/agents/claude/board-accounts.sh" "$WORK/shared/board-accounts.sh"
  cat > "$WORK/shared/accounts.sh" <<ACCOUNTS
ACCOUNTS=($accounts)
acct_dir() { printf '%s' "\$HOME/.claude-\$1"; }
ACCOUNTS
  printf '[package]\nname = "board-card"\n' > "$CRATE/Cargo.toml"
  printf 'fn main() {}\n' > "$CRATE/src/main.rs"
  cat > "$WORK/bin/cargo" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "CARGO_TARGET_DIR=$CARGO_TARGET_DIR $*" >> "$CALLS_FILE"
mkdir -p "$CARGO_TARGET_DIR/release"
printf '#!/bin/sh\n' > "$CARGO_TARGET_DIR/release/board-card"
chmod +x "$CARGO_TARGET_DIR/release/board-card"
STUB
  chmod +x "$WORK/bin/cargo"
  : > "$CALLS_FILE"
}

run_worker() {
  output="$(HOME="$WORK/home" \
    PATH="$WORK/bin:$PATH" \
    CLAUDE_SHARED_DIR="$WORK/shared" \
    BOARD_CARD_CRATE="$CRATE" \
    BASH_ENV="$REPO/agents/shared/prompts.sh" \
    bash "$WORKER" "$@" 2>&1 < /dev/null)"
  status=$?
}

printf "Test group: check reports a binary that is missing or older than its sources\n"

build_fixture "probe"
run_worker --check
assert_equal "check exits 1 when board-card was never built" "1" "$status"
assert_contains "and says it is not built" "not built" "$output"
assert_equal "check builds nothing" "" "$(cat "$CALLS_FILE")"

printf "\nTest group: apply builds the crate in its own target directory\n"

run_worker --apply --yes
assert_equal "apply exits 0" "0" "$status"
assert_equal "it runs one release build of the crate" "CARGO_TARGET_DIR=$CRATE/target build --release --quiet --manifest-path $CRATE/Cargo.toml" "$(cat "$CALLS_FILE")"
assert_contains "and names the binary it built" "built $BINARY" "$output"

printf "\nTest group: a binary built from the current sources has nothing to do\n"

: > "$CALLS_FILE"
run_worker --check
assert_equal "check exits 0" "0" "$status"
run_worker --apply --yes
assert_equal "apply builds nothing" "" "$(cat "$CALLS_FILE")"

printf "\nTest group: a source newer than the binary is rebuilt\n"

touch -t 203001010000 "$CRATE/src/main.rs"
run_worker --check
assert_equal "check exits 1" "1" "$status"
assert_contains "naming the newer source" "older than src/main.rs" "$output"
run_worker --apply --yes
assert_equal "apply builds it again" "1" "$(wc -l < "$CALLS_FILE" | tr -d ' ')"

printf "\nTest group: a machine with no board account builds nothing\n"

build_fixture "claude"
run_worker --apply --yes
assert_equal "apply exits 0" "0" "$status"
assert_equal "cargo is not run" "" "$(cat "$CALLS_FILE")"

printf "\n%d passed, %d failed\n" "$pass" "$fail"
[ "$fail" -eq 0 ]
