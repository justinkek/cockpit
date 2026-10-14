#!/usr/bin/env bash

HOOK="$(cd "$(dirname "$0")/.." && pwd)/format-on-edit.sh"

TEMPORARY_DIRECTORY="$(cd "$(mktemp -d)" && pwd -P)"
trap 'rm -rf "$TEMPORARY_DIRECTORY"' EXIT

STUBS="$TEMPORARY_DIRECTORY/stubs"
CALLS="$TEMPORARY_DIRECTORY/calls"

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

assert_empty() {
  local label="$1" actual="$2"
  if [ -z "$actual" ]; then
    assert_ok "$label"
  else
    assert_ko "$label" "got '$actual'"
  fi
}

assert_contains() {
  local label="$1" needle="$2" haystack="$3"
  if printf '%s' "$haystack" | grep --quiet --fixed-strings -- "$needle"; then
    assert_ok "$label"
  else
    assert_ko "$label" "'$needle' is not in '${haystack:-nothing}'"
  fi
}

assert_matches() {
  local label="$1" pattern="$2" haystack="$3"
  if printf '%s' "$haystack" | grep --quiet --extended-regexp -- "$pattern"; then
    assert_ok "$label"
  else
    assert_ko "$label" "'${haystack:-nothing}' does not match $pattern"
  fi
}

write_prettier_stub() {
  local path="$1"
  mkdir -p "$(dirname "$path")"
  cat > "$path" <<'STUB'
#!/usr/bin/env bash
printf '%s %s\n' "$0" "$*" >> "$FORMAT_CALLS"
target="${!#}"
case "$target" in
  *broken*) exit 2 ;;
  *stale*)
    case " $* " in
      *" --prefer-offline "*) exit 1 ;;
    esac
    ;;
esac
case " $* " in
  *" --ignore-unknown "*) exit 0 ;;
esac
case "$target" in
  *.md|*.mdx|*.json|*.ts) exit 0 ;;
esac
exit 2
STUB
  chmod +x "$path"
}

make_repository() {
  local path="$1"
  mkdir -p "$path"
  git init --quiet --initial-branch=main "$path"
}

warnings_from_edit() {
  local path="$1"
  : > "$CALLS"
  jq --null-input --compact-output --arg path "$path" \
    '{tool_name:"Edit",tool_input:{file_path:$path,old_string:"a",new_string:"b"}}' \
    | PATH="$STUBS:$PATH" FORMAT_CALLS="$CALLS" bash "$HOOK" 2>&1 >/dev/null
}

pinned_spec() {
  grep --only-matching --extended-regexp -- 'prettier@[^ ]+' "$CALLS" | head -n 1
}

write_prettier_stub "$STUBS/npx"
printf '#!/usr/bin/env bash\nexit 1\n' > "$STUBS/mise"
chmod +x "$STUBS/mise"

PRETTIER_PROJECT="$TEMPORARY_DIRECTORY/prettier-project"
make_repository "$PRETTIER_PROJECT"
printf '{}\n' > "$PRETTIER_PROJECT/.prettierrc"
printf '* text=auto\n' > "$PRETTIER_PROJECT/.gitattributes"
printf '{}\n' > "$PRETTIER_PROJECT/broken.json"
printf '{}\n' > "$PRETTIER_PROJECT/stale.json"

PLAIN_PROJECT="$TEMPORARY_DIRECTORY/plain-project"
make_repository "$PLAIN_PROJECT"
printf '# Notes\n' > "$PLAIN_PROJECT/notes.md"

INSTALLED_PROJECT="$TEMPORARY_DIRECTORY/installed-project"
make_repository "$INSTALLED_PROJECT"
printf '{}\n' > "$INSTALLED_PROJECT/.prettierrc"
mkdir -p "$INSTALLED_PROJECT/packages/web/src"
printf 'export {}\n' > "$INSTALLED_PROJECT/packages/web/src/app.ts"
printf '# Readme\n' > "$INSTALLED_PROJECT/packages/web/README.md"
write_prettier_stub "$INSTALLED_PROJECT/node_modules/.bin/prettier"

printf "Test group: a file prettier has no parser for is left alone without a warning\n"

warnings="$(warnings_from_edit "$PRETTIER_PROJECT/.gitattributes")"
calls="$(cat "$CALLS")"
assert_empty "an edit to .gitattributes under a .prettierrc prints no warning" "$warnings"
assert_contains "prettier is told to skip a file it cannot parse" "--ignore-unknown" "$calls"

printf "\nTest group: where the project declares no prettier, one exact version runs and the cache is read first\n"

assert_contains "the fallback runs through npx" "$STUBS/npx " "$calls"
non_markdown_spec="$(pinned_spec)"
assert_matches "the fallback names an exact version" '^prettier@[0-9]+\.[0-9]+\.[0-9]+$' "$non_markdown_spec"
assert_contains "the fallback reads the npm cache before the registry" "--prefer-offline" "$calls"
assert_contains "the fallback never waits on an install prompt" "--yes" "$calls"

warnings="$(warnings_from_edit "$PLAIN_PROJECT/notes.md")"
calls="$(cat "$CALLS")"
assert_empty "a markdown edit prints no warning" "$warnings"
assert_contains "the markdown call skips a file it cannot parse too" "--ignore-unknown" "$calls"
if [ -n "$non_markdown_spec" ] && [ "$(pinned_spec)" = "$non_markdown_spec" ]; then
  assert_ok "the markdown call names the same version as the other call"
else
  assert_ko "the markdown call names the same version as the other call" \
    "markdown ran '$(pinned_spec)', the other call ran '$non_markdown_spec'"
fi

printf "\nTest group: a prettier the project installed wins over the pinned one\n"

warnings="$(warnings_from_edit "$INSTALLED_PROJECT/packages/web/src/app.ts")"
calls="$(cat "$CALLS")"
assert_empty "an edit in a nested package prints no warning" "$warnings"
assert_contains "the repository's own prettier runs" "$INSTALLED_PROJECT/node_modules/.bin/prettier --ignore-unknown --write" "$calls"
if grep --quiet --fixed-strings -- "$STUBS/npx" "$CALLS"; then
  assert_ko "npx is not reached" "$calls"
else
  assert_ok "npx is not reached"
fi

warnings_from_edit "$INSTALLED_PROJECT/packages/web/README.md" >/dev/null
calls="$(cat "$CALLS")"
assert_contains "a markdown edit there uses the repository's own prettier too" "$INSTALLED_PROJECT/node_modules/.bin/prettier --ignore-unknown --write" "$calls"

printf "\nTest group: a cache that predates the pinned version is refreshed rather than failing every edit\n"

warnings="$(warnings_from_edit "$PRETTIER_PROJECT/stale.json")"
assert_empty "an edit whose cached packument lacks the pin prints no warning" "$warnings"
assert_contains "the first call reads the cache" "$STUBS/npx --yes --prefer-offline prettier@" "$(sed -n 1p "$CALLS")"
assert_contains "and the second asks the registry for the same version" "$STUBS/npx --yes --prefer-offline=false $non_markdown_spec " "$(sed -n 2p "$CALLS")"

printf "\nTest group: a prettier that fails is still reported\n"

warnings="$(warnings_from_edit "$PRETTIER_PROJECT/broken.json")"
assert_contains "a failed format names the file" "prettier format failed for $PRETTIER_PROJECT/broken.json" "$warnings"
calls_made="$(grep --count --fixed-strings -- "$STUBS/npx" "$CALLS")"
if [ "$calls_made" -eq 1 ]; then
  assert_ok "a file prettier refused is not fetched again from the registry"
else
  assert_ko "a file prettier refused is not fetched again from the registry" "npx ran $calls_made times"
fi

printf "\n%d passed, %d failed\n" "$pass" "$fail"
[ "$fail" -eq 0 ]
