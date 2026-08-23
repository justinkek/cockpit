#!/usr/bin/env bash

input="$(cat)"
tool="$(printf '%s' "$input" | jq -r '.tool_name // empty'        2>/dev/null)"
cmd="$(printf '%s'  "$input" | jq -r '.tool_input.command // empty' 2>/dev/null)"

[ "$tool" = "Bash" ] || exit 0
[ -n "$cmd" ] || exit 0

# Keychain reads, checked before anything else and against the RAW command.
# `Bash(security:*)` in permissions.deny only matches a command that starts
# with the bare word, so `/usr/bin/security find-generic-password …` and
# `bash -c "security find-generic-password …"` both walk straight past it.
# Matching the subcommand anywhere — quoted spans included, which is why this
# runs before the residue stripping below — closes every shape at once.
#
# Writes are denied alongside reads. Storing a credential is the user's setup
# step, run with the `!` prefix in their own shell where hooks do not apply, so
# denying it here costs the agent nothing it should have been doing. The bare
# word `security` is not matched: it appears in commit messages and paths far
# more often than as this binary. The subcommands are unambiguous.
case "$cmd" in
  *-generic-password*|*-internet-password*|*dump-keychain*|*keychain-password*|*security\ export*)
    reason="Refusing this command — it touches the macOS Keychain. Reading one would put a credential's plaintext in the transcript; writing one is your setup step, not the agent's. Run it yourself with the \`!\` prefix."
    jq -nc --arg r "$reason" \
      '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'
    exit 0 ;;
esac

# Leading command token, after stripping a `cd … &&` prefix.
first="$(printf '%s' "$cmd" \
  | sed -E 's/^[[:space:]]*//; s/^(cd[[:space:]]+[^&;|]+([&;]{1,2}|\|\|)[[:space:]]*)+//' \
  | awk '{print $1; exit}')"
case "$first" in
  grep|egrep|fgrep|rg|awk|strings|od|xxd|nl|tac|find|jq|diff|ls|readlink|wc|command) ;;
  *) exit 0 ;;
esac

# Strip quoted spans and committed example env names (.env.example etc. are
# readable by design), then look for a secret-file reference in what remains.
residue="$(printf '%s' "$cmd" \
  | sed -E "s/'[^']*'//g; s/\"[^\"]*\"//g" \
  | sed -E 's/\.env\.(example|sample|template|dist)//g')"
case "$residue" in
  *.env*|*.pem*|*.key*|*id_rsa*|*id_ed25519*|*.npmrc*|*.netrc*|*/.ssh*|*/.aws*|*/.config/gcloud*|*credentials*) ;;
  *) exit 0 ;;
esac

reason="Refusing Bash \`$first\` — it references a secret file. Unlike cat/head/tail/sed, this command isn't covered by the permission deny rules and would bypass them. Use the Read tool, or adjust the deny rules if this is a false positive."
jq -nc --arg r "$reason" \
  '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'
exit 0
