#!/usr/bin/env bash

LIBRARY="$(cd "$(dirname "$0")/.." && pwd)/hook-argv-lib.sh"
. "$LIBRARY"

pass=0
fail=0

assert_equal() {
  local label="$1" expected="$2" actual="$3"
  if [ "$actual" = "$expected" ]; then
    printf "  OK  %s\n" "$label"
    pass=$((pass + 1))
  else
    printf "  KO  %s — expected '%s', got '%s'\n" "$label" "$expected" "$actual"
    fail=$((fail + 1))
  fi
}

printf "Test group: a hook sources the library and gets these two calls\n"

assert_equal "hook_argv_after prints one argument per line" \
  "ticket
feature" \
  "$(hook_argv_after '"$HOME/.cockpit/scripts/ticket-register-type" ticket feature' ticket-register-type)"

assert_equal "hook_argv_after reads an unquoted argument too" \
  "feature" \
  "$(hook_argv_after '$HOME/.cockpit/scripts/ticket-register-type feature' ticket-register-type)"

assert_equal "hook_argv_after starts at the command token, not a later mention" \
  "feature" \
  "$(hook_argv_after '"$HOME/.cockpit/scripts/ticket-register-type" feature' ticket-register-type)"

assert_equal "hook_is_readonly_bash says yes to a command that only reads" \
  "yes" \
  "$(hook_is_readonly_bash 'cat /tmp/nothing' && printf yes || printf no)"

assert_equal "hook_is_readonly_bash says no to a command that writes" \
  "no" \
  "$(hook_is_readonly_bash 'rm /tmp/nothing' && printf yes || printf no)"

assert_equal "hook_argv_segments prints one line per invocation" \
  "gh pr view
gh api repos/owner/name/pulls" \
  "$(hook_argv_segments 'gh pr view; gh api repos/owner/name/pulls')"

assert_equal "hook_argv_segments drops a cd prefix" \
  "gh api repos/owner/name/pulls" \
  "$(hook_argv_segments 'cd /repo && gh api repos/owner/name/pulls')"

assert_equal "hook_argv_segments drops a leading assignment" \
  "gh api repos/owner/name/pulls" \
  "$(hook_argv_segments 'GH_TOKEN=x gh api repos/owner/name/pulls')"

assert_equal "hook_argv_segments does not eat the next invocation after a bare cd" \
  "gh api repos/owner/name/pulls" \
  "$(hook_argv_segments 'cd && gh api repos/owner/name/pulls')"

assert_equal "hook_argv_segments keeps a quoted operator inside its invocation" \
  "gh api graphql --raw-field query=query{viewer{login}}" \
  "$(hook_argv_segments "gh api graphql --raw-field query='query{viewer{login}}'")"

printf "\n%d passed, %d failed\n" "$pass" "$fail"
[ "$fail" -eq 0 ]
