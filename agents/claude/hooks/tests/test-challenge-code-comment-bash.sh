#!/usr/bin/env bash

GUARD="$(cd "$(dirname "$0")/.." && pwd)/challenge-code-comment.sh"

pass=0
fail=0

verdict() {
  local emitted
  emitted="$(bash "$GUARD")"
  [ -n "$emitted" ] || { echo allow; return 0; }
  printf '%s' "$emitted" | jq --raw-output '.hookSpecificOutput.permissionDecision // "allow"'
}

decision() {
  jq --null-input --compact-output --arg command "$1" \
    '{tool_name: "Bash", tool_input: {command: $command}}' | verdict
}

edit_decision() {
  jq --null-input --compact-output --arg path "$1" --arg added "$2" \
    '{tool_name: "Edit", tool_input: {file_path: $path, new_string: $added, old_string: ""}}' | verdict
}

assert_eq() {
  local label="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then
    printf "  OK  %s\n" "$label"
    pass=$((pass + 1))
  else
    printf "  KO  %s — expected '%s', got '%s'\n" "$label" "$expected" "$actual"
    fail=$((fail + 1))
  fi
}

printf "Test group: a shell command that writes a comment is refused\n"

assert_eq "a heredoc carrying a comment" "deny" \
  "$(decision 'cat > lib/thing.sh <<EOF
# what this does
run
EOF')"
assert_eq "a printf appending a comment" "deny" \
  "$(decision "printf '# what this does\nrun\n' >> lib/thing.sh")"
assert_eq "an in-place perl substitution introducing one" "deny" \
  "$(decision "perl -pi -e 's{run}{# what this does\nrun}' lib/thing.sh")"
assert_eq "a tee carrying a comment" "deny" \
  "$(decision "printf '# what this does\n' | tee lib/thing.sh")"

printf "\nTest group: a shell command that writes no comment is left alone\n"

assert_eq "a redirect of ordinary code" "allow" \
  "$(decision "printf 'run\n' >> lib/thing.sh")"
assert_eq "a command that writes nothing at all" "allow" \
  "$(decision "grep --count '# what this does' lib/thing.sh")"
assert_eq "a shebang is not a comment" "allow" \
  "$(decision "printf '#!/usr/bin/env bash\n' > lib/thing.sh")"

printf "\nTest group: the file types the edit path exempts are exempt here too\n"

assert_eq "markdown" "allow" \
  "$(decision "printf '# heading\n' >> notes.md")"
assert_eq "an ignore file" "allow" \
  "$(decision "printf '# build output\ndist/\n' >> .gitignore")"
assert_eq "a discarded stream" "allow" \
  "$(decision "printf '# noise\n' > /dev/null")"

printf "\nTest group: the edit path still behaves as it did\n"

assert_eq "an edit adding a comment is refused" "deny" \
  "$(edit_decision "lib/thing.sh" '# what this does
run')"
assert_eq "an edit adding none is allowed" "allow" \
  "$(edit_decision "lib/thing.sh" 'run')"
assert_eq "an edit to markdown is exempt" "allow" \
  "$(edit_decision "notes.md" '# heading')"

printf "\n%d passed, %d failed\n" "$pass" "$fail"
[ "$fail" -eq 0 ]
