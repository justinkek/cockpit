#!/usr/bin/env bash

HOOKS_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CLAUDE_DIR="$(cd "$HOOKS_DIR/.." && pwd)"
GATES="$CLAUDE_DIR/templates/status-machine-gates.md"
READY="$CLAUDE_DIR/skills/cockpit:ticket:4:ready-for-cr/SKILL.md"
SETTINGS="$CLAUDE_DIR/settings/base.settings.json"
GUARD="$HOOKS_DIR/guard-gh-api.sh"
REVIEWS="$CLAUDE_DIR/../shared/code-reviews"

pass=0
fail=0

assert_names() {
  local label="$1" file="$2" needle="$3"
  if grep --quiet --fixed-strings "$needle" "$file"; then
    printf "  OK  %s\n" "$label"
    pass=$((pass + 1))
  else
    printf "  KO  %s — no '%s' in %s\n" "$label" "$needle" "$file"
    fail=$((fail + 1))
  fi
}

assert_present() {
  local label="$1" file="$2"
  if [ -f "$file" ]; then
    printf "  OK  %s\n" "$label"
    pass=$((pass + 1))
  else
    printf "  KO  %s — %s is not there\n" "$label" "$file"
    fail=$((fail + 1))
  fi
}

printf "Test group: a project's own reviews have somewhere to be listed\n"

assert_names "the gates template names the section a project lists them in" \
  "$GATES" '## Extra reviews'
assert_names "and the file a project keeps its conventions in" \
  "$GATES" './AGENTS.md'
assert_names "and still names the review every project runs" \
  "$GATES" '/code-review low'
assert_names "the path a project's own review sits at names no agent" \
  "$GATES" 'agents/code-reviews/'
assert_names "and neither does the one shared across projects" \
  "$GATES" '~/.agents-shared/code-reviews/'

printf "\nTest group: two reviews run on every project, listed by no project\n"

assert_names "the gates template puts the pair beyond a project's reach" \
  "$GATES" 'A project neither lists those two nor leaves them out.'

for review in readability divergence-from-tech-steps; do
  assert_names "the gates template names $review" \
    "$GATES" "code-reviews/$review.md"
  assert_present "$review sits where the template points" \
    "$REVIEWS/$review.md"
  assert_names "$review anchors its findings to a line" \
    "$REVIEWS/$review.md" 'path/to/file.ext:123'
done

printf "\nTest group: the two files agree on the marker they pass between them\n"

assert_names "the gates template marks a finding it left open" "$GATES" 'unfixed -'
assert_names "ready-for-cr looks for that same marker" "$READY" 'unfixed -'
assert_names "both name the toggle it is written into" "$READY" 'Machine gates'

printf "\nTest group: a finding lands beside the line it is about\n"

assert_names "the gates template keeps the anchor the review reported" \
  "$GATES" 'path/to/file.ext:123'
assert_names "ready-for-cr posts onto the endpoint that takes one" \
  "$READY" 'pulls/<number>/comments'
assert_names "the guard lets that endpoint through" \
  "$GUARD" 'repos/*/pulls/*/comments'

printf "\nTest group: a finding with nothing to anchor to still gets posted\n"

assert_names "the allowlist carries the fallback" "$SETTINGS" 'Bash(gh pr comment:*)'
assert_names "and ready-for-cr calls it by that name" "$READY" 'gh pr comment'

printf "\n%d passed, %d failed\n" "$pass" "$fail"
[ "$fail" -eq 0 ]
