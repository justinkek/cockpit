#!/usr/bin/env bash

set -f
input="$(cat)"

command -v jq >/dev/null 2>&1 || exit 0

tool_name="$(printf '%s' "$input" | jq --raw-output '.tool_name // empty')"
case "$tool_name" in
  Edit|Write) ;;
  *) exit 0 ;;
esac

MINIMUM_SENTENCE=60

checkout="$(cd "$(dirname "$0")" && cd "$(pwd -P)/../../.." && pwd)"

SENTENCES_PROGRAM='
function emit(   parts, count, index_, sentence) {
  if (paragraph == "") return
  gsub(/[[:space:]]+/, " ", paragraph)
  gsub(/[.!?] /, "&\n", paragraph)
  count = split(paragraph, parts, "\n")
  for (index_ = 1; index_ <= count; index_++) {
    sentence = parts[index_]
    sub(/^[[:space:]]+/, "", sentence)
    sub(/[[:space:]]+$/, "", sentence)
    if (length(sentence) >= minimum) print prefix sentence
  }
  paragraph = ""
}
FNR == 1 { emit(); fenced = 0; prefix = (named ? FILENAME "\t" : "") }
/^[[:space:]]*```/ { emit(); fenced = !fenced; next }
fenced { next }
/^[[:space:]]*$/ { emit(); next }
{
  line = $0
  sub(/^[[:space:]]*([-*+>#]+[[:space:]]*)*/, "", line)
  paragraph = (paragraph == "" ? line : paragraph " " line)
}
END { emit() }
'

holds_instructions() {
  case "$1" in
    *.md) ;;
    *) return 1 ;;
  esac
  case "$1" in
    *AGENTS.md|*CLAUDE.md|*SKILL.md) return 0 ;;
    *agents/*) return 0 ;;
  esac
  return 1
}

identity() {
  printf '%s\n' "${1#"$repo"/}"
}

worktree_of() {
  case "$1" in
    "$checkout"/.claude/worktrees/*) ;;
    *) return 1 ;;
  esac
  local inside="${1#"$checkout"/.claude/worktrees/}"
  printf '%s\n' "$checkout/.claude/worktrees/${inside%%/*}"
}

sentences() {
  [ -n "$1" ] || return 0
  printf '%s\n' "$1" \
    | awk -v minimum="$MINIMUM_SENTENCE" -v named=0 "$SENTENCES_PROGRAM" \
    | sort --unique
}

file_path="$(printf '%s' "$input" | jq --raw-output '.tool_input.file_path // empty')"
holds_instructions "$file_path" || exit 0

repo="$(worktree_of "$file_path")" || repo="$checkout"

added="$(printf '%s' "$input" | jq --raw-output '.tool_input.new_string // .tool_input.content // empty')"
removed="$(printf '%s' "$input" | jq --raw-output '.tool_input.old_string // empty')"

[ -n "$added" ] || exit 0

if [ -z "$removed" ] && [ -f "$file_path" ]; then
  removed="$(cat "$file_path")"
fi

candidates="$(comm -23 <(sentences "$added") <(sentences "$removed"))"

[ -n "$candidates" ] || exit 0

corpus="$(find "$repo" -name '*.md' -type f \
  -not -path "$repo/.claude/*" -not -path '*/.git/*' -not -path '*/node_modules/*' \
  -exec awk -v minimum="$MINIMUM_SENTENCE" -v named=1 "$SENTENCES_PROGRAM" {} +)"

target="$(identity "$file_path")"

hits=""
while IFS="$(printf '\t')" read -r held_in sentence; do
  [ -n "$held_in" ] || continue
  holds_instructions "$held_in" || continue
  [ "$(identity "$held_in")" != "$target" ] || continue
  hits="$hits $(identity "$held_in") already holds: \"$sentence\";"
done <<< "$(awk -v FS='\t' 'NR == FNR { wanted[$0] = 1; next } $2 in wanted' \
  <(printf '%s\n' "$candidates") <(printf '%s\n' "$corpus") | sort --unique)"

[ -n "$hits" ] || exit 0

reason="Repeated sentence denied in ${file_path} —${hits} An instruction is stated in one file and named from the others: replace the sentence with a pointer to the file that already holds it. Moving a sentence means cutting it from the file that holds it first, in its own edit. There is no escape hatch — do not ask, do not work around this deny."

jq --null-input --compact-output --arg r "$reason" \
  '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'
exit 0
