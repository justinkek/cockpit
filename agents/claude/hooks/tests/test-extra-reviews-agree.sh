#!/usr/bin/env bash

HOOKS_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CLAUDE_DIR="$(cd "$HOOKS_DIR/.." && pwd)"
PLUGIN_DIR="$(cd "$CLAUDE_DIR/../../marketplace/plugins/cockpit" && pwd)"
GATES="$CLAUDE_DIR/templates/status-machine-gates.md"
READY="$PLUGIN_DIR/skills/ticket:4:ready-for-cr/SKILL.md"
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

assert_lacks() {
  local label="$1" file="$2" needle="$3"
  if grep --quiet --fixed-strings "$needle" "$file"; then
    printf "  KO  %s — '%s' still in %s\n" "$label" "$needle" "$file"
    fail=$((fail + 1))
  else
    printf "  OK  %s\n" "$label"
    pass=$((pass + 1))
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

printf "\nTest group: an open finding is posted by the step that posts\n"

assert_names "the gates template hands the posting to ready-for-cr's own step" \
  "$GATES" '`/cockpit:ticket:4:ready-for-cr` step 4.5'
assert_names "and that step is the one posting open findings" \
  "$READY" '### 4.5. Post the open findings on the PR'
assert_lacks "the gates template no longer sends it through the thread walker" \
  "$GATES" 'through `/cockpit:ticket:4:cr:comments`'
assert_lacks "and does not post it a second time after the publish" \
  "$GATES" 'So publish, then post'

printf "\nTest group: a card that came back is reviewed the way the normal path is\n"

assert_lacks "the gates template passes no flag that posts only on a pull request target" \
  "$GATES" '/code-review low --comment'
assert_names "and says to leave it off" \
  "$GATES" 'leave `--comment` off'
assert_names "so the commits that brought the card back reach the PR through ready-for-cr" \
  "$GATES" '`/cockpit:ticket:4:ready-for-cr` pushes the fixes to that PR'

printf "\nTest group: every review reads the range the pull request carries\n"

assert_names "the gates template finds where the branch left its base" \
  "$GATES" 'git merge-base HEAD origin/<default-branch>'
assert_names "and reads from there to HEAD" \
  "$GATES" 'git diff <the commit it printed>..HEAD'
assert_names "and hands the shared review that same range" \
  "$GATES" '`/code-review low <the commit it printed>..HEAD`'

printf "\nTest group: the divergence review reads the steps off the local board\n"

DIVERGENCE="$REVIEWS/divergence-from-tech-steps.md"
assert_names "it reads the steps through board-card" \
  "$DIVERGENCE" '"$HOME/.cockpit/scripts/board-card" show <id> --section "Tech Steps"'
assert_names "and reads a missing section off the exit status" \
  "$DIVERGENCE" 'Exit 7 means the card has no `## Tech Steps`'
assert_lacks "and fetches no page" \
  "$DIVERGENCE" 'Fetch that page'
assert_names "an approved divergence is not reported" \
  "$DIVERGENCE" 'A divergence a person approved in a reply on the card'
assert_names "and resolved threads are read for the approval" \
  "$DIVERGENCE" 'board-card" comments <id> --all'

printf "\nTest group: a finding with nothing to anchor to still gets posted\n"

assert_names "the allowlist carries the fallback" "$SETTINGS" 'Bash(gh pr comment:*)'
assert_names "and ready-for-cr calls it by that name" "$READY" 'gh pr comment'

printf "\n%d passed, %d failed\n" "$pass" "$fail"
[ "$fail" -eq 0 ]
