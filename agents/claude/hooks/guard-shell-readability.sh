#!/usr/bin/env bash

set -f
input="$(cat)"

command -v jq >/dev/null 2>&1 || exit 0

tool_name="$(printf '%s' "$input" | jq -r '.tool_name // empty')"

accepts_long_options() {
  case "$1" in
    aws|brew|curl|docker|gcloud|gh|git|grep|jq|kubectl|mise|node|npm|npx) return 0 ;;
    pip3|python3|rsync|sort|ssh|tar|wget) return 0 ;;
  esac
  return 1
}

holds_shell() {
  local path="$1" body="$2"
  case "$path" in
    *.sh|*.bash|*.zsh|*zshrc|*zprofile|*bashrc|*profile) return 0 ;;
    *.md|*.mdx|*.markdown|*.txt|*.rst) return 1 ;;
    *.json|*.lock|*.csv|*.svg|*.yml|*.yaml|*.toml|*.ini|*.cfg|*.conf) return 1 ;;
    *.ts|*.tsx|*.js|*.jsx|*.py|*.rb|*.go|*.rs|*.java|*.kt|*.swift|*.c|*.h) return 1 ;;
  esac
  if [ -f "$path" ] && head -1 "$path" | grep -qE '^#!.*(bash|zsh|sh)'; then
    return 0
  fi
  printf '%s\n' "$body" | head -1 | grep -qE '^#!.*(bash|zsh|sh)'
}

scan() {
  local text="$1" unquoted segment head_word token
  [ -n "$text" ] || return 0
  unquoted="$(printf '%s\n' "$text" | sed -E "s/'[^']*'//g; s/\"[^\"]*\"//g")"

  while IFS= read -r segment; do
    [ -n "$segment" ] || continue
    set -- $segment
    while [ $# -gt 0 ]; do
      case "$1" in
        if|while|until|then|do|done|elif|else|fi|'!'|time|sudo|nohup|exec|command) shift ;;
        *) break ;;
      esac
    done
    [ $# -gt 0 ] || continue
    head_word="${1##*/}"
    accepts_long_options "$head_word" || continue
    shift
    for token in "$@"; do
      case "$token" in
        -[A-Za-z]|-[A-Za-z][A-Za-z]*) ;;
        *) continue ;;
      esac
      case "$head_word $token" in
        'git -C'|'tar -C') continue ;;
      esac
      printf 'option: %s %s\n' "$head_word" "$token"
    done
  done <<< "$(printf '%s\n' "$unquoted" | tr '|;&' '\n\n\n')"

  printf '%s\n' "$unquoted" \
    | grep -oE '(^|[[:space:]]|local[[:space:]]+|export[[:space:]]+|declare[[:space:]]+)[A-Za-z_][A-Za-z0-9_]*=' \
    | grep -oE '[A-Za-z_][A-Za-z0-9_]*=' \
    | tr -d '=' \
    | grep -xE 'acc|arg|attr|cfg|cmd|ctx|curr|desc|dir|dst|enc|fp|idx|len|msg|num|opt|pos|prev|req|res|src|str|tmp|val|var' \
    | sed 's/^/name: /'
}

case "$tool_name" in
  Bash)
    added="$(printf '%s' "$input" | jq -r '.tool_input.command // empty')"
    removed=""
    subject="this command"
    ;;
  Edit|Write)
    added="$(printf '%s' "$input" | jq -r '.tool_input.new_string // .tool_input.content // empty')"
    removed="$(printf '%s' "$input" | jq -r '.tool_input.old_string // empty')"
    file_path="$(printf '%s' "$input" | jq -r '.tool_input.file_path // empty')"
    holds_shell "$file_path" "$added" || exit 0
    subject="$file_path"
    ;;
  *) exit 0 ;;
esac

[ -n "$added" ] || exit 0

offences="$(comm -23 \
  <(scan "$added" | sort -u) \
  <(scan "$removed" | sort -u))"

[ -n "$offences" ] || exit 0

offending_names="$(printf '%s\n' "$offences" | sed -n 's/^name: //p' | tr '\n' ' ')"
offending_options="$(printf '%s\n' "$offences" | sed -n 's/^option: //p' | tr '\n' ',' | sed 's/,$//')"

detail=""
[ -n "$offending_names" ] && detail="shortened variable name(s): ${offending_names}"
if [ -n "$offending_options" ]; then
  [ -n "$detail" ] && detail="$detail; "
  detail="${detail}short-form option(s): ${offending_options}"
fi

reason="Unreadable shell denied in ${subject} — ${detail}. Spell every variable name out as the whole word, and write every option in its long form, then retry. There is no escape hatch — do not ask, do not work around this deny. If an option genuinely has no long form on this platform, say which and leave the exception for the user to add to the guard."

jq -nc --arg r "$reason" \
  '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'
exit 0
