#!/usr/bin/env bash
set -euo pipefail

SHARED_DIR="${CLAUDE_SHARED_DIR:-$HOME/.claude-shared}"
CRATE="${BOARD_CARD_CRATE:-$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && cd ../../../marketplace/plugins/cockpit/board-card && pwd)}"
BINARY="$CRATE/target/release/board-card"

source "$SHARED_DIR/accounts.sh"
source "$SHARED_DIR/board-accounts.sh"

MODE="apply"
ASSUME_YES=0
for arg in "$@"; do
  case "$arg" in
    --check)   MODE="check" ;;
    --apply)   MODE="apply" ;;
    --yes|-y)  ASSUME_YES=1 ;;
    -h|--help) echo "usage: sync.board-card.sh [--check|--apply] [--yes]"; exit 0 ;;
    *)         echo "error: unknown arg: $arg" >&2; exit 2 ;;
  esac
done

if [ -t 1 ]; then
  C_RESET=$'\033[0m'; C_RED=$'\033[31m'; C_GREEN=$'\033[32m'
  C_YELLOW=$'\033[33m'; C_DIM=$'\033[2m'
else
  C_RESET=''; C_RED=''; C_GREEN=''; C_YELLOW=''; C_DIM=''
fi

board_account=""
for acct in "${ACCOUNTS[@]}"; do
  if account_works_the_ticket_board "$acct"; then
    board_account="$acct"
    break
  fi
done

if [ -z "$board_account" ]; then
  echo "${C_DIM}no account here works the board, so board-card is not built${C_RESET}"
  exit 0
fi

stale=""
if [ ! -x "$BINARY" ]; then
  stale="not built"
else
  for file in "$CRATE/Cargo.toml" "$CRATE/Cargo.lock" "$CRATE"/src/*.rs; do
    if [ "$file" -nt "$BINARY" ]; then
      stale="older than ${file#"$CRATE"/}"
      break
    fi
  done
fi

if [ -z "$stale" ]; then
  echo "${C_GREEN}✓ board-card${C_RESET}  built from its current sources  ${C_DIM}($BINARY)${C_RESET}"
  exit 0
fi

echo "${C_YELLOW}△ board-card  DRIFT${C_RESET}  the binary is $stale  ${C_DIM}($BINARY)${C_RESET}"

[ "$MODE" = "check" ] && exit 1

cargo="$(command -v cargo || true)"
[ -n "$cargo" ] || [ ! -x "$HOME/.cargo/bin/cargo" ] || cargo="$HOME/.cargo/bin/cargo"
if [ -z "$cargo" ]; then
  echo "    ${C_RED}✗ cargo is not installed${C_RESET} - install Rust from https://rustup.rs and run this again; until then board-card cannot start"
  exit 1
fi

if ! confirm "    " "build board-card with cargo?"; then
  echo "    skipped"
  exit 0
fi

CARGO_TARGET_DIR="$CRATE/target" "$cargo" build --release --quiet --manifest-path "$CRATE/Cargo.toml"
echo "    ✓ built $BINARY"
exit 0
