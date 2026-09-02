#!/usr/bin/env bash

repo_root_through_symlink() {
  cd "$(dirname "$0")" && cd "$(pwd -P)/../.." && pwd
}

REPO="$(repo_root_through_symlink)"
CORE="$REPO/agents/shared/base.AGENTS.md"
BOARD_CORE="$REPO/agents/shared/board.AGENTS.md"
TEMPLATES="$REPO/agents/claude/templates"
SKILLS="$REPO/marketplace/plugins/cockpit/skills"
AGENT_CONFIG="$REPO/agents"
PLUGIN_CONFIG="$REPO/marketplace/plugins/cockpit"
PROJECT="$REPO/AGENTS.md"
SETTINGS="$REPO/agents/claude/settings/base.settings.json"
PLUGIN_HOOKS="$REPO/marketplace/plugins/cockpit/hooks/hooks.json"
TEMPLATE_PATH_PATTERN='templates/[A-Za-z0-9._-]+\.md'

pass=0
fail=0

assert_ok() {
  local label="$1"
  printf "  OK  %s\n" "$label"
  pass=$((pass + 1))
}

assert_ko() {
  local label="$1" detail="$2"
  printf "  KO  %s — %s\n" "$label" "$detail"
  fail=$((fail + 1))
}

printf "Test group: every reference a loader names exists\n"

named_templates="$(grep --only-matching --recursive --extended-regexp "$TEMPLATE_PATH_PATTERN" "$CORE" "$BOARD_CORE" "$SKILLS" | sed 's/^.*://' | sort --unique)"

if [ -z "$named_templates" ]; then
  assert_ko "the core and the skills name at least one reference" "no templates path found"
else
  missing=""
  for reference in $named_templates; do
    [ -f "$REPO/agents/claude/$reference" ] || missing="$missing $reference"
  done
  if [ -z "$missing" ]; then
    assert_ok "every templates path in the core and the skills resolves to a file"
  else
    assert_ko "every templates path in the core and the skills resolves to a file" "missing:$missing"
  fi
fi

printf "\nTest group: no reference is left with nobody loading it\n"

unread=""
for path in "$TEMPLATES"/*.md; do
  name="$(basename "$path")"
  if ! grep --quiet --recursive --fixed-strings --exclude-dir=templates "templates/$name" "$AGENT_CONFIG" "$PLUGIN_CONFIG"; then
    unread="$unread $name"
  fi
done

if [ -z "$unread" ]; then
  assert_ok "every template is named outside the templates directory"
else
  assert_ko "every template is named outside the templates directory" "unread:$unread"
fi

printf "\nTest group: the session-name convention is stated once\n"

CONVENTION="$TEMPLATES/session-name.md"

convention_phrases=(
  "[scope] description"
  "~25 characters"
)

lost=""
restated=""
for phrase in "${convention_phrases[@]}"; do
  grep --quiet --fixed-strings "$phrase" "$CONVENTION" || lost="$lost|$phrase"
  ! grep --quiet --recursive --fixed-strings --exclude-dir=templates "$phrase" "$AGENT_CONFIG" "$PLUGIN_CONFIG" || restated="$restated|$phrase"
done

if [ -z "$lost" ]; then
  assert_ok "the convention states the shape and the shortening rule"
else
  assert_ko "the convention states the shape and the shortening rule" "missing:$lost"
fi

if [ -z "$restated" ]; then
  assert_ok "and nothing outside the templates directory states either again"
else
  assert_ko "and nothing outside the templates directory states either again" "restated:$restated"
fi

printf "\nTest group: a pointer names its reference and states nothing it says\n"

summary_phrases=(
  "toggle and table markup"
  "carries the column pattern"
  "It carries the column"
  "A reviewer's correction"
  "for canonical section order"
  "does not already contain the PR URL"
  "conventional commit format as a commit"
)

restated=""
for phrase in "${summary_phrases[@]}"; do
  ! grep --quiet --recursive --fixed-strings --exclude-dir=templates "$phrase" "$AGENT_CONFIG" "$PLUGIN_CONFIG" || restated="$restated|$phrase"
done

if [ -z "$restated" ]; then
  assert_ok "no pointer outside the templates directory summarises its reference"
else
  assert_ko "no pointer outside the templates directory summarises its reference" "restated:$restated"
fi

printf "\nTest group: a moved body landed in a reference and left the core\n"

moved_sentences=(
  "the agent drafts, entry is automatic"
  "Fibonacci scale (1, 2, 3, 5, 8, 13)"
  "is the last section on every ticket"
  "needs to be created, insert it after"
  "Subsequent bounces from the same gate"
  "Notion parses"
  "reports success when"
  "watcher never fires on the agent's own walk"
  "One comment per finding, posted when it surfaces"
  "Open with the agent marker"
  "no useful work on this ticket is"
  "Prefer functional transforms over imperative loops"
)

lost=""
duplicated=""
for sentence in "${moved_sentences[@]}"; do
  grep --quiet --recursive --fixed-strings "$sentence" "$TEMPLATES" || lost="$lost|$sentence"
  ! grep --quiet --fixed-strings "$sentence" "$CORE" "$BOARD_CORE" || duplicated="$duplicated|$sentence"
done

if [ -z "$lost" ]; then
  assert_ok "every moved body is present in a reference"
else
  assert_ko "every moved body is present in a reference" "in no reference:$lost"
fi

if [ -z "$duplicated" ]; then
  assert_ok "and no longer stated in the core"
else
  assert_ko "and no longer stated in the core" "still in the core:$duplicated"
fi

printf "\nTest group: a moved path landed in a reference and left the skill that owns it\n"

STATUS_SKILL="$SKILLS/cockpit:ticket:x:status/SKILL.md"

moved_paths=(
  "Regression source"
  "Release the claim"
  "Give the worktree back"
  "Bring the main checkout forward"
  "Once per landing"
  "Last-in, never first-in"
)

lost=""
duplicated=""
for sentence in "${moved_paths[@]}"; do
  grep --quiet --recursive --fixed-strings "$sentence" "$TEMPLATES" || lost="$lost|$sentence"
  ! grep --quiet --fixed-strings "$sentence" "$STATUS_SKILL" || duplicated="$duplicated|$sentence"
done

if [ -z "$lost" ]; then
  assert_ok "every moved path is present in a reference"
else
  assert_ko "every moved path is present in a reference" "in no reference:$lost"
fi

if [ -z "$duplicated" ]; then
  assert_ok "and no longer stated in the status skill"
else
  assert_ko "and no longer stated in the status skill" "still in the skill:$duplicated"
fi

printf "\nTest group: a topic the project instructions used to restate names its reference\n"

retired_sentences=(
  "refused rather than answered empty"
  "Age is warned about on stderr"
  "so the number lives in two files"
  "unambiguous reason forms"
  "takes a default, rather than asking"
)

named_references=(
  "cockpit-cache-query"
  "base.AGENTS.md"
  "guard-instruction-register.sh"
  "templates/raise-a-decision.md"
  "templates/board-event.md"
  "templates/blocked-flag.md"
  "templates/copilot-finding.md"
  "templates/ticket-comment-reply.md"
  "templates/coding-conventions.md"
)

restated=""
for sentence in "${retired_sentences[@]}"; do
  ! grep --quiet --fixed-strings "$sentence" "$PROJECT" || restated="$restated|$sentence"
done

if [ -z "$restated" ]; then
  assert_ok "no retired body is stated again in the project instructions"
else
  assert_ko "no retired body is stated again in the project instructions" "restated:$restated"
fi

unnamed=""
for reference in "${named_references[@]}"; do
  grep --quiet --fixed-strings "$reference" "$PROJECT" && continue
  grep --quiet --fixed-strings "$reference" "$CORE" "$BOARD_CORE" && continue
  unnamed="$unnamed $reference"
done

if [ -z "$unnamed" ]; then
  assert_ok "and each of their references is named in the project instructions or the core"
else
  assert_ko "and each of their references is named in the project instructions or the core" "unnamed:$unnamed"
fi

printf "\nTest group: a worked example is written in one instruction file\n"

example_anchors=(
  "In src/hooks/useUserProfile.ts"
  "Complexity Breakdown: 3 = FE 2 + Testing 1"
  "Back from CR #1"
)

duplicated=""
for anchor in "${example_anchors[@]}"; do
  holders="$(grep --recursive --files-with-matches --fixed-strings "$anchor" "$AGENT_CONFIG" "$PLUGIN_CONFIG" | grep --count .)"
  [ "$holders" -eq 1 ] || duplicated="$duplicated|$anchor in $holders files"
done

if [ -z "$duplicated" ]; then
  assert_ok "every worked example appears in exactly one instruction file"
else
  assert_ko "every worked example appears in exactly one instruction file" "$duplicated"
fi

printf "\nTest group: a stage section left the contract for its own file\n"

CONTRACT="$TEMPLATES/cockpit-operating-contract.md"

staged_sentences=(
  "Split threshold"
  "owns status: a change is written there first"
  "Reviewing is the first job"
)

lost=""
duplicated=""
for sentence in "${staged_sentences[@]}"; do
  grep --quiet --recursive --fixed-strings "$sentence" "$TEMPLATES" || lost="$lost|$sentence"
  ! grep --quiet --fixed-strings "$sentence" "$CONTRACT" || duplicated="$duplicated|$sentence"
done

if [ -z "$lost" ]; then
  assert_ok "every staged section is present in a stage file"
else
  assert_ko "every staged section is present in a stage file" "in no stage file:$lost"
fi

if [ -z "$duplicated" ]; then
  assert_ok "and no longer stated in the contract"
else
  assert_ko "and no longer stated in the contract" "still in the contract:$duplicated"
fi

printf "\nTest group: a behaviour that fires outside this repo is named in the core\n"

repo_scoped_commands=(
  "format-on-edit.sh"
  "guard-instruction-repetition.sh"
)

not_yet_named=(
  "allow-family-search.sh"
  "allow-gh-pr-comment-reads.sh"
  "allow-readonly-git.sh"
  "auto-populate-pr.sh"
  "auto-rename"
  "auto-sync-config.sh"
  "block-user-claudemd.sh"
  "block-user-settings.sh"
  "challenge-code-comment.sh"
  "challenge-memory-write.sh"
  "challenge-settings-scope.sh"
  "cockpit-board-claim"
  "cockpit-board-id"
  "cockpit-cache-refresh"
  "confine-to-repo.sh"
  "guard-bash-secret-read.sh"
  "guard-env-var-leak.sh"
  "guard-gh-api.sh"
  "guard-notion-content-revival.sh"
  "guard-secrets-gitignore.sh"
  "guard-ticket-comment-length.sh"
  "redirect-artifacts.sh"
  "redirect-default-profile-reads.sh"
  "redirect-session-id-echo.sh"
  "redirect-state-to-read-write.sh"
  "refresh-cockpit-cache.sh"
  "remind-back-from-column.sh"
  "remind-response-length.sh"
  "require-blocked-comment.sh"
  "require-emoji.sh"
  "require-rename.sh"
  "require-ticket-type.sh"
  "require-ticket.sh"
  "session-end-release-claims.sh"
  "settings-scope-confirm"
  "sprint-backlog-sync.sh"
  "statusline-command"
  "ticket-comment-images"
  "ticket-comment-line"
  "ticket-done-usage"
  "ticket-register"
  "ticket-register-column"
  "ticket-register-source-ticket"
  "ticket-register-type"
  "ticket-status-confirm"
  "ticket-watch-board"
  "verify-notion-content-edit.sh"
)

registered_commands() {
  grep --only-matching --extended-regexp 'hooks/[a-z0-9-]+\.sh' "$SETTINGS" "$PLUGIN_HOOKS" | sed 's|^.*hooks/||'
  grep --only-matching --extended-regexp '\.claude-shared/[a-z0-9-]+' "$SETTINGS" |
    sed 's|\.claude-shared/||' | grep --invert-match --line-regexp 'hooks'
  grep --only-matching --extended-regexp '\.cockpit/scripts/[a-z0-9-]+' "$SETTINGS" |
    sed 's|\.cockpit/scripts/||' | grep --invert-match --line-regexp 'hooks'
}

allowed_commands="$(printf '%s\n' "${repo_scoped_commands[@]}" "${not_yet_named[@]}")"

unnamed=""
for command_name in $(registered_commands | sort --unique); do
  grep --quiet --fixed-strings "$command_name" "$CORE" "$BOARD_CORE" && continue
  printf '%s\n' "$allowed_commands" | grep --quiet --line-regexp --fixed-strings "$command_name" && continue
  unnamed="$unnamed $command_name"
done

if [ -z "$unnamed" ]; then
  assert_ok "every registered hook and script is named in the core, exempt, or listed as not yet named"
else
  assert_ko "every registered hook and script is named in the core, exempt, or listed as not yet named" "unnamed:$unnamed"
fi

registered="$(registered_commands | sort --unique)"

stale=""
for command_name in "${repo_scoped_commands[@]}" "${not_yet_named[@]}"; do
  printf '%s\n' "$registered" | grep --quiet --line-regexp --fixed-strings "$command_name" ||
    stale="$stale $command_name (not registered)"
done
for command_name in "${not_yet_named[@]}"; do
  ! grep --quiet --fixed-strings "$command_name" "$CORE" "$BOARD_CORE" || stale="$stale $command_name (now named in the core)"
done

if [ -z "$stale" ]; then
  assert_ok "and neither list holds a command it no longer needs to"
else
  assert_ko "and neither list holds a command it no longer needs to" "stale:$stale"
fi

printf "\n%d passed, %d failed\n" "$pass" "$fail"
[ "$fail" -eq 0 ]
