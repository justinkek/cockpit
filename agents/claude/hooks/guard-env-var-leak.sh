#!/usr/bin/env bash

input="$(cat)"
tool="$(printf '%s' "$input" | jq -r '.tool_name // empty' 2>/dev/null)"
cmd="$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null)"

[ "$tool" = "Bash" ] || exit 0
[ -n "$cmd" ] || exit 0

deny() {
  jq -nc --arg r "$1" \
    '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'
  exit 0
}

allow() {
  jq -nc --arg r "$1" \
    '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"allow",permissionDecisionReason:$r}}'
  exit 0
}

is_sensitive() {
  local upper
  upper="$(printf '%s' "$1" | tr '[:lower:]' '[:upper:]')"
  case "$upper" in
    *SECRET*|*TOKEN*|*PASSWORD*|*PASSWD*) return 0 ;;
    *CREDENTIAL*|*PASSPHRASE*) return 0 ;;
    *PRIVATE_KEY*|*API_KEY*|*APIKEY*|*ACCESS_KEY*) return 0 ;;
    *SIGNING_KEY*|*ENCRYPTION_KEY*|*MASTER_KEY*) return 0 ;;
    *) return 1 ;;
  esac
}

# Strip leading cd prefix, get first token.
stripped="$(printf '%s' "$cmd" \
  | sed -E 's/^[[:space:]]*//; s/^(cd[[:space:]]+[^&;|]+([&;]{1,2}|\|\|)[[:space:]]*)+//')"
first="$(printf '%s' "$stripped" | awk '{print $1; exit}')"

# --- Case 1: full env dump ---
case "$first" in
  printenv)
    # Strip command name + optional flags, get first positional arg.
    arg="$(printf '%s' "$stripped" \
      | sed -E 's/^printenv[[:space:]]*//' \
      | sed -E 's/^-[[:alpha:]0]+[[:space:]]*//' \
      | awk '{print $1; exit}')"
    # Valid var name starts with letter/underscore; anything else (empty,
    # pipe, redirect) means a full dump.
    case "$arg" in
      [A-Za-z_]*)
        is_sensitive "$arg" && deny "Refusing \`printenv $arg\` — references a sensitive env var."
        allow "Allowed: \`printenv $arg\` — non-sensitive env var read."
        ;;
      *)
        deny "Refusing \`printenv\` — dumps all environment variables including secrets. Use \`printenv VAR_NAME\` for a specific variable."
        ;;
    esac
    ;;
  env)
    rest="$(printf '%s' "$stripped" \
      | sed -E 's/^env[[:space:]]*//' \
      | sed -E 's/^-[[:alpha:]0]+[[:space:]]*//')"
    case "$rest" in
      ""|"|"*|">"*|"&"*|";"*)
        deny "Refusing \`env\` — dumps all environment variables including secrets."
        ;;
    esac
    # env with args (VAR=val or command) is not a dump.
    exit 0
    ;;
  set)
    rest="$(printf '%s' "$stripped" | sed -E 's/^set[[:space:]]*//')"
    [ -z "$rest" ] && deny "Refusing \`set\` — dumps all shell variables including secrets."
    exit 0
    ;;
  export)
    rest="$(printf '%s' "$stripped" | sed -E 's/^export[[:space:]]*//')"
    case "$rest" in
      ""|"-p"|"-p "*)
        deny "Refusing \`export -p\` — dumps all exported variables including secrets."
        ;;
    esac
    exit 0
    ;;
  declare)
    rest="$(printf '%s' "$stripped" | sed -E 's/^declare[[:space:]]*//')"
    case "$rest" in
      "-x"|"-x "*|"-px"|"-px "*|"-xp"|"-xp "*)
        deny "Refusing \`declare -x\` — dumps all exported variables including secrets."
        ;;
    esac
    exit 0
    ;;
esac

# --- Case 2: sensitive $VAR references in output commands ---
case "$first" in
  echo|printf) ;;
  *) exit 0 ;;
esac

# Strip single-quoted spans (no var expansion inside single quotes).
residue="$(printf '%s' "$cmd" | sed -E "s/'[^']*'//g")"

# Extract $VAR and ${VAR} references.
vars="$(printf '%s' "$residue" \
  | grep -oE '\$\{?[A-Za-z_][A-Za-z_0-9]*\}?' \
  | sed -E 's/^\$\{?//; s/\}$//' \
  | sort -u)"

[ -n "$vars" ] || exit 0

while IFS= read -r var; do
  [ -z "$var" ] && continue
  is_sensitive "$var" && deny "Refusing \`$first\` — references sensitive env var \$$var."
done <<< "$vars"

exit 0
