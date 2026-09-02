#!/usr/bin/env bash

HOOKS_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CLAUDE_DIR="$(cd "$HOOKS_DIR/.." && pwd)"
REPO="$(cd "$CLAUDE_DIR/../.." && pwd)"
PLUGIN_HOOKS_DIR="$REPO/marketplace/plugins/cockpit/scripts/hooks"
SETTINGS="$CLAUDE_DIR/settings/base.settings.json"
RULES="$REPO/agents/shared/base.AGENTS.md"

loaded_files=(
  "$RULES"
  "$CLAUDE_DIR/claude-md/adapter.CLAUDE.md"
  "$REPO/CLAUDE.md"
)

SENTENCE_FLOOR=60

TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

pass=0
fail=0

assert() {
  local label="$1" outcome="$2" detail="$3"
  if [ "$outcome" = "0" ]; then
    printf "  OK  %s\n" "$label"
    pass=$((pass + 1))
  else
    printf "  KO  %s — %s\n" "$label" "$detail"
    fail=$((fail + 1))
  fi
}

corpus="$TMPDIR/always-loaded.txt"
for file in "${loaded_files[@]}"; do
  tr '\n' ' ' < "$file" | sed 's/  */ /g'
  printf '\n'
done > "$corpus"

sentences_of() {
  grep --extended-regexp --only-matching "\"[^\"]{$SENTENCE_FLOOR,}\"" "$1" \
    | awk '{ count = split($0, parts, /\. /); for (part = 1; part <= count; part++) print parts[part] }' \
    | sed 's/^"//; s/"$//'
}

repeated_sentence_of() {
  local hook="$1" sentence=""
  while IFS= read -r sentence; do
    [ "${#sentence}" -ge "$SENTENCE_FLOOR" ] || continue
    if grep --quiet --fixed-strings -- "$sentence" "$corpus"; then
      printf '%s\n' "$sentence"
      return 0
    fi
  done < <(sentences_of "$hook")
  return 1
}

printf "Test group: a sentence a per-prompt hook prints is not in the always-loaded set\n"

reminders="$(jq --raw-output '.hooks.UserPromptSubmit[].hooks[].command' "$SETTINGS")"

if [ -n "$reminders" ]; then
  assert "the settings name the per-prompt hooks" 0 ""
else
  assert "the settings name the per-prompt hooks" 1 "no UserPromptSubmit commands in $SETTINGS"
fi

while IFS= read -r command_line; do
  [ -n "$command_line" ] || continue
  script="${command_line%% *}"
  hook="$HOOKS_DIR/${script##*/}"
  [ -f "$hook" ] || hook="$PLUGIN_HOOKS_DIR/${script##*/}"
  if [ ! -f "$hook" ]; then
    assert "$(basename "$hook") exists" 1 "$command_line names a file in neither $HOOKS_DIR nor $PLUGIN_HOOKS_DIR"
    continue
  fi
  repeated="$(repeated_sentence_of "$hook")"
  [ -z "$repeated" ]
  assert "$(basename "$hook") states nothing already loaded" "$?" \
    "it prints a sentence the always-loaded set holds: $repeated"
done <<< "$reminders"

printf "\nTest group: the comparison catches a repeat that is there\n"

probe="$(awk 'length($0) >= 70 && index($0, "\"") == 0 { print; exit }' "$RULES")"
fixture="$TMPDIR/reminder-that-repeats.sh"
printf '#!/usr/bin/env bash\n\nprintf %s "%s"\n' "'%s\\n'" "$probe" > "$fixture"

[ -n "$probe" ]
assert "a sentence to repeat was found in the rules" "$?" "no quote-free line of 70 characters in $RULES"

[ -n "$(repeated_sentence_of "$fixture")" ]
assert "a hook printing it is caught" "$?" "the fixture repeats $RULES and the comparison missed it"

printf "\n%d passed, %d failed\n" "$pass" "$fail"
[ "$fail" -eq 0 ]
