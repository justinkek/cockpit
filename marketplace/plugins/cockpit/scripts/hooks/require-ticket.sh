#!/usr/bin/env bash

. "${CLAUDE_SHARED_DIR:-$HOME/.claude-shared}/hooks/hook-argv-lib.sh"

input="$(cat)"

if command -v jq >/dev/null 2>&1; then
  tool="$(printf '%s' "$input" | jq -r '.tool_name // empty')"
  session_id="$(printf '%s' "$input" | jq -r '.session_id // empty')"
  cmd="$(printf '%s' "$input" | jq -r '.tool_input.command // empty')"
else
  tool="$(printf '%s' "$input" | sed -n 's/.*"tool_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')"
  session_id="$(printf '%s' "$input" | sed -n 's/.*"session_id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')"
  cmd="$(printf '%s' "$input" | sed -n 's/.*"command"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')"
fi

# No session id (shouldn't happen) -> defer rather than brick the session.
[ -n "$session_id" ] || exit 0

STATE_DIR="$HOME/.local/state/claude-ticket-sessions"
mkdir -p "$STATE_DIR"
find "$STATE_DIR" -type f -mtime +7 -delete 2>/dev/null

# The heartbeat the claim expiry reads. A claim is held from pickup to Done now,
# so the column a card sits in no longer says whether its holder is alive — this
# file does. Written here because this hook is the one component that reliably
# knows the session id, and it fires on every tool call that changes something,
# so a working session beats constantly. A session killed without SessionEnd
# firing stops beating at once. Written before any gate below: a denied call
# still proves the session is alive.
touch "$STATE_DIR/$session_id.alive"

marker="$STATE_DIR/$session_id.ticket"

# Intercept the registration command: write the marker, then auto-approve it.
# The registration call is forced by this very gate, so prompting on it is a
# self-inflicted loop. Approve it silently — but only when the command is
# *nothing but* a ticket-register invocation: strip quoted substrings and bail
# on any pipe/redirect/chaining/subshell, and require the first token to be a
# ticket-register script. A command that merely contains the substring, or
# tacks shell metacharacters onto it, still defers to the normal prompt.
#
# Ordering matters: the marker is written BEFORE the shape gate, so the gate
# decides only whether to auto-approve — never whether state is recorded. A
# compound invocation (`ticket-register-column "In Dev" && ...`) still lands
# its sidecar, then falls through to the prompt. This mirrors
# require-dev-status.sh, which writes its stage marker before its own shape
# checks. Writing on a command the user then denies leaves a marker for a move
# that did not happen — accepted: the sidecars record intent, and a stale
# marker is repaired by the next status hop, whereas a missing one is silent.
if [ "$tool" = "Bash" ] && printf '%s' "$cmd" | grep -q 'ticket-register'; then
  residue="$(printf '%s' "$cmd" | sed -E "s/'[^']*'//g; s/\"[^\"]*\"//g")"
  first="$(printf '%s' "$cmd" | sed -E 's/^[[:space:]]*//' | awk '{print $1}' | tr -d '"'"'")"

  # Which script is invoked? Matched anywhere in the command, not just as the
  # first token, so a chained invocation is still recognised. Longest name
  # first: the -column / -type variants must win over the
  # bare ticket-register prefix they all share.
  case "$cmd" in
    *.cockpit/scripts/ticket-register-column*)        _script=column ;;
    *.cockpit/scripts/ticket-register-type*)          _script=type ;;
    *.cockpit/scripts/ticket-register*)               _script=ticket ;;
    *) exit 0 ;;
  esac

  # Arguments come back as shell words (hook-argv-lib.sh), never as regex
  # captures: quoting an argument or not stops changing whether it is read,
  # and a script name echoed inside a quoted argument — a session named after
  # the very command being run — can no longer be mistaken for the command
  # token. Absent arguments come back empty, so emptiness is the only guard
  # each branch needs.
  case "$_script" in
    column)
      _rcol="$(hook_argv_after "$cmd" ticket-register-column | sed -n 1p)"
      if [ -n "$_rcol" ]; then
        printf '%s\n' "$_rcol" > "$STATE_DIR/$session_id.column"
      fi
      reason="ticket-register-column (board column) — allowed"
      ;;
    type)
      _rargs="$(hook_argv_after "$cmd" ticket-register-type)"
      _rtype="$(printf '%s\n' "$_rargs" | sed -n 1p)"
      _rname="$(printf '%s\n' "$_rargs" | sed -n 2p)"
      _rttype="$(printf '%s\n' "$_rargs" | sed -n 3p)"
      if [ -n "$_rtype" ] && [ -n "$_rname" ]; then
        printf 'type=%s\nname=%s\n' "$_rtype" "$_rname" > "$STATE_DIR/$session_id.type"
        [ -n "$_rttype" ] && printf 'ticket_type=%s\n' "$_rttype" >> "$STATE_DIR/$session_id.type"
      fi
      reason="ticket-register-type (work item type) — allowed"
      ;;
    ticket)
      _rurl="$(hook_argv_after "$cmd" ticket-register | sed -n 1p)"
      case "$_rurl" in
        https://*) printf '%s\n' "$_rurl" > "$marker" ;;
        *) printf '%s' "$_rurl" | grep --quiet --extended-regexp '^[A-Z][A-Z0-9]*-[0-9]+$' && printf '%s\n' "$_rurl" > "$marker" ;;
      esac
      reason="ticket-register (session registration) — allowed"
      ;;
  esac

  # Shape gate: auto-approve only a standalone invocation. Anything chained or
  # redirected defers to the normal prompt — with its sidecar already written.
  case "$residue" in *'|'*|*'&'*|*';'*|*'<'*|*'>'*|*'`'*|*'$('*) exit 0 ;; esac
  case "$first" in *.cockpit/scripts/ticket-register*) ;; *) exit 0 ;; esac

  if command -v jq >/dev/null 2>&1; then
    jq -nc --arg r "$reason" \
      '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"allow",permissionDecisionReason:$r}}'
  else
    printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow","permissionDecisionReason":"%s"}}\n' "$reason"
  fi
  exit 0
fi

# Cross-allow: let the copilot skill work out which ticket to register. Every
# one of these runs before a ticket exists, because they are how it is chosen.
# ticket-claim-lock and board-card claim write one known thing each, which is
# why they are named here one by one rather than by a pattern that would let
# anything through.
if [ "$tool" = "Bash" ] && printf '%s' "$cmd" | grep -qE 'ticket-claim-lock|ticket-waiting-cards'; then
  first="$(printf '%s' "$cmd" | sed -E 's/^[[:space:]]*//' | awk '{print $1}' | tr -d '"'"'")"
  case "$first" in *.cockpit/scripts/ticket-claim-lock|*.cockpit/scripts/ticket-waiting-cards) exit 0 ;; esac
fi

if [ "$tool" = "Bash" ] && printf '%s' "$cmd" | grep -q 'board-card'; then
  first="$(printf '%s' "$cmd" | sed -E 's/^[[:space:]]*//' | awk '{print $1}' | tr -d '"'"'")"
  subcommand="$(printf '%s' "$cmd" | sed -E 's/^[[:space:]]*//' | awk '{print $2}' | tr -d '"'"'")"
  case "$first" in
    *.cockpit/scripts/board-card)
      case "$subcommand" in show|list|statuses|path|claim|create) exit 0 ;; esac
      ;;
  esac
fi

# Cross-allow: let auto-rename through without writing the ticket marker.
# Without this, auto-rename is denied by the ticket gate before the rename
# gate can intercept it — a chicken-and-egg deadlock between the two hooks.
if [ "$tool" = "Bash" ] && printf '%s' "$cmd" | grep -q 'auto-rename'; then
  first="$(printf '%s' "$cmd" | sed -E 's/^[[:space:]]*//' | awk '{print $1}' | tr -d '"'"'")"
  case "$first" in *.cockpit/scripts/auto-rename) exit 0 ;; esac
fi

# A command that only reads is not a mutation. exit 0 is "no opinion": the
# normal allowlist or permission prompt still decides.
if [ "$tool" = "Bash" ] && hook_is_readonly_bash "$cmd"; then
  exit 0
fi

[ -f "$marker" ] && exit 0

reason="No cockpit ticket registered for this session — Edit/Write/Agent and shell commands that change something are DENIED until one is. Commands that only read are free. Assistant: do not reply to the user, retry this command, or work around the block — invoke the ticket skill NOW to register (use /cockpit:ticket:0:register in Claude or \$ticket in Codex; it resolves or creates the ticket stub, links or raises an epic if missing, then unlocks the session). Registration is the only door; there is no override."
if command -v jq >/dev/null 2>&1; then
  jq -nc --arg r "$reason" \
    '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'
else
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"%s"}}\n' "$reason"
fi
exit 0
