#!/usr/bin/env bash

repo_root_through_symlink() {
  cd "$(dirname "$0")" && cd "$(pwd -P)/../.." && pwd
}

REPO="$(repo_root_through_symlink)"
CONFIG="$REPO/.prettierrc"
BIOME="$REPO/agents/claude/biome.json"
HOOK="$REPO/agents/claude/hooks/format-on-edit.sh"

pass=0
fail=0

assert_ok() {
  printf "  OK  %s\n" "$1"
  pass=$((pass + 1))
}

assert_ko() {
  printf "  KO  %s — %s\n" "$1" "$2"
  fail=$((fail + 1))
}

assert_equal() {
  local label="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then
    assert_ok "$label"
  else
    assert_ko "$label" "expected $expected, got ${actual:-nothing}"
  fi
}

printf "Test group: the config turns prose wrapping off for markdown\n"

if [ -r "$CONFIG" ]; then
  assert_ok "the repo root carries a prettier config"
else
  assert_ko "the repo root carries a prettier config" "$CONFIG is missing"
  printf "\n%d passed, %d failed\n" "$pass" "$fail"
  exit 1
fi

markdown_option() {
  jq --raw-output --arg option "$1" \
    '[ .overrides[]? | select(.files == "*.md") | .options[$option] ] | first | tostring' \
    "$CONFIG"
}

assert_equal "and the markdown override never wraps prose" \
  "never" "$(markdown_option proseWrap)"
assert_equal "and leaves markdown indented with spaces" \
  "false" "$(markdown_option useTabs)"

printf "\nTest group: the config leaves everything else as biome writes it\n"

assert_equal "the top level indents with tabs, as biome does" \
  "$(jq --raw-output '.formatter.indentStyle == "tab"' "$BIOME")" \
  "$(jq --raw-output '.useTabs' "$CONFIG")"
assert_equal "and holds the same line width biome does" \
  "$(jq --raw-output '.formatter.lineWidth' "$BIOME")" \
  "$(jq --raw-output '.printWidth' "$CONFIG")"

printf "\nTest group: every tracked markdown file is already unwrapped\n"

prettier_version="$(sed -n 's/^prettier_version="\(.*\)"$/\1/p' "$HOOK")"
pinned_prettier="prettier@$prettier_version"

if printf '%s' "$prettier_version" | grep --quiet --extended-regexp -- '^[0-9]+\.[0-9]+\.[0-9]+$'; then
  assert_ok "the format hook pins one exact prettier version"
else
  assert_ko "the format hook pins one exact prettier version" "found '${prettier_version:-nothing}' in $HOOK"
  printf "\n%d passed, %d failed\n" "$pass" "$fail"
  exit 1
fi

cd "$REPO" || exit 1
if npx --yes --prefer-offline "$pinned_prettier" --version >/dev/null 2>&1 ||
  npx --yes --prefer-offline=false "$pinned_prettier" --version >/dev/null 2>&1; then
  assert_ok "and that version runs here"
else
  assert_ko "and that version runs here" "npx $pinned_prettier --version failed, so the check below proves nothing"
  printf "\n%d passed, %d failed\n" "$pass" "$fail"
  exit 1
fi

still_wrapped="$(git ls-files "*.md" | xargs npx --yes --prefer-offline "$pinned_prettier" --list-different 2>/dev/null)"

if [ -z "$still_wrapped" ]; then
  assert_ok "and the formatter has nothing left to rewrite"
else
  assert_ko "and the formatter has nothing left to rewrite" \
    "$(printf '%s' "$still_wrapped" | tr '\n' ' ')"
fi

printf "\n%d passed, %d failed\n" "$pass" "$fail"
[ "$fail" -eq 0 ]
