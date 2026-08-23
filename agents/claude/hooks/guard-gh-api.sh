#!/usr/bin/env bash

set -f
input="$(cat)"
tool="$(printf '%s' "$input" | jq --raw-output '.tool_name // empty' 2>/dev/null)"
cmd="$(printf '%s'  "$input" | jq --raw-output '.tool_input.command // empty' 2>/dev/null)"
[ "$tool" = "Bash" ] || exit 0
[ -n "$cmd" ] || exit 0

. "$(dirname "$0")/hook-argv-lib.sh"

guarded=""
invocations=0
while IFS= read -r segment; do
  invocations=$((invocations + 1))
  case "$segment" in
    "gh api "* | "gh api")
      if [ -z "$guarded" ]; then guarded="$segment"; fi ;;
  esac
done < <(hook_argv_segments "$cmd")
[ -n "$guarded" ] || exit 0

if [ "$invocations" -gt 1 ]; then
  jq --null-input --compact-output --arg r "gh api joined to another command is denied — the guard cannot tell what runs. Send the call on its own, and filter with --jq." \
    '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'
  exit 0
fi

args="${guarded#gh api }"

case "$args" in
  graphql*)
    lowercased="$(printf '%s' "$args" | tr 'A-Z' 'a-z')"
    case "$lowercased" in
      *mutation*) ;;
      *) case "$args" in *"=@"*) ;; *) exit 0 ;; esac ;;
    esac ;;
esac

method=""
body_parameter=""
set -- $args
while [ $# -gt 0 ]; do
  case "$1" in
    -X|--method) [ $# -ge 2 ] && method="$2" ;;
    --method=*) method="${1#--method=}" ;;
    -X?*) method="${1#-X}" ;;
    -f|-F|--field|--raw-field|--input) body_parameter="$1" ;;
    --field=*|--raw-field=*|--input=*) body_parameter="$1" ;;
    -f?*|-F?*) body_parameter="$1" ;;
  esac
  shift
done

anchors_a_review_comment=""
for token in $args; do
  case "$token" in
    repos/*/pulls/*/comments) anchors_a_review_comment=1 ;;
  esac
done

case "$method" in
  ""|GET|get) ;;
  POST|post) [ -n "$anchors_a_review_comment" ] || method_is_denied=1 ;;
  *) method_is_denied=1 ;;
esac

if [ -n "${method_is_denied:-}" ]; then
  jq --null-input --compact-output --arg r "gh api with method $method is denied — mutating. Use a GET, or a read-only graphql query." \
    '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'
  exit 0
fi

if [ -n "$anchors_a_review_comment" ]; then
  exit 0
fi

if [ -n "$body_parameter" ]; then
  jq --null-input --compact-output --arg r "gh api with body parameters is denied — auto-POSTs. A read-only graphql query is allowed: no mutation keyword, and the query text inline rather than read from a file." \
    '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'
  exit 0
fi

exit 0
