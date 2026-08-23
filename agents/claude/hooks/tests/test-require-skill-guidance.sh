#!/usr/bin/env bash

HOOK="$(cd "$(dirname "$0")/.." && pwd)/require-skill-guidance.sh"
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

export TICKET_STATE_DIR="$TMPDIR/state"

pass=0
fail=0

assert_present() {
  local label="$1" path="$2"
  if [ -e "$path" ]; then
    printf "  OK  %s\n" "$label"
    pass=$((pass + 1))
  else
    printf "  KO  %s — %s was never written\n" "$label" "$path"
    fail=$((fail + 1))
  fi
}

assert_absent() {
  local label="$1" path="$2"
  if [ ! -e "$path" ]; then
    printf "  OK  %s\n" "$label"
    pass=$((pass + 1))
  else
    printf "  KO  %s — %s exists\n" "$label" "$path"
    fail=$((fail + 1))
  fi
}

assert_denied() {
  local label="$1" output="$2"
  if printf '%s' "$output" | grep --quiet '"permissionDecision":"deny"'; then
    printf "  OK  %s\n" "$label"
    pass=$((pass + 1))
  else
    printf "  KO  %s — expected a deny, got '%s'\n" "$label" "$output"
    fail=$((fail + 1))
  fi
}

assert_allowed() {
  local label="$1" output="$2"
  if [ -z "$output" ]; then
    printf "  OK  %s\n" "$label"
    pass=$((pass + 1))
  else
    printf "  KO  %s — expected no output, got '%s'\n" "$label" "$output"
    fail=$((fail + 1))
  fi
}

assert_contains() {
  local label="$1" needle="$2" output="$3"
  if printf '%s' "$output" | grep --quiet --fixed-strings "$needle"; then
    printf "  OK  %s\n" "$label"
    pass=$((pass + 1))
  else
    printf "  KO  %s — '%s' is not in '%s'\n" "$label" "$needle" "$output"
    fail=$((fail + 1))
  fi
}

guard_on_bash() {
  printf '{"session_id":"s1","tool_name":"Bash","tool_input":{"command":%s}}' "$(printf '%s' "$1" | jq --raw-input .)" | bash "$HOOK"
}

marker="$TICKET_STATE_DIR/s1.skill-guidance"

printf "Test group: what the record mode writes\n"

printf '{"session_id":"s1","tool_input":{"skill":"cockpit:ticket:3:dev"}}' | bash "$HOOK" record
assert_absent "another skill leaves no marker" "$marker"

printf '{"session_id":"s1","tool_input":{"skill":"writing-great-skills"}}' | bash "$HOOK" record
assert_present "the guidance skill writes the marker" "$marker"

rm -f "$marker"
printf '{"session_id":"s1","tool_input":{"skill":"plugin:writing-great-skills"}}' | bash "$HOOK" record
assert_present "a namespaced form writes the marker too" "$marker"

printf "\nTest group: what the guard refuses\n"

rm -f "$marker"
denied="$(printf '{"session_id":"s1","tool_name":"Edit","tool_input":{"file_path":"/repo/skills/a/SKILL.md"}}' | bash "$HOOK")"
assert_denied "a skill edit with no marker is refused" "$denied"

named="$(printf '{"session_id":"s1","tool_name":"Write","tool_input":{"file_path":"/repo/skills/a/SKILL.md"}}' | bash "$HOOK")"
assert_contains "the refusal names the skill to invoke" "writing-great-skills" "$named"

bare="$(printf '{"session_id":"s1","tool_name":"Edit","tool_input":{"file_path":"SKILL.md"}}' | bash "$HOOK")"
assert_denied "a bare relative SKILL.md is refused too" "$bare"

printf "\nTest group: a shell command that writes a skill file\n"

assert_denied "a heredoc redirect is refused" "$(guard_on_bash 'cat > agents/skills/a/SKILL.md <<EOF')"
assert_denied "an append redirect is refused" "$(guard_on_bash 'printf x >> a/SKILL.md')"
assert_denied "an in-place sed is refused" "$(guard_on_bash 'sed --in-place s/a/b/ a/SKILL.md')"
assert_denied "a tee is refused" "$(guard_on_bash 'printf x | tee a/SKILL.md')"
assert_denied "a copy over one is refused" "$(guard_on_bash 'cp /tmp/x a/SKILL.md')"

assert_allowed "reading one is allowed" "$(guard_on_bash 'cat a/SKILL.md')"
assert_allowed "grepping one is allowed" "$(guard_on_bash 'grep --line-number x a/SKILL.md')"
assert_allowed "redirecting its content elsewhere is allowed" "$(guard_on_bash 'cat a/SKILL.md > /tmp/copy')"
assert_allowed "a shell command naming no skill file is allowed" "$(guard_on_bash 'printf x > a/AGENTS.md')"

printf "\nTest group: what the guard lets through\n"

allowed="$(printf '{"session_id":"s1","tool_name":"Edit","tool_input":{"file_path":"/repo/AGENTS.md"}}' | bash "$HOOK")"
assert_allowed "a file that is not a SKILL.md passes with no marker" "$allowed"

allowed="$(printf '{"session_id":"s1","tool_name":"Read","tool_input":{"file_path":"/repo/skills/a/SKILL.md"}}' | bash "$HOOK")"
assert_allowed "a tool that writes nothing passes" "$allowed"

printf '{"session_id":"s1","tool_input":{"skill":"writing-great-skills"}}' | bash "$HOOK" record
allowed="$(printf '{"session_id":"s1","tool_name":"Edit","tool_input":{"file_path":"/repo/skills/a/SKILL.md"}}' | bash "$HOOK")"
assert_allowed "a skill edit after the invoke passes" "$allowed"

printf "\nTest group: one session's invoke is not another's\n"

denied="$(printf '{"session_id":"s2","tool_name":"Edit","tool_input":{"file_path":"/repo/skills/a/SKILL.md"}}' | bash "$HOOK")"
assert_denied "a second session is refused on the first session's invoke" "$denied"

printf "\n%d passed, %d failed\n" "$pass" "$fail"
[ "$fail" -eq 0 ]
