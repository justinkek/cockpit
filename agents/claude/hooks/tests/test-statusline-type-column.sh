#!/usr/bin/env bash

STATUSLINE="$(cd "$(dirname "$0")/../.." && pwd)/statusline-command.sh"
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

pass=0
fail=0

assert_contains() {
  local label="$1" expected="$2" output="$3"
  if printf '%s' "$output" | grep -qF "$expected"; then
    printf "  OK  %s\n" "$label"
    pass=$((pass + 1))
  else
    printf "  KO  %s — expected '%s' in output '%s'\n" "$label" "$expected" "$output"
    fail=$((fail + 1))
  fi
}

assert_not_contains() {
  local label="$1" unexpected="$2" output="$3"
  if ! printf '%s' "$output" | grep -qF "$unexpected"; then
    printf "  OK  %s\n" "$label"
    pass=$((pass + 1))
  else
    printf "  KO  %s — did not expect '%s' in output '%s'\n" "$label" "$unexpected" "$output"
    fail=$((fail + 1))
  fi
}

SESSION_ID="test-statusline-$$"
STATE_DIR="$TMPDIR/.local/state/claude-ticket-sessions"
TRANSCRIPT_DIR="$TMPDIR/.claude/projects/test/$SESSION_ID"
mkdir -p "$STATE_DIR" "$TRANSCRIPT_DIR"

printf 'type=ticket\nname=test session\nticket_type=feature\n' > "$STATE_DIR/$SESSION_ID.type"
printf 'in dev' > "$STATE_DIR/$SESSION_ID.column"
printf 'ready-for-cr' > "$STATE_DIR/$SESSION_ID.step"
printf '{"customTitle":"test session"}' > "$TRANSCRIPT_DIR/transcript.jsonl"

TRANSCRIPT_PATH="$TRANSCRIPT_DIR/transcript.jsonl"

printf "Test group: type and column appear when session_name is set, session_id absent\n"

output=$(jq -nc \
  --arg sn "test session" \
  --arg tp "$TRANSCRIPT_PATH" \
  '{session_name:$sn, transcript_path:$tp, model:{display_name:"test-model"}, cost:{total_cost_usd:0.01}, effort:{level:"high"}, context_window:{current_usage:{input_tokens:1000}}}' \
  | HOME="$TMPDIR" bash "$STATUSLINE" 2>/dev/null)

assert_contains "output contains type" "ticket" "$output"
assert_contains "output contains ticket_type" "feature" "$output"
assert_contains "output contains column" "in dev" "$output"
assert_contains "output contains session name" "test session" "$output"
assert_contains "running step follows the column" "in dev · /ready-for-cr" "$output"

printf "\nTest group: the step prints on its own, with no type or column beside it\n"

rm -f "$STATE_DIR/$SESSION_ID.type" "$STATE_DIR/$SESSION_ID.column"

output_step_only=$(jq -nc \
  --arg sn "test session" \
  --arg tp "$TRANSCRIPT_PATH" \
  '{session_name:$sn, transcript_path:$tp, model:{display_name:"test-model"}, cost:{total_cost_usd:0.01}, effort:{level:"high"}, context_window:{current_usage:{input_tokens:1000}}}' \
  | HOME="$TMPDIR" bash "$STATUSLINE" 2>/dev/null)

assert_contains "step without a column still prints" "/ready-for-cr" "$output_step_only"
assert_not_contains "no separator before a lone step" "· /ready-for-cr" "$output_step_only"

printf "\nTest group: type and column absent when no sidecar files exist\n"

rm -f "$STATE_DIR/$SESSION_ID.step"

output2=$(jq -nc \
  --arg sn "test session" \
  --arg tp "$TRANSCRIPT_PATH" \
  '{session_name:$sn, transcript_path:$tp, model:{display_name:"test-model"}, cost:{total_cost_usd:0.01}, effort:{level:"high"}, context_window:{current_usage:{input_tokens:1000}}}' \
  | HOME="$TMPDIR" bash "$STATUSLINE" 2>/dev/null)

assert_not_contains "no type without .type file" "ticket" "$output2"
assert_not_contains "no ticket_type without .type file" "feature" "$output2"
assert_not_contains "no column without .column file" "in dev" "$output2"
assert_not_contains "no step without .step file" "/ready-for-cr" "$output2"

printf "\n%d passed, %d failed\n" "$pass" "$fail"
[ "$fail" -eq 0 ]
