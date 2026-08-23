#!/usr/bin/env bash

HOOK="$(cd "$(dirname "$0")/.." && pwd)/guard-bash-secret-read.sh"

pass=0
fail=0

run_bash() {
  jq -nc --arg command "$1" \
    '{tool_name:"Bash",tool_input:{command:$command}}' \
    | bash "$HOOK" 2>/dev/null
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

printf "Test group: the readers the deny rules do not recognise are the ones this covers\n"

assert_denies "grep reads a secret file the deny rules would have caught for cat" \
  "$(run_bash 'grep SECRET .env')"
assert_denies "jq reads a credentials file" \
  "$(run_bash 'jq . credentials.json')"
assert_denies "rg reads a private key" \
  "$(run_bash 'rg BEGIN id_rsa')"
assert_denies "awk reads a certificate" \
  "$(run_bash 'awk "{print}" server.pem')"
assert_silent "cat is left to the deny rules, which already recognise it" \
  "$(run_bash 'cat .env')"

printf "\nTest group: a quoted span is a search pattern, not a file being read\n"

assert_silent "the secret name is the pattern, the file is not a secret" \
  "$(run_bash 'grep "\.env" README.md')"
assert_silent "a single-quoted pattern is stripped the same way" \
  "$(run_bash "grep '.npmrc' notes.txt")"
assert_denies "the same command with the secret unquoted is a read" \
  "$(run_bash 'grep TOKEN .npmrc')"

printf "\nTest group: a committed example file is readable by design\n"

assert_silent "the example env file" \
  "$(run_bash 'grep KEY .env.example')"
assert_silent "the template env file" \
  "$(run_bash 'grep KEY .env.template')"

printf "\nTest group: the match is coarse on purpose, and over-denies rather than under-denies\n"

assert_denies "a secret token anywhere in the command, not only as its last argument" \
  "$(run_bash 'grep --recursive TOKEN ~/.aws')"
assert_denies "a path that merely contains the secret token" \
  "$(run_bash 'ls deploy/credentials-backup')"

printf "\n%d passed, %d failed\n" "$pass" "$fail"
[ "$fail" -eq 0 ]
