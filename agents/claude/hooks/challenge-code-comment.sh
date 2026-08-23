#!/usr/bin/env bash

input="$(cat)"

command -v jq >/dev/null 2>&1 || exit 0

tool="$(printf '%s' "$input" | jq -r '.tool_name // empty')"
case "$tool" in
  Edit|Write|Bash) ;;
  *) exit 0 ;;
esac

path_is_exempt() {
  case "${1##*/}" in
    .gitignore|.gitattributes|.dockerignore|.npmignore|.prettierignore|.eslintignore) return 0 ;;
    .editorconfig|.gitconfig|Dockerfile|Makefile|.env*) return 0 ;;
  esac
  case "$1" in
    /dev/null|/dev/stderr|/dev/stdout) return 0 ;;
    *.md|*.mdx|*.markdown|*.txt|*.rst) return 0 ;;
    *.json|*.lock|*.csv|*.svg) return 0 ;;
    *.yml|*.yaml|*.toml|*.ini|*.cfg|*.conf|*.env) return 0 ;;
  esac
  return 1
}

writes_a_file() {
  printf '%s' "$1" | grep --quiet --extended-regexp \
    '(^|[^0-9&<>])>>?[[:space:]]*[^&[:space:]]|\btee\b|\binstall\b|\b(sed|perl)\b[^|;]*(-[A-Za-z]*i|--in-place)|\b(cp|mv)\b'
}

paths_in() {
  printf '%s' "$1" | tr -s "[:space:]'\"\`;|&()" '\n' | grep --extended-regexp '^[^-][^[:space:]]*\.[A-Za-z0-9_]+$|^\.[A-Za-z0-9_]+$|^/dev/[a-z]+$'
}

if [ "$tool" = "Bash" ]; then
  command_line="$(printf '%s' "$input" | jq -r '.tool_input.command // empty')"
  writes_a_file "$command_line" || exit 0

  every_path_exempt=1
  saw_a_path=0
  while IFS= read -r candidate; do
    [ -n "$candidate" ] || continue
    saw_a_path=1
    path_is_exempt "$candidate" || every_path_exempt=0
  done <<< "$(paths_in "$command_line")"
  [ "$saw_a_path" -eq 1 ] && [ "$every_path_exempt" -eq 1 ] && exit 0

  fp="the file this command writes"
  hash_opens_a_directive=0
  added="$(printf '%s' "$command_line" | sed 's/\\n/\
/g' | tr "'\"{}" '\n\n\n\n')"
  removed=""
else
  fp="$(printf '%s' "$input" | jq -r '.tool_input.file_path // empty')"
  path_is_exempt "$fp" && exit 0

  hash_opens_a_directive=0
  case "$fp" in
    *.c|*.h|*.cc|*.cpp|*.cxx|*.hh|*.hpp|*.hxx|*.cu|*.cuh|*.m|*.mm) hash_opens_a_directive=1 ;;
  esac

  added="$(printf '%s' "$input" | jq -r '.tool_input.new_string // .tool_input.content // empty')"
  removed="$(printf '%s' "$input" | jq -r '.tool_input.old_string // empty')"
fi

comment_lines() {
  awk -v hash_opens_a_directive="$1" '
    {
      line = $0
      if (sq % 2 == 0 && dq % 2 == 0) {
        probe = line
        sub(/^[[:space:]]+/, "", probe)
        if (probe !~ /^#!/ && !(hash_opens_a_directive && probe ~ /^#/) &&
            (probe ~ /^(#|\/\/|\/\*)/ || probe ~ /^\*([[:space:]]|\/|$)/)) print probe
      }
      sq += gsub(/\047/, "", line)
      dq += gsub(/"/, "", line)
    }
  ' | sort -u
}

drop_licence_header() {
  awk '
    !body {
      if (NR == 1 && $0 ~ /^#!/) next
      if ($0 ~ /^[[:space:]]*$/) { licence = 0; next }
      if ($0 ~ /^[[:space:]]*(\/\/|#|\*|\/\*)/) {
        if (licence || $0 ~ /SPDX-License-Identifier:|Copyright \(c\)|Copyright ©|Licensed under/) { licence = 1; next }
        print
        next
      }
      body = 1
    }
    body { print }
  '
}

[ "$tool" = "Write" ] && added="$(printf '%s\n' "$added" | drop_licence_header)"

new_comments="$(printf '%s\n' "$added" | comment_lines "$hash_opens_a_directive")"
if [ "$tool" = "Bash" ]; then
  new_comments="$(printf '%s\n' "$new_comments" | grep --extended-regexp '^(#|//)[[:space:]]' || true)"
fi
[ -n "$new_comments" ] || exit 0

old_comments="$(printf '%s\n' "$removed" | comment_lines "$hash_opens_a_directive")"
count="$(comm -23 <(printf '%s\n' "$new_comments") <(printf '%s\n' "$old_comments") | grep -c '[^[:space:]]')"
[ "$count" -gt 0 ] || exit 0

reason="Comment denied: this edit adds $count comment line(s) to $fp. Write the change without them, and carry what the comment would have said one of these ways instead: assert the invariant at runtime using a value the code already has; rename the function or variable so the constraint reads off the code; write a test whose failure teaches it; write it up in the repo's own docs, separate from the code. There is no escape hatch — do not retry, do not ask, do not work around this deny. If none of those can carry it, say what you would write and where, and leave it for the user to add by hand."

jq -nc --arg r "$reason" \
  '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'
exit 0
