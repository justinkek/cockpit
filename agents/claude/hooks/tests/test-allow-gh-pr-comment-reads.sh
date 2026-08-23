#!/usr/bin/env bash

HOOK="$(cd "$(dirname "$0")/.." && pwd)/allow-gh-pr-comment-reads.sh"

pass=0
fail=0

run_bash() {
  jq --null-input --compact-output --arg command "$1" \
    '{tool_name:"Bash",tool_input:{command:$command}}' \
    | bash "$HOOK" 2>/dev/null
}

assert_allows() {
  local label="$1" output="$2"
  if printf '%s' "$output" | grep --quiet --fixed-strings '"permissionDecision":"allow"'; then
    printf "  OK  %s\n" "$label"
    pass=$((pass + 1))
  else
    printf "  KO  %s — expected an allow, got '%s'\n" "$label" "$output"
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

review_threads_read='gh api graphql --paginate --field owner="$(gh repo view --json owner --jq .owner.login)" --raw-field query='"'"'query($owner:String!){repository(owner:$owner,name:"x"){pullRequest(number:1){reviewThreads(first:100){nodes{isResolved}}}}}'"'"' --jq .data'

printf "Test group: the read this hook exists to allow\n"

assert_allows "the review-thread query is allowed" \
  "$(run_bash "$review_threads_read")"
assert_allows "a REST get on a pull request endpoint is allowed" \
  "$(run_bash 'gh api repos/owner/name/pulls/1')"

printf "\nTest group: an allow auto-approves the whole command, so anything joined to the call defers\n"

assert_silent "a second line carrying the call is not allowed" \
  "$(run_bash 'rm -rf x
gh api repos/owner/name/pulls/1')"
assert_silent "a command in front of the call is not allowed" \
  "$(run_bash 'rm -rf x; gh api repos/owner/name/pulls/1')"
assert_silent "a pipe is not allowed" \
  "$(run_bash 'gh api repos/owner/name/pulls/1 | tee out.json')"
assert_silent "a redirect is not allowed" \
  "$(run_bash 'gh api repos/owner/name/pulls/1 > out.json')"

printf "\nTest group: a call that writes is left to the guard\n"

assert_silent "a mutation is not allowed" \
  "$(run_bash "gh api graphql --raw-field query='mutation{addComment(input:{body:\"x\"}){clientMutationId}}'")"
assert_silent "a write method is not allowed" \
  "$(run_bash 'gh api --method DELETE repos/owner/name/issues/1')"
assert_silent "an endpoint outside pull requests and issue comments is not allowed" \
  "$(run_bash 'gh api repos/owner/name/branches')"

printf "\n%d passed, %d failed\n" "$pass" "$fail"
[ "$fail" -eq 0 ]
