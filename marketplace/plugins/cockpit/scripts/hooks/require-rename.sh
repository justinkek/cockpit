#!/usr/bin/env bash

. "${CLAUDE_SHARED_DIR:-$HOME/.claude-shared}/hooks/hook-argv-lib.sh"

sole_invocation_words() {
  printf '%s' "$2" | awk -v mode="$1" -v readers="$HOOK_READONLY_CMDS" '
    function close_word(  name) {
      if (!inword) return
      if (segment == 1) words[++count] = word
      else if (reader_due) {
        name = word
        sub(/^.*\//, "", name)
        if (!(name in reader)) exit 1
        reader_due = 0
      }
      word = ""
      inword = 0
    }
    { s = s (NR > 1 ? "\n" : "") $0 }
    END {
      split(readers, list, " ")
      for (j in list) reader[list[j]] = 1
      if (mode == "approve" && index(s, "\n")) exit 1
      n = length(s)
      i = 1
      segment = 1
      while (i <= n) {
        c = substr(s, i, 1)
        two = substr(s, i, 2)
        if (quote == "\047") {
          if (c == "\047") quote = ""; else word = word c
          i++
          continue
        }
        if (c == "\\" || c == "`" || two == "$(") exit 1
        if (two == "${") {
          if (!match(substr(s, i), /^\$\{[A-Za-z_][A-Za-z0-9_]*\}/)) exit 1
          word = word substr(s, i, RLENGTH)
          inword = 1
          i += RLENGTH
          continue
        }
        if (quote == "\"") {
          if (c == "\"") quote = ""; else word = word c
          i++
          continue
        }
        if (two == "$\047" || (c == "#" && !inword)) exit 1
        if (c == "\047" || c == "\"") {
          quote = c
          inword = 1
          i++
          continue
        }
        if (c == " " || c == "\t") {
          close_word()
          i++
          continue
        }
        if (c == "\n") {
          close_word()
          i++
          if (delimiter != "") {
            while (i <= n) {
              line_end = index(substr(s, i), "\n")
              line = line_end ? substr(s, i, line_end - 1) : substr(s, i)
              i = line_end ? i + line_end : n + 1
              if (strip) sub(/^\t+/, "", line)
              if (line == delimiter) break
            }
            delimiter = ""
          }
          if (substr(s, i) !~ /^[ \t\n]*$/) exit 1
          break
        }
        if (mode == "let-through" && c == "|") {
          after = substr(s, i + 1, 1)
          if (after == "|" || after == "&") exit 1
          close_word()
          if (count == 0 || reader_due) exit 1
          segment++
          reader_due = 1
          i++
          continue
        }
        if (mode == "let-through" && two == "<<" && !heredoc) {
          close_word()
          i += 2
          if (substr(s, i, 1) == "-") {
            strip = 1
            i++
          }
          while (substr(s, i, 1) == " " || substr(s, i, 1) == "\t") i++
          if (!match(substr(s, i), /^\047[A-Za-z_][A-Za-z0-9_]*\047/) && !match(substr(s, i), /^"[A-Za-z_][A-Za-z0-9_]*"/)) exit 1
          delimiter = substr(s, i + 1, RLENGTH - 2)
          heredoc = 1
          i += RLENGTH
          after = substr(s, i, 1)
          if (after != "" && after != " " && after != "\t" && after != "\n" && after != "|") exit 1
          continue
        }
        if (index(";&|<>()", c)) exit 1
        word = word c
        inword = 1
        i++
      }
      if (quote != "") exit 1
      close_word()
      if (reader_due) exit 1
      for (j = 1; j <= count; j++) print words[j]
    }'
}

names_cockpit_script() {
  local word="$1" name
  shift
  for name in "$@"; do
    case "$word" in
      "\$HOME/.cockpit/scripts/$name" | "\${HOME}/.cockpit/scripts/$name" | "~/.cockpit/scripts/$name" | "$HOME/.cockpit/scripts/$name") return 0 ;;
    esac
  done
  return 1
}

input="$(cat)"

if command -v jq >/dev/null 2>&1; then
  tool="$(printf '%s' "$input" | jq -r '.tool_name // empty')"
  session_id="$(printf '%s' "$input" | jq -r '.session_id // empty')"
  transcript="$(printf '%s' "$input" | jq -r '.transcript_path // empty')"
  cmd="$(printf '%s' "$input" | jq -r '.tool_input.command // empty')"
else
  tool="$(printf '%s' "$input" | sed -n 's/.*"tool_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')"
  session_id="$(printf '%s' "$input" | sed -n 's/.*"session_id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')"
  transcript="$(printf '%s' "$input" | sed -n 's/.*"transcript_path"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')"
  cmd="$(printf '%s' "$input" | sed -n 's/.*"command"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')"
fi

invocation="$(sole_invocation_words let-through "$cmd")"
first="$(printf '%s\n' "$invocation" | sed -n 1p)"
subcommand="$(printf '%s\n' "$invocation" | sed -n 2p)"

# No session id (shouldn't happen) -> defer rather than brick the session.
[ -n "$session_id" ] || exit 0

STATE_DIR="$HOME/.local/state/claude-rename-gate"
mkdir -p "$STATE_DIR"
find "$STATE_DIR" -type f -mtime +7 -delete 2>/dev/null

marker="$STATE_DIR/$session_id"

# Intercept the auto-rename command: write the custom-title record to the
# transcript, create the marker, and auto-approve. Same pattern as
# require-ticket.sh's intercept of ticket-register.
if [ "$tool" = "Bash" ] && printf '%s' "$cmd" | grep -q 'auto-rename'; then
  # The session name is the first argument after the script token — read as a
  # shell word, so a name that itself contains "auto-rename" cannot be
  # mistaken for the command token (see hook-argv-lib.sh).
  name="$(hook_argv_after "$cmd" auto-rename | sed -n 1p)"

  if [ -n "$name" ] && [ -n "$transcript" ] && [ -f "$transcript" ]; then
    printf '{"type":"custom-title","customTitle":"%s","sessionId":"%s"}\n' \
      "$name" "$session_id" >> "$transcript"
  fi

  : > "$marker"

  # Validate: only auto-approve clean invocations of the auto-rename script.
  names_cockpit_script "$(sole_invocation_words approve "$cmd" | sed -n 1p)" auto-rename || exit 0

  reason="auto-rename (session naming) — allowed"
  if command -v jq >/dev/null 2>&1; then
    jq -nc --arg r "$reason" \
      '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"allow",permissionDecisionReason:$r}}'
  else
    printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow","permissionDecisionReason":"%s"}}\n' "$reason"
  fi
  exit 0
fi

[ -f "$marker" ] && exit 0

# Cross-allow: let the copilot skill work out which ticket to take. The name
# comes from that ticket, so every one of these necessarily runs before the
# session has a name. ticket-claim-lock and board-card claim write one known
# thing each, which is why they are named here one by one rather than by a
# pattern that would let anything through.
if [ "$tool" = "Bash" ] && printf '%s' "$cmd" | grep -qE 'ticket-claim-lock|ticket-waiting-cards'; then
  names_cockpit_script "$first" ticket-claim-lock ticket-waiting-cards && exit 0
fi

if [ "$tool" = "Bash" ] && printf '%s' "$cmd" | grep -q 'board-card'; then
  if names_cockpit_script "$first" board-card; then
    case "$subcommand" in show|list|statuses|path|claim|create) exit 0 ;; esac
  fi
fi

# Cross-allow: let ticket-register through without writing the rename marker.
# Without this, ticket-register is denied by the rename gate before the ticket
# gate can intercept it — a chicken-and-egg deadlock between the two hooks.
if [ "$tool" = "Bash" ] && printf '%s' "$cmd" | grep -q 'ticket-register'; then
  names_cockpit_script "$first" ticket-register ticket-register-type && exit 0
fi

# A command that only reads is not a mutation, and looking around is exactly
# what a session does before it knows what to call itself. exit 0 is "no
# opinion": the normal allowlist or permission prompt still decides.
if [ "$tool" = "Bash" ] && hook_is_readonly_bash "$cmd"; then
  exit 0
fi

# Check transcript for a custom-title record (written by /rename or auto-rename).
if [ -n "$transcript" ] && [ -f "$transcript" ] && grep -q '"type":"custom-title"' "$transcript"; then
  : > "$marker"
  exit 0
fi

reason="This session has no name yet — Edit/Write/Agent and shell commands that change something are DENIED until it is named. Commands that only read are free. Assistant: do not reply to the user, retry this tool call, or work around the block — derive a name and run \$HOME/.cockpit/scripts/auto-rename NOW, passing the name as its single quoted argument. Read \$HOME/.claude-shared/templates/session-name.md for the name to pass — it is the one place the convention is stated, and reading is free while the session is unnamed. This hook intercepts that call, records the name, and unlocks the session; naming is self-serve. Ask the user for a name only when nothing in the session gives you a basis for one."
if command -v jq >/dev/null 2>&1; then
  jq -nc --arg r "$reason" \
    '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'
else
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"%s"}}\n' "$reason"
fi
exit 0
