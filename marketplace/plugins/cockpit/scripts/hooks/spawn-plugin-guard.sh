#!/usr/bin/env bash

guard="${1:-}"
[ -n "$guard" ] || exit 0

input="$(cat)"

command -v jq >/dev/null 2>&1 || exit 0

. "${CLAUDE_SHARED_DIR:-$HOME/.claude-shared}/hooks/hook-argv-lib.sh"

[ "$(printf '%s' "$input" | jq --raw-output '.tool_name // empty')" = "Bash" ] || exit 0
cmd="$(printf '%s' "$input" | jq --raw-output '.tool_input.command // empty')"
printf '%s' "$cmd" | grep --quiet 'board-card' || exit 0

words="$(hook_argv_after "$cmd" board-card)"
action="$(printf '%s\n' "$words" | sed -n 1p)"
target="$(printf '%s\n' "$words" | sed -n 3p)"
while [ "${target#\#}" != "$target" ]; do target="${target#\#}"; done
target="${target# }"

case "$action:$target" in
  "section:Tech Steps")
    content="$(printf '## Tech Steps\n%s' "$(hook_heredoc_body "$cmd")")"
    ;;
  "set:body")
    content="$(hook_heredoc_body "$cmd")"
    [ -n "$content" ] || content="$(printf '%s\n' "$words" | sed -n 4p)"
    ;;
  *) exit 0 ;;
esac
[ -n "$content" ] || exit 0

search_root="${COCKPIT_PLUGIN_SEARCH_ROOT:-}"
if [ -z "$search_root" ]; then
  directory="${CLAUDE_PLUGIN_ROOT:-}"
  while [ -n "$directory" ] && [ "$directory" != "/" ]; do
    if [ -d "$directory/marketplaces" ]; then
      search_root="$directory"
      break
    fi
    directory="$(dirname "$directory")"
  done
fi
[ -n "$search_root" ] || exit 0

found="$(find "$search_root" -type f -name "$guard" -path '*/hooks/*' -print 2>/dev/null | head -1)"
[ -n "$found" ] || exit 0
[ -x "$found" ] || exit 0

printf '%s' "$input" \
  | jq --compact-output --arg content "$content" \
    '{session_id, transcript_path, cwd, hook_event_name, tool_name: "Write", tool_input: {content: $content}}' \
  | "$found"
