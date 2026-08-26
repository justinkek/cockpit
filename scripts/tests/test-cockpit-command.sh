#!/usr/bin/env bash

REPO="$(cd "$(dirname "$0")" && cd "$(pwd -P)/../.." && pwd)"
LAUNCHER="$REPO/agents/claude/bin/cockpit"
TEMP="$(mktemp -d)"
trap 'rm -rf "$TEMP"' EXIT

pass=0
fail=0

mkdir -p "$TEMP/bin" "$TEMP/home" "$TEMP/repo" "$TEMP/bare"
printf '%s\n' '#!/usr/bin/env bash' 'printf "%s\n%s\n" "$CLAUDE_CONFIG_DIR" "$*"' > "$TEMP/bin/claude"
chmod +x "$TEMP/bin/claude"
git -C "$TEMP/repo" init --quiet

run_in() { ( cd "$1" && shift && PATH="$TEMP/bin:$PATH" HOME="$TEMP/home" bash "$LAUNCHER" "$@" ); }

assert_equal() {
  local label="$1" actual="$2" expected="$3"
  if [ "$actual" = "$expected" ]; then
    printf "  OK  %s\n" "$label"
    pass=$((pass + 1))
  else
    printf "  KO  %s — got '%s', expected '%s'\n" "$label" "$actual" "$expected"
    fail=$((fail + 1))
  fi
}

assert_status() {
  local label="$1" actual="$2" expected="$3"
  if [ "$actual" -eq "$expected" ]; then
    printf "  OK  %s\n" "$label"
    pass=$((pass + 1))
  else
    printf "  KO  %s — exit %s, expected %s\n" "$label" "$actual" "$expected"
    fail=$((fail + 1))
  fi
}

assert_executable() {
  local label="$1" path="$2"
  if [ -x "$path" ]; then
    printf "  OK  %s\n" "$label"
    pass=$((pass + 1))
  else
    printf "  KO  %s — %s carries no executable bit\n" "$label" "$path"
    fail=$((fail + 1))
  fi
}

output="$(run_in "$TEMP/repo" --resume last)"
{ read -r directory; read -r arguments; } <<< "$output"

printf "Test group: inside a repo the command launches claude against the cockpit profile\n"

assert_equal "it points claude at the cockpit profile" "$directory" "$TEMP/home/.claude-cockpit"
assert_equal "it passes every argument on" "$arguments" "--resume last"
assert_executable "a clone can run the launcher without chmod" "$LAUNCHER"

printf "\nTest group: outside a repo it refuses, and the bypass still runs\n"

run_in "$TEMP/bare" >/dev/null 2>&1
assert_status "it refuses with nothing tracking the edits" "$?" 1

CLAUDE_ALLOW_NONREPO=1 run_in "$TEMP/bare" >/dev/null 2>&1
assert_status "the bypass launches anyway" "$?" 0

printf "\n%d passed, %d failed\n" "$pass" "$fail"
[ "$fail" -eq 0 ]
