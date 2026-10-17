#!/usr/bin/env bash

repo_root_through_symlink() {
  cd "$(dirname "$0")" && cd "$(pwd -P)/../../.." && pwd
}

REPO="$(repo_root_through_symlink)"
BOARD="$REPO/board"

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

finish() {
  printf "\n%d passed, %d failed\n" "$pass" "$fail"
  [ "$fail" -eq 0 ]
  exit
}

if [ ! -d "$BOARD/node_modules/typescript" ]; then
  printf "  KO  the board's packages are installed — run npm ci in %s, or nothing below can be checked\n" "$BOARD"
  fail=1
  finish
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

export CLAUDE_SHARED_DIR="$REPO/agents/claude"
export COCKPIT_BOARD_DIR="$WORK/board"
export TICKET_CLAIM_LOCK_DIR="$WORK/claims"
export TICKET_STATE_DIR="$WORK/state"
export BOARD_CARD="$REPO/marketplace/plugins/cockpit/scripts/board-card"
export GIT_CONFIG_GLOBAL=/dev/null
export GIT_CONFIG_NOSYSTEM=1

node -e '
const fs = require("node:fs");
const [board, work] = process.argv.slice(1);
const ts = require(`${board}/node_modules/typescript`);
const options = { compilerOptions: { module: ts.ModuleKind.ESNext, target: ts.ScriptTarget.ES2022 } };
fs.writeFileSync(`${work}/held.mjs`, ts.transpileModule(fs.readFileSync(`${board}/lib/held.ts`, "utf8"), options).outputText);
' "$BOARD" "$WORK"

COCKPIT_COMMIT_DELAY=0 "$BOARD_CARD" init >/dev/null
COCKPIT_COMMIT_DELAY=0 "$BOARD_CARD" create --kind project --name Home --key HOM >/dev/null
COCKPIT_COMMIT_DELAY=0 "$BOARD_CARD" create --kind epic --name Home --project PRJ-1 >/dev/null
COCKPIT_COMMIT_DELAY=0 "$BOARD_CARD" create --epic EPIC-1 --name "Held" >/dev/null
COCKPIT_COMMIT_DELAY=0 "$BOARD_CARD" create --epic EPIC-1 --name "Held too" >/dev/null

held_file="$WORK/board/.git/board-card-held"

batches() {
  node --input-type=module -e '
import fs from "node:fs";
import { heldBatches } from "'"$WORK"'/held.mjs";
const text = fs.existsSync(process.argv[1]) ? fs.readFileSync(process.argv[1], "utf8") : "";
console.log(JSON.stringify(heldBatches(text, 60)));
' "$held_file"
}

printf "Test group: the board app reads the writes board-card holds before committing them\n"

assert_eq "nothing is held before any write waits" "[]" "$(batches)"

COCKPIT_COMMIT_DELAY=60 "$BOARD_CARD" move HOM-1 "In Dev" >/dev/null
COCKPIT_COMMIT_DELAY=60 "$BOARD_CARD" set HOM-2 name "Held again" >/dev/null
assert_eq "each held write is read as one batch" "2" "$(batches | jq length)"
assert_eq "naming the ticket it changed" "HOM-1 HOM-2" "$(batches | jq --raw-output '[.[].ids[]] | sort | join(" ")')"
assert_eq "and what board-card did to it" "move set" "$(batches | jq --raw-output '[.[].actions[]] | sort | join(" ")')"
assert_eq "due the delay after its last write" "60000" "$(batches | jq '.[0].due - .[0].held')"

"$BOARD_CARD" flush --now >/dev/null
assert_eq "and nothing is read once board-card has committed them" "[]" "$(batches)"

finish
