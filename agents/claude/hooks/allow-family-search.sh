#!/usr/bin/env bash

set -f   # no glob expansion when iterating command tokens

input="$(cat)"
tool="$(printf '%s' "$input" | jq -r '.tool_name // empty'         2>/dev/null)"
cwd="$(printf '%s'  "$input" | jq -r '.cwd // empty'               2>/dev/null)"
cmd="$(printf '%s'  "$input" | jq -r '.tool_input.command // empty' 2>/dev/null)"
[ "$tool" = "Bash" ] || exit 0
[ -n "$cmd" ] || exit 0
cwd="${cwd:-$PWD}"

# 1. leading search verb (after stripping a `cd … &&` prefix)
first="$(printf '%s' "$cmd" \
  | sed -E 's/^[[:space:]]*//; s/^(cd[[:space:]]+[^&;|]+([&;]{1,2}|\|\|)[[:space:]]*)+//' \
  | awk '{print $1; exit}')"
case "$first" in
  find|grep|egrep|fgrep|rg) ;;
  *) exit 0 ;;
esac

# 2. strip quoted spans, then reject pipe/compound/redirect/subshell
residue="$(printf '%s' "$cmd" | sed -E "s/'[^']*'//g; s/\"[^\"]*\"//g")"
case "$residue" in
  *'|'*|*'&'*|*';'*|*'<'*|*'>'*|*'`'*|*'$('*) exit 0 ;;
esac

# 3. find with execution/mutation predicates -> defer
if [ "$first" = "find" ]; then
  case " $residue " in
    *' -exec'*|*' -delete'*|*' -ok'*|*' -fprint'*) exit 0 ;;
  esac
fi

# 4. family roots = every worktree of this repo (+ the toplevel)
roots=""
while IFS= read -r l; do
  case "$l" in
    "worktree "*) p="${l#worktree }"; rp="$(cd "$p" 2>/dev/null && pwd -P)"
                  [ -n "$rp" ] && roots="$roots
$rp" ;;
  esac
done < <(git -C "$cwd" worktree list --porcelain 2>/dev/null)
top="$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null)"
[ -n "$top" ] && roots="$roots
$(cd "$top" 2>/dev/null && pwd -P)"
[ -n "$(printf '%s' "$roots" | tr -d '[:space:]')" ] || exit 0   # not a repo -> defer

canon() {  # absolute-ish path -> resolved absolute (need not exist)
  local p="$1" dir base tail=""
  case "$p" in "~") p="$HOME" ;; "~/"*) p="$HOME/${p#\~/}" ;; esac
  case "$p" in /*) ;; *) p="$cwd/$p" ;; esac
  dir="$p"
  while [ ! -d "$dir" ]; do base="$(basename "$dir")"; dir="$(dirname "$dir")"; tail="$base${tail:+/}$tail"; [ "$dir" = "/" ] && break; done
  if cd "$dir" 2>/dev/null; then dir="$(pwd -P)"; [ -n "$tail" ] && printf '%s/%s' "$dir" "$tail" || printf '%s' "$dir"; else printf '%s' "$p"; fi
}

in_family() {  # 0 if $1 is under a family root
  local t="$1" r
  while IFS= read -r r; do
    [ -z "$r" ] && continue
    case "$t" in "$r"|"$r"/*) return 0 ;; esac
  done <<EOF
$roots
EOF
  return 1
}

# 5. every absolute path token must be inside the family (relative paths are
#    under cwd, which is itself a family root)
for tok in $residue; do
  case "$tok" in
    /*|"~/"*|"~") in_family "$(canon "$tok")" || exit 0 ;;
  esac
done

# 6. safe -> allow (silences the out-of-workspace prompt)
jq -nc --arg r "Allowed: standalone $first within the repo family (current + sibling/main worktrees)." \
  '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"allow",permissionDecisionReason:$r}}'
exit 0
