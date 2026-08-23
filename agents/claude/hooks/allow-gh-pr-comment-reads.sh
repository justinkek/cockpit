#!/usr/bin/env bash

input="$(cat)"
tool="$(printf '%s' "$input" | jq -r '.tool_name // empty'         2>/dev/null)"
cmd="$(printf '%s'  "$input" | jq -r '.tool_input.command // empty' 2>/dev/null)"
[ "$tool" = "Bash" ] || exit 0
[ -n "$cmd" ] || exit 0

. "$(dirname "$0")/hook-argv-lib.sh"

matched=""
invocations=0
while IFS= read -r segment; do
  invocations=$((invocations + 1))
  case "$segment" in
    "gh api "* | "gh api")
      if [ -z "$matched" ]; then matched="$segment"; fi ;;
  esac
done < <(hook_argv_segments "$cmd")
[ -n "$matched" ] || exit 0
[ "$invocations" -eq 1 ] || exit 0

allow() {
  jq -nc --arg r "$1" '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"allow",permissionDecisionReason:$r}}'
  exit 0
}

lc="$(printf '%s' "$cmd" | tr 'A-Z' 'a-z')"

case "$cmd" in
  *graphql*)
    case "$lc"  in *mutation*) exit 0 ;; esac        # a mutation -> defer
    case "$cmd" in *"=@"*)     exit 0 ;; esac         # query from a file -> can't inspect -> defer
    case "$cmd" in
      *reviewThreads*|*reviewthreads*|*pullRequest*|*pullrequest*)
        allow "gh api graphql — PR review-thread read (no mutation keyword)" ;;
    esac
    exit 0 ;;
  *)
    case "$cmd" in
      *" -X "*|*"--method"*|*" -f "*|*" -F "*|*"--field"*|*"--raw-field"*|*"--input"*) exit 0 ;;
    esac
    case "$cmd" in
      *pulls/*/comments*|*pulls/*/reviews*) exit 0 ;;
      *repos/*/pulls*|*repos/*/issues/*/comments*)
        allow "gh api — REST GET on PR/issue comment endpoint" ;;
    esac
    exit 0 ;;
esac
