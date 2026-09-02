#!/usr/bin/env bash

HOOKS="$(cd "$(dirname "$0")/.." && pwd)"

pass=0
fail=0

through() {
  local hook="$1" command="$2"
  jq -nc --arg command "$command" \
    '{tool_name:"Bash",tool_input:{command:$command}}' \
    | bash "$HOOKS/$hook" 2>/dev/null
}

verdict() {
  local output="$1"
  if printf '%s' "$output" | grep -qF '"permissionDecision":"allow"'; then
    printf 'allow'
  elif printf '%s' "$output" | grep -qF '"permissionDecision":"deny"'; then
    printf 'deny'
  else
    printf 'defer'
  fi
}

assert_verdict() {
  local label="$1" expected="$2" actual="$3"
  if [ "$actual" = "$expected" ]; then
    printf "  OK  %s\n" "$label"
    pass=$((pass + 1))
  else
    printf "  KO  %s — expected '%s', got '%s'\n" "$label" "$expected" "$actual"
    fail=$((fail + 1))
  fi
}

printf "Test group: a bare search inside the repo family is allowed, so it does not prompt\n"

assert_verdict "grep under the current worktree" "allow" \
  "$(verdict "$(through allow-family-search.sh 'grep --recursive todo agents')")"
assert_verdict "find under the current worktree" "allow" \
  "$(verdict "$(through allow-family-search.sh 'find agents -name "*.sh"')")"

printf "\nTest group: anything an allow could ride on defers instead\n"

assert_verdict "a pipe could carry a second command" "defer" \
  "$(verdict "$(through allow-family-search.sh 'grep --recursive todo agents | xargs rm')")"
assert_verdict "a chain could carry a second command" "defer" \
  "$(verdict "$(through allow-family-search.sh 'grep todo agents && rm -r agents')")"
assert_verdict "a redirect writes" "defer" \
  "$(verdict "$(through allow-family-search.sh 'grep todo agents > /tmp/out')")"
assert_verdict "find -exec executes" "defer" \
  "$(verdict "$(through allow-family-search.sh 'find agents -name "*.sh" -exec rm {} ;')")"
assert_verdict "find -delete mutates" "defer" \
  "$(verdict "$(through allow-family-search.sh 'find agents -name "*.sh" -delete')")"
assert_verdict "a path outside the family" "defer" \
  "$(verdict "$(through allow-family-search.sh 'grep --recursive todo /usr/local/lib')")"
assert_verdict "a command that is not a search" "defer" \
  "$(verdict "$(through allow-family-search.sh 'cat marketplace/plugins/cockpit/scripts/hooks/tab-status.sh')")"

printf "\nTest group: a secret stays refused, whatever this hook would have said about it\n"

assert_verdict "this hook would allow a search of a secret inside the family" "allow" \
  "$(verdict "$(through allow-family-search.sh 'grep --recursive TOKEN agents/.env')")"
assert_verdict "and the secret guard denies the very same command" "deny" \
  "$(verdict "$(through guard-bash-secret-read.sh 'grep --recursive TOKEN agents/.env')")"

printf "\n%d passed, %d failed\n" "$pass" "$fail"
[ "$fail" -eq 0 ]
