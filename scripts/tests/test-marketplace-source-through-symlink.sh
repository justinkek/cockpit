#!/usr/bin/env bash

repo_root_through_symlink() {
  cd "$(dirname "$0")" && cd "$(pwd -P)/../.." && pwd
}

REPO="$(repo_root_through_symlink)"
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

mkdir -p "$TMPDIR/checkout"
CHECKOUT="$(cd "$TMPDIR/checkout" && pwd -P)"
mkdir -p "$CHECKOUT/agents/claude/plugins" "$CHECKOUT/marketplace"
printf '{"marketplaces":{"cockpit":"./marketplace"},"plugins":{}}\n' \
  > "$CHECKOUT/agents/claude/plugins/base.plugins.json"
ln -s "$CHECKOUT/agents/claude" "$TMPDIR/claude-shared"

resolve_through() {
  CLAUDE_PLUGINS_MANIFEST="$1/plugins/base.plugins.json" \
    bash -c '
      MANIFEST="$CLAUDE_PLUGINS_MANIFEST"
      source_is_repository_relative() { case "$1" in ./*) return 0 ;; *) return 1 ;; esac; }
      '"$(sed -n '/^marketplace_source_path()/,/^}/p' "$REPO/agents/claude/plugins/sync.plugins.sh")"'
      marketplace_source_path "./marketplace"
    '
}

printf "Test group: a repository-relative source resolves through the symlink it was reached by\n"

assert_eq "the real path answers" "$CHECKOUT/marketplace" \
  "$(resolve_through "$CHECKOUT/agents/claude")"
assert_eq "and so does the symlinked one" "$CHECKOUT/marketplace" \
  "$(resolve_through "$TMPDIR/claude-shared")"

printf "\nTest group: a source that names no directory is refused\n"

rm -rf "$CHECKOUT/marketplace"
resolve_through "$TMPDIR/claude-shared" >/dev/null 2>&1
assert_eq "the resolver exits non-zero" "1" "$?"

printf "\n%d passed, %d failed\n" "$pass" "$fail"
[ "$fail" -eq 0 ]
