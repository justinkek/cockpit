#!/usr/bin/env bash

repo_root_through_symlink() {
  cd "$(dirname "$0")" && cd "$(pwd -P)/../.." && pwd
}

REPO="$(repo_root_through_symlink)"
CONFIG="$REPO/.prettierrc"

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

cd "$REPO" || exit 1

code_width="$(jq --raw-output '.printWidth' "$CONFIG")"
markdown_width="$(jq --raw-output '[ .overrides[]? | select(.files == "*.md") | .options.printWidth ] | first' "$CONFIG")"

printf "Test group: markdown gets a line wide enough for a table to pad\n"

if [ "$markdown_width" = "null" ]; then
  assert_ko "the markdown override sets its own printWidth" \
    "it has none, so a table wider than $code_width comes back in the one-dash form"
elif [ "$markdown_width" -gt "$code_width" ]; then
  assert_ok "the markdown override sets a printWidth above the $code_width every other file gets"
else
  assert_ko "the markdown override sets a printWidth above the $code_width every other file gets" \
    "it is $markdown_width"
fi

printf "\nTest group: a fenced code block in markdown still fits the narrow width\n"

over_width="$(git ls-files "*.md" | xargs awk -v limit="$code_width" '
  FNR == 1 { inside = 0 }
  {
    stripped = $0
    sub(/^[ \t]+/, "", stripped)
    if (stripped ~ /^```/) {
      if (inside) { inside = 0; next }
      language = stripped
      sub(/^```/, "", language)
      if (language ~ /^(json|ts|tsx|js|jsx|mjs|cjs|css|scss|less|yaml|yml|html|graphql|markdown)$/) inside = 1
      next
    }
    if (inside && length($0) > limit) print FILENAME ":" FNR " (" length($0) " characters)"
  }
')"

if [ -z "$over_width" ]; then
  assert_ok "no block prettier formats holds a line past $code_width"
else
  assert_ko "no block prettier formats holds a line past $code_width" \
    "$(printf '%s' "$over_width" | tr '\n' ' ')"
fi

printf "\n%d passed, %d failed\n" "$pass" "$fail"
[ "$fail" -eq 0 ]
