#!/usr/bin/env bash

repo_root_through_symlink() {
  cd "$(dirname "$0")" && cd "$(pwd -P)/../.." && pwd
}

REPO="$(repo_root_through_symlink)"
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

pass=0
fail=0

ok() {
  printf "  OK  %s\n" "$1"
  pass=$((pass + 1))
}

ko() {
  printf "  KO  %s — %s\n" "$1" "$2"
  fail=$((fail + 1))
}

assert_absent() {
  local label="$1" file="$2" phrase="$3"
  if grep --quiet --fixed-strings "$phrase" "$file"; then
    ko "$label" "'$phrase' is still in $file"
  else
    ok "$label"
  fi
}

assert_contains() {
  local label="$1" file="$2" phrase="$3"
  if grep --quiet --fixed-strings "$phrase" "$file"; then
    ok "$label"
  else
    ko "$label" "'$phrase' is not in $file"
  fi
}

AGENTS_SHARED="$TMPDIR/agents-shared"
mkdir -p "$AGENTS_SHARED"
cp "$REPO/agents/shared/base.AGENTS.md" "$AGENTS_SHARED/base.AGENTS.md"
cp "$REPO/agents/shared/board.AGENTS.md" "$AGENTS_SHARED/board.AGENTS.md"
cp "$REPO/agents/shared/prompts.sh" "$AGENTS_SHARED/prompts.sh"

# The overlay lives beside homes.sh, so a run that needs one gets its own copy
# of agents/codex rather than writing into the checkout.
codex_tree_with_overlay() {
  local dest="$1" overlay="$2"
  cp -R "$REPO/agents/codex" "$dest"
  printf '%s\n' "$overlay" > "$dest/homes.local.sh"
  printf '%s' "$dest"
}

run_agents_md() {
  local codex_dir="$1" probe_home="$2"
  mkdir -p "$probe_home"
  AGENTS_SHARED_DIR="$AGENTS_SHARED" HOME="$probe_home" \
    bash "$codex_dir/sync.sh" agents-md --apply > "$TMPDIR/apply.out" 2>&1 < /dev/null
}

printf "Test group: the default sync leaves the home an unwrapped launch lands in alone\n"

DEFAULT_HOME="$TMPDIR/default-home"
run_agents_md "$REPO/agents/codex" "$DEFAULT_HOME"

if [ -e "$DEFAULT_HOME/.codex" ]; then
  ko "nothing is written to ~/.codex" "$DEFAULT_HOME/.codex exists"
else
  ok "nothing is written to ~/.codex"
fi

WRAPPED="$DEFAULT_HOME/.codex-cockpit/AGENTS.md"
if [ -f "$WRAPPED" ]; then
  ok "and ~/.codex-cockpit is still synced"
else
  ko "and ~/.codex-cockpit is still synced" "$WRAPPED was not written"
  cat "$TMPDIR/apply.out"
fi

assert_contains "the default home list names the wrapped home" \
  "$REPO/agents/codex/homes.sh" "CODEX_HOMES=(codex-cockpit)"

printf "\nTest group: the home a wrapper points at gets the board\n"

if [ -f "$WRAPPED" ]; then
  assert_contains "the ticket registration rule" "$WRAPPED" "Cockpit URL-first"
  assert_contains "the claim lock rule" "$WRAPPED" "## Claim locks"
  assert_contains "and the writing rules too" "$WRAPPED" "## Solution ladder"
else
  ko "the wrapped home has an AGENTS.md to check" "$WRAPPED is missing"
fi

printf "\nTest group: an overlay that adds the unwrapped home still gets it no board\n"

OVERLAY_TREE="$(codex_tree_with_overlay "$TMPDIR/codex-with-desktop" 'CODEX_HOMES=(codex codex-cockpit)')"
OVERLAY_HOME="$TMPDIR/overlay-home"
run_agents_md "$OVERLAY_TREE" "$OVERLAY_HOME"

UNWRAPPED="$OVERLAY_HOME/.codex/AGENTS.md"
if [ -f "$UNWRAPPED" ]; then
  ok "the overlay puts the unwrapped home back in the list"
  assert_absent "no ticket registration rule" "$UNWRAPPED" "Cockpit URL-first"
  assert_absent "no claim lock rule" "$UNWRAPPED" "## Claim locks"
  assert_contains "and it keeps the writing rules" "$UNWRAPPED" "## Solution ladder"
else
  ko "the overlay puts the unwrapped home back in the list" "$UNWRAPPED was not written"
  cat "$TMPDIR/apply.out"
fi

printf "\nTest group: the wrapper that runs with none of this is refused\n"

VANILLA_TREE="$(codex_tree_with_overlay "$TMPDIR/codex-vanilla" 'CODEX_HOMES=(codex-vanilla)')"
VANILLA_HOME="$TMPDIR/vanilla-home"
mkdir -p "$VANILLA_HOME"
if AGENTS_SHARED_DIR="$AGENTS_SHARED" HOME="$VANILLA_HOME" \
     bash "$VANILLA_TREE/sync.sh" agents-md --apply > "$TMPDIR/vanilla.out" 2>&1 < /dev/null; then
  ko "a home list naming codex-vanilla fails" "the sync exited 0"
else
  ok "a home list naming codex-vanilla fails"
fi

if [ -e "$VANILLA_HOME/.codex-vanilla" ]; then
  ko "and writes nothing to ~/.codex-vanilla" "$VANILLA_HOME/.codex-vanilla exists"
else
  ok "and writes nothing to ~/.codex-vanilla"
fi

printf "\nTest group: a worker reached outside the orchestrator refuses\n"

for worker in agents-md/sync.agents-md.sh settings/sync.settings.sh; do
  BARE_HOME="$TMPDIR/bare-home-$(basename "$(dirname "$worker")")"
  mkdir -p "$BARE_HOME"
  if env -u CODEX_HOME -u CODEX_HOME_NAME \
       AGENTS_SHARED_DIR="$AGENTS_SHARED" HOME="$BARE_HOME" BASH_ENV="$AGENTS_SHARED/prompts.sh" \
       bash "$REPO/agents/codex/$worker" --apply --yes > "$TMPDIR/bare.out" 2>&1 < /dev/null; then
    ko "$worker fails without CODEX_HOME" "it exited 0"
  else
    ok "$worker fails without CODEX_HOME"
  fi

  if [ -e "$BARE_HOME/.codex" ]; then
    ko "and writes nothing to ~/.codex" "$BARE_HOME/.codex exists"
  else
    ok "and writes nothing to ~/.codex"
  fi
done

printf "\nTest group: the ticket gate is in the board hooks profile alone\n"

assert_absent "the shared profile does not require a ticket" \
  "$REPO/agents/codex/settings/base.hooks-profile.toml" "require-ticket.sh"
assert_contains "the board profile does" \
  "$REPO/agents/codex/settings/board.hooks-profile.toml" "require-ticket.sh"
assert_contains "and the shared profile keeps the secret guard" \
  "$REPO/agents/codex/settings/base.hooks-profile.toml" "guard-bash-secret-read.sh"

printf "\n%d passed, %d failed\n" "$pass" "$fail"
[ "$fail" -eq 0 ]
