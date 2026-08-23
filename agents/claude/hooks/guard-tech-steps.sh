#!/usr/bin/env bash

input="$(cat)"

command -v jq >/dev/null 2>&1 || exit 0

command_name="$(printf '%s' "$input" | jq --raw-output '.tool_input.command // empty')"
case "$command_name" in
update_content | replace_content | insert_content) ;;
*) exit 0 ;;
esac

written="$(printf '%s' "$input" | jq --raw-output '
  [ .tool_input.new_str // empty ]
  + [ .tool_input.content // empty ]
  + [ .tool_input.content_updates[]?.new_str ]
  | join("\n")
')"
[ -n "$written" ] || exit 0

refusals=""
deferred_refusals=""
tech_steps_write=0

refuse() {
  refusals="${refusals}
  - ${1}
    ${2}"
}

refuse_when_tech_steps() {
  deferred_refusals="${deferred_refusals}
  - ${1}
    ${2}"
}

sentence_column() {
  printf '%s' "$1" | sed 's/│/./g; s/├/./g; s/└/./g; s/─/./g' | awk '
    {
      rest = $0
      position = 0
      while (match(rest, /  +/)) {
        position += RSTART + RLENGTH - 1
        rest = substr(rest, RSTART + RLENGTH)
      }
      print position
    }'
}

character_length() {
  printf '%s' "$1" | LC_ALL=en_US.UTF-8 wc -m | awk '{ print $1 }'
}

tree_path() {
  printf '%s' "$1" | awk -F "── " '{ split($2, parts, "  "); print parts[1] }'
}

first_column=""
paths_seen=""
section=""
inside_fence=0
mermaid_block=""
inside_mermaid=0
inside_tree=0

while IFS= read -r line; do
  squashed="${line#"${line%%[![:space:]]*}"}"
  squashed="${squashed%"${squashed##*[![:space:]]}"}"

  case "$squashed" in
  '```'*) inside_fence=$((1 - inside_fence)) ;;
  esac

  case "$line" in
  "## "*)
    [ "$inside_fence" -eq 1 ] && continue
    section="${line#\#\# }"
    inside_tree=0
    [ "$section" = "Tech Steps" ] && tech_steps_write=1
    continue
    ;;
  esac

  if [ -n "$section" ] && [ "$section" != "Tech Steps" ]; then
    continue
  fi

  if [ "$inside_mermaid" -eq 1 ]; then
    if [ "$squashed" = '```' ]; then
      inside_mermaid=0
      printf '%s' "$mermaid_block" | grep --quiet --fixed-strings 'title ' ||
        refuse_when_tech_steps "a sequence flow in this write" "carries no title"
      printf '%s' "$mermaid_block" | grep --quiet --fixed-strings 'autonumber' ||
        refuse_when_tech_steps "a sequence flow in this write" "carries no autonumber"
      mermaid_block=""
      continue
    fi
    mermaid_block="${mermaid_block}
${line}"
    case "$line" in
    *"rect rgb("*)
      case "$line" in
      *"rgb(220, 245, 220)"* | *"rgb(255, 225, 225)"*) ;;
      *) refuse_when_tech_steps "$line" "shades with a colour outside the two the skill allows" ;;
      esac
      ;;
    esac
    continue
  fi

  if [ "$squashed" = '```mermaid' ]; then
    inside_mermaid=1
    mermaid_block=""
    continue
  fi

  case "$line" in
  "="*)
    inside_tree=1
    tech_steps_write=1
    first_column=""
    paths_seen=""
    heading_length="$(character_length "$line")"
    if [ "$heading_length" -ne 120 ]; then
      refuse "$line" "heads a tree in a rule of ${heading_length} characters, not 120"
    fi
    continue
    ;;
  esac

  if [ -z "$squashed" ]; then
    inside_tree=0
    continue
  fi

  if [ "$inside_tree" -eq 0 ]; then
    case "$line" in
    *"<summary>"*)
      summary="${line#*<summary>}"
      summary="${summary%%</summary>*}"
      case "$summary" in
      *" Layer "*)
        tech_steps_write=1
        continue
        ;;
      "" | "In "* | "["*) continue ;;
      esac
      printf '%s' "$summary" | grep --quiet --extended-regexp '^(add|replace|remove|rename|move) ' ||
        refuse_when_tech_steps "$summary" "opens on a verb outside add, replace, remove, rename and move"
      if printf '%s' "$summary" | grep --quiet --extended-regexp ' so [a-z]'; then
        refuse_when_tech_steps "$summary" "carries a reason clause"
      fi
      ;;
    esac
    continue
  fi

  case "$line" in
  "+ "* | "- "* | "! "* | "  "*) ;;
  *) refuse "$line" "opens on something other than +, -, ! or two spaces" ;;
  esac

  if [ "${line%/}" != "$line" ]; then
    continue
  fi

  case "$line" in
  *"── "*) ;;
  *)
    refuse "$line" "reaches its name on indentation alone, joined to no folder above it"
    continue
    ;;
  esac

  column="$(sentence_column "$line")"
  if [ -z "$first_column" ]; then
    first_column="$column"
  elif [ "$column" != "$first_column" ]; then
    refuse "$line" "starts its sentence at column ${column}, not ${first_column} like the rest of its tree"
  fi

  path="$(tree_path "$line")"
  case "
${paths_seen}" in
  *"
${path}"*) refuse "$line" "names a path its tree already carries" ;;
  *) paths_seen="${paths_seen}
${path}" ;;
  esac
done <<EOF
$written
EOF

if [ "$tech_steps_write" -eq 1 ]; then
  refusals="${refusals}${deferred_refusals}"
fi

[ -n "$refusals" ] || exit 0

reason="This write breaks a rule the cockpit:ticket:2:tr skill states about the tech steps:${refusals}

Read \`### Tech Steps\` in that skill, fix each line named above, and write again."
jq --null-input --compact-output --arg reason "$reason" \
  '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$reason}}'
exit 0
