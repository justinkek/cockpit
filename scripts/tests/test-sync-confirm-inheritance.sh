#!/usr/bin/env bash
#
# Test: a concern folder inherits confirm() from the orchestrator.
#
# A throwaway tree is built with a probe concern that calls confirm() without
# sourcing anything, so every assertion is about what the orchestrator hands
# its workers — the real concern folders are never run.

# pwd -P, so the repo still resolves when run through the ~/.scripts symlink.
REPO="$(cd "$(dirname "$0")" && cd "$(pwd -P)/../.." && pwd)"
ORCHESTRATOR="$REPO/agents/claude/sync.sh"
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

pass=0
fail=0

# A tree shaped like agents/claude: the orchestrator plus concern subfolders.
TREE="$TMPDIR/tree"
mkdir -p "$TREE"
cp "$ORCHESTRATOR" "$TREE/sync.sh"

# Stands in for ~/.agents-shared, so the probe inherits the real confirm().
export AGENTS_SHARED_DIR="$TMPDIR/shared"
mkdir -p "$AGENTS_SHARED_DIR"
cp "$REPO/agents/shared/prompts.sh" "$AGENTS_SHARED_DIR/prompts.sh"

# A new concern, written the way the convention says: it calls confirm() and
# sources nothing. Writing $MARKER is its stand-in for applying a config.
write_concern() {
  local name="$1"
  mkdir -p "$TREE/$name"
  cat > "$TREE/$name/sync.$name.sh" <<'CONCERN'
#!/usr/bin/env bash
set -euo pipefail
[ "${1:-}" = "--check" ] && exit 0
if ! confirm "    " "apply?"; then
  echo "    skipped"
  exit 0
fi
printf 'applied\n' >> "$MARKER"
CONCERN
}

# Runs the orchestrator with no terminal, leaving its output in $output, the
# exit code in $status, and whatever the concern wrote in $applied.
run_sync() {
  : > "$MARKER"
  output="$(MARKER="$MARKER" bash "$TREE/sync.sh" "$@" 2>&1 < /dev/null)"
  status=$?
  applied="$(cat "$MARKER")"
}

MARKER="$TMPDIR/applied.log"
write_concern probe

assert_applied() {
  local label="$1"
  if [ -n "$applied" ]; then
    printf "  OK  %s\n" "$label"
    pass=$((pass + 1))
  else
    printf "  KO  %s — nothing applied, output: %s\n" "$label" "$output"
    fail=$((fail + 1))
  fi
}

assert_not_applied() {
  local label="$1"
  if [ -z "$applied" ]; then
    printf "  OK  %s\n" "$label"
    pass=$((pass + 1))
  else
    printf "  KO  %s — applied when it should not have\n" "$label"
    fail=$((fail + 1))
  fi
}

assert_status() {
  local label="$1" expected="$2"
  if [ "$status" -eq "$expected" ]; then
    printf "  OK  %s\n" "$label"
    pass=$((pass + 1))
  else
    printf "  KO  %s — exit %s, expected %s\n" "$label" "$status" "$expected"
    fail=$((fail + 1))
  fi
}

printf "Test group: a concern that sources nothing still gets the gate\n"

run_sync --apply
assert_applied "an unattended run applies instead of silently skipping"
assert_status "and exits clean" 0

run_sync --check
assert_not_applied "--check still writes nothing"

printf "\nTest group: a second concern needs no wiring either\n"

write_concern twin
run_sync --apply
assert_applied "both concerns run off one export"
assert_status "and the run exits clean" 0

printf "\nTest group: naming a concern runs only that one\n"

run_sync probe --apply
assert_applied "the named concern applies"
assert_status "and exits clean" 0

run_sync nosuch --apply
assert_not_applied "an unknown concern applies nothing"
assert_status "and fails loudly" 1

printf "\n%d passed, %d failed\n" "$pass" "$fail"
[ "$fail" -eq 0 ]
