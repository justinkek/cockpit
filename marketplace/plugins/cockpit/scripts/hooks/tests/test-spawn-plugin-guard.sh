#!/usr/bin/env bash

export CLAUDE_SHARED_DIR="$(cd "$(dirname "$0")/../../../../../../agents/claude" && pwd)"

RESOLVER="$(cd "$(dirname "$0")/.." && pwd)/spawn-plugin-guard.sh"

pass=0
fail=0

report() {
  local label="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then
    printf "  OK  %s\n" "$label"
    pass=$((pass + 1))
  else
    printf "  KO  %s\n" "$label"
    printf "        expected: %s\n" "$expected"
    printf "        actual:   %s\n" "$actual"
    fail=$((fail + 1))
  fi
}

workspace="$(mktemp -d)"
trap 'rm -rf "$workspace"' EXIT

mkdir -p "$workspace/marketplaces/tech-ref/plugins/tech-ref/hooks"
guard="$workspace/marketplaces/tech-ref/plugins/tech-ref/hooks/guard-tech-steps.sh"
printf '#!/usr/bin/env bash\njq --raw-output '"'"'"\\(.tool_name): \\(.tool_input.content)"'"'"'\n' > "$guard"
chmod +x "$guard"

bash_call() {
  jq --null-input --compact-output --arg command "$1" \
    '{session_id:"guard-test",hook_event_name:"PreToolUse",tool_name:"Bash",tool_input:{command:$command}}'
}

section_write() {
  printf '%s\n' "\"\$HOME/.cockpit/scripts/board-card\" section FEAT-3 $1 <<'EOF'" '+ the tree' 'EOF'
}

run() {
  bash_call "$1" | COCKPIT_PLUGIN_SEARCH_ROOT="$workspace" "$RESOLVER" "${2:-guard-tech-steps.sh}"
}

printf "Test group: a board write reaches the plugin's guard as a file write\n"

report "a Tech Steps section arrives under its heading" \
  "Write: ## Tech Steps
+ the tree" \
  "$(run "$(section_write '"Tech Steps"')")"

report "a heading given with its marker is the same section" \
  "Write: ## Tech Steps
+ the tree" \
  "$(run "$(section_write '"## Tech Steps" --after Context')")"

report "a whole body arrives as it was written" \
  "Write: ## Tech Steps
+ the body" \
  "$(run "$(printf '%s\n' "\"\$HOME/.cockpit/scripts/board-card\" set FEAT-3 body \"\$(cat <<'EOF'" '## Tech Steps' '+ the body' 'EOF' ')"')")"

printf "\nTest group: anything else never reaches it\n"

report "another section is silent" "" "$(run "$(section_write Context)")"
report "another board command is silent" "" "$(run '"$HOME/.cockpit/scripts/board-card" show FEAT-3 --section "Tech Steps"')"
report "a command that is not the board's is silent" "" "$(run 'echo "Tech Steps"')"
report "a tool that is not Bash is silent" "" \
  "$(jq --null-input --compact-output '{tool_name:"Write",tool_input:{content:"## Tech Steps"}}' \
    | COCKPIT_PLUGIN_SEARCH_ROOT="$workspace" "$RESOLVER" guard-tech-steps.sh)"
report "a guard no plugin carries says so to the agent and the person" \
  "[cockpit] guard-validation-steps.sh is installed in no plugin on this account, so this write to the card went unchecked - run sync.sh plugins --apply|PreToolUse|true" \
  "$(run "$(section_write '"Tech Steps"')" guard-validation-steps.sh \
    | jq --raw-output '"\(.hookSpecificOutput.additionalContext)|\(.hookSpecificOutput.hookEventName)|\(.systemMessage == .hookSpecificOutput.additionalContext)"')"
report "a guard missing on another board command stays silent" "" \
  "$(run "$(section_write Context)" guard-validation-steps.sh)"
report "a guard missing outside a plugin hook stays silent" "" \
  "$(bash_call "$(section_write '"Tech Steps"')" | CLAUDE_PLUGIN_ROOT= "$RESOLVER" guard-validation-steps.sh)"
report "no guard named is silent" "" \
  "$(bash_call "$(section_write '"Tech Steps"')" | COCKPIT_PLUGIN_SEARCH_ROOT="$workspace" "$RESOLVER")"

chmod -x "$guard"
report "a guard that is not executable says so" \
  "[cockpit] guard-tech-steps.sh is not executable on this account, so this write to the card went unchecked - run sync.sh plugins --apply" \
  "$(run "$(section_write '"Tech Steps"')" | jq --raw-output '.hookSpecificOutput.additionalContext')"

printf "\n%d passed, %d failed\n" "$pass" "$fail"
[ "$fail" -eq 0 ]
