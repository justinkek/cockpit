#!/usr/bin/env bash

HOOK="$(cd "$(dirname "$0")/.." && pwd)/guard-gh-api.sh"

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

assert_contains() {
  local label="$1" expected="$2" haystack="$3"
  if printf '%s' "$haystack" | grep -qF -- "$expected"; then
    printf "  OK  %s\n" "$label"
    pass=$((pass + 1))
  else
    printf "  KO  %s — expected '%s' in '%s'\n" "$label" "$expected" "$haystack"
    fail=$((fail + 1))
  fi
}

read_copied_verbatim_from_the_cr_comments_skill='gh api graphql --paginate --field owner="$(gh repo view --json owner --jq .owner.login)" --field repo="$(gh repo view --json name --jq .name)" --field number="$(gh pr view --json number --jq .number)" --raw-field query='"'"'query($owner:String!,$repo:String!,$number:Int!,$endCursor:String){repository(owner:$owner,name:$repo){pullRequest(number:$number){reviewThreads(first:100, after:$endCursor){pageInfo{hasNextPage endCursor} nodes{isResolved path line comments(first:100){nodes{author{login} body url}}}}}}}'"'"' --jq .data'

printf "Test group: a read query is left to the hook that allows it\n"

assert_silent "the review-comments skill's own read is not refused" \
  "$(run_bash "$read_copied_verbatim_from_the_cr_comments_skill")"
assert_silent "a read query in its shortest form" \
  "$(run_bash "gh api graphql --raw-field query='query{viewer{login}}'")"
assert_silent "a plain GET is untouched" \
  "$(run_bash 'gh api repos/owner/name/pulls/1')"

printf "\nTest group: a graphql call that writes, or cannot be read, is still refused\n"

assert_denies "a mutation is refused" \
  "$(run_bash "gh api graphql --raw-field query='mutation{addComment(input:{body:\"x\"}){clientMutationId}}'")"
assert_denies "a mutation spelled in capitals is refused" \
  "$(run_bash "gh api graphql --raw-field query='MUTATION{addComment}'")"
assert_denies "a query read from a file cannot be inspected, so it is refused" \
  "$(run_bash 'gh api graphql --raw-field query=@query.graphql')"
assert_denies "the word is matched anywhere, so a field named after it over-refuses" \
  "$(run_bash "gh api graphql --raw-field query='query{repository{mutationCount}}'")"

printf "\nTest group: the rules the exemption must not have loosened\n"

assert_denies "a write method is refused" \
  "$(run_bash 'gh api --method POST repos/owner/name/issues')"
assert_denies "body parameters on a REST call are refused" \
  "$(run_bash 'gh api repos/owner/name/issues --field title=x')"

printf "\nTest group: a refusal names the form that is allowed\n"

assert_contains "the body-parameter refusal names read-only graphql" "read-only graphql query" \
  "$(run_bash 'gh api repos/owner/name/issues --field title=x')"
assert_contains "the method refusal names read-only graphql" "read-only graphql query" \
  "$(run_bash 'gh api --method POST repos/owner/name/issues')"

printf "\nTest group: a call joined to another command is refused, not waved through\n"

assert_denies "a pipe no longer switches the guard off" \
  "$(run_bash 'gh api --method DELETE repos/owner/name/issues/1 | cat')"
assert_denies "a redirect no longer switches the guard off" \
  "$(run_bash 'gh api --method DELETE repos/owner/name/issues/1 > out.json')"
assert_denies "a cd prefix no longer hides the call from the guard" \
  "$(run_bash 'cd /repo && gh api --method DELETE repos/owner/name/issues/1')"
assert_denies "a command in front of the call no longer hides it" \
  "$(run_bash 'gh pr view; gh api --method DELETE repos/owner/name/issues/1')"
assert_denies "an and-chain in front of the call no longer hides it" \
  "$(run_bash 'true && gh api --method DELETE repos/owner/name/issues/1')"
assert_denies "an environment assignment in front of the call no longer hides it" \
  "$(run_bash 'GH_TOKEN=x gh api --method DELETE repos/owner/name/issues/1')"
assert_denies "a bare cd in front of the call no longer hides it" \
  "$(run_bash 'cd && gh api --method DELETE repos/owner/name/issues/1')"
assert_denies "a second line no longer hides the call" \
  "$(run_bash 'echo hi
gh api --method DELETE repos/owner/name/issues/1')"

printf "\nTest group: a value written attached to its flag is refused too\n"

assert_denies "a short body-parameter flag with the value attached" \
  "$(run_bash 'gh api repos/owner/name/issues -ftitle=x')"
assert_denies "a short raw body-parameter flag with the value attached" \
  "$(run_bash 'gh api repos/owner/name/issues -Fowner=y')"
assert_denies "a long body-parameter flag joined by an equals sign" \
  "$(run_bash 'gh api repos/owner/name/issues --field=title=x')"
assert_denies "a long raw body-parameter flag joined by an equals sign" \
  "$(run_bash 'gh api repos/owner/name/issues --raw-field=title=x')"
assert_denies "a body read from a file, joined by an equals sign" \
  "$(run_bash 'gh api repos/owner/name/issues --input=body.json')"
assert_denies "a write method with the value attached" \
  "$(run_bash 'gh api -XPOST repos/owner/name/issues')"
assert_denies "a write method joined by an equals sign" \
  "$(run_bash 'gh api --method=DELETE repos/owner/name/issues/1')"

printf "\nTest group: the neighbouring options the new patterns must not swallow\n"

assert_silent "a GET with the value attached is still allowed" \
  "$(run_bash 'gh api -XGET repos/owner/name/pulls/1')"
assert_silent "a GET joined by an equals sign is still allowed" \
  "$(run_bash 'gh api --method=GET repos/owner/name/pulls/1')"
assert_silent "a filter naming a branch that starts with a dash is not read as a body parameter" \
  "$(run_bash "gh api repos/owner/name/pulls --jq '.[] | select(.head.ref==\"-fix\")'")"

printf "\nTest group: a finding anchored beside the line it is about gets through\n"

assert_silent "a review comment posted onto a pull request" \
  "$(run_bash 'gh api repos/owner/name/pulls/50/comments --method POST --field path=a.md --field line=3 --field side=RIGHT --field commit_id=abc --field body=x')"
assert_silent "the same call written with the short flags" \
  "$(run_bash 'gh api repos/owner/name/pulls/50/comments -XPOST -fpath=a.md -fline=3')"
assert_silent "reading the comments back is unaffected" \
  "$(run_bash 'gh api repos/owner/name/pulls/50/comments')"

assert_denies "a write to any other endpoint is still refused" \
  "$(run_bash 'gh api repos/owner/name/issues/1/comments --method POST --field body=x')"
assert_denies "and so is a delete against the comments endpoint" \
  "$(run_bash 'gh api repos/owner/name/pulls/50/comments --method DELETE')"

printf "\n%d passed, %d failed\n" "$pass" "$fail"
[ "$fail" -eq 0 ]
