#!/usr/bin/env bash

HOOK="$(cd "$(dirname "$0")/.." && pwd)/guard-shell-readability.sh"

pass=0
fail=0

run_bash() {
  jq -nc --arg command "$1" \
    '{tool_name:"Bash",tool_input:{command:$command}}' | "$HOOK" 2>/dev/null
}

run_write() {
  jq -nc --arg path "$1" --arg content "$2" \
    '{tool_name:"Write",tool_input:{file_path:$path,content:$content}}' | "$HOOK" 2>/dev/null
}

run_edit() {
  jq -nc --arg path "$1" --arg old "$2" --arg new "$3" \
    '{tool_name:"Edit",tool_input:{file_path:$path,old_string:$old,new_string:$new}}' | "$HOOK" 2>/dev/null
}

assert_denies() {
  local label="$1" output="$2"
  if printf '%s' "$output" | grep -qF '"permissionDecision":"deny"'; then
    printf "  OK  %s\n" "$label"
    pass=$((pass + 1))
  else
    printf "  KO  %s — expected a deny, got '%s'\n" "$label" "$output"
    fail=$((fail + 1))
  fi
}

assert_silent() {
  local label="$1" output="$2"
  if [ -z "$output" ]; then
    printf "  OK  %s\n" "$label"
    pass=$((pass + 1))
  else
    printf "  KO  %s — expected silence, got '%s'\n" "$label" "$output"
    fail=$((fail + 1))
  fi
}

printf "Test group: short-form options are denied\n"

assert_denies "clustered option on curl" \
  "$(run_bash 'curl -sS https://example.dev')"
assert_denies "the jq options from the review" \
  "$(run_bash 'jq -rn --arg c "$cursor" @uri')"
assert_denies "single-letter option on git" \
  "$(run_bash 'git commit -m "a message"')"
assert_denies "short option inside a written script" \
  "$(run_write /tmp/probe.sh '#!/usr/bin/env bash
gh pr view -q .url')"

printf "\nTest group: shortened variable names are denied\n"

assert_denies "the assignment from the review" \
  "$(run_write /tmp/probe.sh '#!/usr/bin/env bash
enc=$(printf %s "$cursor")')"
assert_denies "a local declaration" \
  "$(run_write /tmp/probe.sh '#!/usr/bin/env bash
readable() { local cmd=$1; printf "%s" "$cmd"; }')"
assert_denies "an assignment in a one-off command" \
  "$(run_bash 'tmp=/tmp/out')"

printf "\nTest group: shell with no long form must never be denied\n"

assert_silent "wc rejects a long option outright" \
  "$(run_bash 'wc -l /tmp/probe.sh')"
assert_silent "sed rejects a long option outright" \
  "$(run_bash 'sed -n 1p /tmp/probe.sh')"
assert_silent "tr rejects a long option outright" \
  "$(run_bash 'printf a | tr -d a')"
assert_silent "cut rejects a long option outright" \
  "$(run_bash 'cut -c1 /tmp/probe.sh')"
assert_silent "ls rejects a long option outright" \
  "$(run_bash 'ls -la /tmp')"
assert_silent "comm rejects a long option outright" \
  "$(run_bash 'comm -23 /tmp/one /tmp/two')"
assert_silent "basename rejects a long option outright" \
  "$(run_bash 'basename -s .sh /tmp/probe.sh')"
assert_silent "a test operator is not an option" \
  "$(run_write /tmp/probe.sh '#!/usr/bin/env bash
if [ -n "$value" ]; then printf "%s" "$value"; fi')"
assert_silent "a builtin option is not a command option" \
  "$(run_write /tmp/probe.sh '#!/usr/bin/env bash
set -f
export -f readable')"
assert_silent "git -C has no long form" \
  "$(run_bash 'git -C /tmp/repo status')"

printf "\nTest group: readable shell stays silent\n"

assert_silent "long-form options throughout" \
  "$(run_bash 'git commit --message "a message"')"
assert_silent "whole-word variable names" \
  "$(run_write /tmp/probe.sh '#!/usr/bin/env bash
encoded=$(printf %s "$cursor")')"
assert_silent "a short option quoted as data, not run" \
  "$(run_bash 'printf "%s" "curl -sS"')"

printf "\nTest group: out of scope stays silent\n"

assert_silent "a non-shell file" \
  "$(run_write /tmp/probe.ts 'const enc = 1;')"
assert_silent "a markdown file documenting a short option" \
  "$(run_write /tmp/probe.md 'Run `curl -sS` to fetch it.')"
assert_silent "a tool that carries no shell" \
  "$(jq -nc '{tool_name:"Read",tool_input:{file_path:"/tmp/probe.sh"}}' | bash "$HOOK" 2>/dev/null)"
assert_silent "an edit that removes the offence" \
  "$(run_edit /tmp/probe.sh 'enc=1' 'encoded=1')"

printf "\nTest group: only what the edit adds counts\n"

assert_silent "an existing offence carried past unchanged" \
  "$(run_edit /tmp/probe.sh 'jq -nc "{}"
value=1' 'jq -nc "{}"
value=2')"
assert_silent "an existing short name re-indented, not added" \
  "$(run_edit /tmp/probe.sh 'cmd=$1' '  cmd=$1')"
assert_denies "a second offence added beside an existing one" \
  "$(run_edit /tmp/probe.sh 'jq -nc "{}"' 'jq -nc "{}"
git commit -m "a message"')"

printf "\n%d passed, %d failed\n" "$pass" "$fail"
[ "$fail" -eq 0 ]
