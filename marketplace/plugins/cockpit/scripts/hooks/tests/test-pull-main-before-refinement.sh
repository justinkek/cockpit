#!/usr/bin/env bash

HOOK="$(cd "$(dirname "$0")/.." && pwd)/pull-main-before-refinement.sh"
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

pass=0
fail=0

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

SHARED="$TMPDIR/shared"
CALLED="$TMPDIR/called"

mkdir -p "$SHARED/hooks"
cat > "$SHARED/hooks/pull-main.sh" <<STUB
#!/usr/bin/env bash
printf 'called with %s\n' "\$*" >> "$CALLED"
exit 0
STUB
chmod +x "$SHARED/hooks/pull-main.sh"

run_hook() {
  rm -f "$CALLED"
  printf '%s' "$1" | CLAUDE_SHARED_DIR="$SHARED" bash "$HOOK" >/dev/null 2>&1
}

what_it_was_called_with() {
  if [ -f "$CALLED" ]; then sed 's/^called with //' "$CALLED"; else printf 'not called'; fi
}

payload_for() {
  printf '{"session_id": "test", "cwd": "%s", "tool_input": {"skill": "%s"}}' "$2" "$1"
}

printf "Test group: the two refinement skills carry their repository forward\n"

run_hook "$(payload_for cockpit:ticket:1:br /repositories/alpha)"
assert_eq "the BR skill pulls the session's own directory" "/repositories/alpha" "$(what_it_was_called_with)"

run_hook "$(payload_for cockpit:ticket:2:tr /repositories/beta)"
assert_eq "the TR skill pulls the session's own directory" "/repositories/beta" "$(what_it_was_called_with)"

printf "\nTest group: every other invocation is left alone\n"

run_hook "$(payload_for cockpit:ticket:3:dev /repositories/alpha)"
assert_eq "a skill outside refinement pulls nothing" "not called" "$(what_it_was_called_with)"

run_hook "$(payload_for cockpit:ticket:0:register /repositories/alpha)"
assert_eq "registering a ticket pulls nothing" "not called" "$(what_it_was_called_with)"

run_hook '{"session_id": "test", "tool_input": {"skill": "cockpit:ticket:2:tr"}}'
assert_eq "a payload naming no directory pulls nothing" "not called" "$(what_it_was_called_with)"

run_hook '{"session_id": "test", "cwd": "/repositories/alpha"}'
assert_eq "a payload naming no skill pulls nothing" "not called" "$(what_it_was_called_with)"

run_hook 'not json at all'
assert_eq "a payload that is not readable pulls nothing" "not called" "$(what_it_was_called_with)"

printf "\nTest group: the hook never fails the tool call it runs in front of\n"

printf '%s' "$(payload_for cockpit:ticket:2:tr /repositories/alpha)" \
  | CLAUDE_SHARED_DIR="$SHARED" bash "$HOOK" >/dev/null 2>&1
assert_eq "a refinement skill exits clean" "0" "$?"

printf '%s' "$(payload_for cockpit:ticket:3:dev /repositories/alpha)" \
  | CLAUDE_SHARED_DIR="$SHARED" bash "$HOOK" >/dev/null 2>&1
assert_eq "a skill outside refinement exits clean" "0" "$?"

printf "\n%s passed, %s failed\n" "$pass" "$fail"
[ "$fail" -eq 0 ]
