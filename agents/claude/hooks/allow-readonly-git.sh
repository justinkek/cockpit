#!/usr/bin/env bash

set -f
input="$(cat)"
tool="$(printf '%s' "$input" | jq -r '.tool_name // empty' 2>/dev/null)"
cmd="$(printf '%s'  "$input" | jq -r '.tool_input.command // empty' 2>/dev/null)"
[ "$tool" = "Bash" ] || exit 0
[ -n "$cmd" ] || exit 0

# strip a single leading `cd <path> &&`, then it must be one git command
work="$(printf '%s' "$cmd" | sed -E 's/^[[:space:]]*//; s/^cd[[:space:]]+[^&]+&&[[:space:]]*//')"
residue="$(printf '%s' "$work" | sed -E "s/'[^']*'//g; s/\"[^\"]*\"//g")"
case "$residue" in
  *'|'*|*'&'*|*';'*|*'<'*|*'>'*|*'`'*|*'$('*) exit 0 ;;
esac
case "$work" in "git "*) ;; *) exit 0 ;; esac

# extract the subcommand, skipping global flags (-C <path>, -c <kv>, --git-dir=…)
set -- ${work#git }
sub=""
while [ $# -gt 0 ]; do
  case "$1" in
    -C|-c|--namespace|--git-dir|--work-tree) if [ $# -ge 2 ]; then shift 2; else shift; fi; continue ;;
    -*) shift; continue ;;
    *) sub="$1"; break ;;
  esac
done

# Collect remaining args after the subcommand for context
shift
rest="$*"

case "$sub" in
  push)
    lowered="$(printf '%s' "$work" | tr '[:upper:]' '[:lower:]')"
    case "$lowered" in
      *--no-v*)
        jq -nc --arg r "git push --no-verify is denied — it skips the pre-push hook that refuses main. Git accepts any unambiguous abbreviation of it, so every --no-v… form is refused." \
          '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}' ;;
      *hookspath*)
        jq -nc --arg r "git push with core.hooksPath set is denied — repointing it disables the pre-push hook that refuses main" \
          '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}' ;;
      *)
        jq -nc --arg r "git push — allowed; the pre-push hook refuses main" \
          '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"allow",permissionDecisionReason:$r}}' ;;
    esac ;;
  reset)
    case "$rest" in *--hard*)
      jq -nc --arg r "git reset --hard is denied — destructive" \
        '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}' ;;
    *) exit 0 ;;
    esac ;;
  clean)
    jq -nc --arg r "git clean is denied — destructive" \
      '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}' ;;
  checkout)
    case "$rest" in "."*|"-- ."*|"--"*"."*)
      jq -nc --arg r "git checkout . is denied — destructive" \
        '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}' ;;
    *) exit 0 ;;
    esac ;;
  restore)
    case "$rest" in "."*)
      jq -nc --arg r "git restore . is denied — destructive" \
        '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}' ;;
    *) exit 0 ;;
    esac ;;
  status|log|diff|show|blame|rev-parse|rev-list|ls-files|ls-tree|cat-file|describe|shortlog|for-each-ref|merge-base|name-rev|symbolic-ref|diff-tree|whatchanged)
    jq -nc --arg r "read-only git ($sub) — allowed" \
      '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"allow",permissionDecisionReason:$r}}' ;;
  *) exit 0 ;;
esac
exit 0
