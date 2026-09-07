#!/usr/bin/env bash

guard="${1:-}"
[ -n "$guard" ] || exit 0

input="$(cat)"

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

printf '%s' "$input" | "$found"
