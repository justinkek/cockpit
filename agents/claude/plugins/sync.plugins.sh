#!/usr/bin/env bash
#
# sync.plugins.sh — keep Claude Code plugins consistent across accounts.
#
# Default / --check: REPORT-ONLY — surface version drift + install health so you
# can fix things deliberately. --apply: reconcile each account to the declared
# state in base.plugins.json (track-latest; safe — never `marketplace remove`).
#
# Accounts (see ACCOUNTS below):
#   claude          — ~/.claude, the DEFAULT config dir. It's NOT dead: the
#                     Claude Code DESKTOP app uses it (it launches outside the
#                     wrappers, so it defaults there). It's a real managed
#                     account; warp is enabled-but-silent in the GUI (no terminal
#                     to emit notifications to) — harmless.
#
# Each account loads the version pinned in its own
#   <config-dir>/plugins/installed_plugins.json
# which only changes when you run `/plugin` update (or this script's --apply) —
# marketplace git clones do NOT auto-pull. So two accounts can silently diverge
#
# Checks:
#   1. cross-account  (offline, default): flag any plugin whose installed
#                     version differs across accounts.
#   2. install health (offline, default): for every install record AND every
#                     registered marketplace, flag
#                     - NOT CACHED / MISSING: the installPath cache dir (or the
#                       marketplace installLocation) is absent/empty — the plugin
#                       will error on session start (the "Plugin not cached"
#                       error the /plugins UI shows), and
#                     - FOREIGN:    the path lives under a DIFFERENT account's
#                       config dir — the
#                       latent coupling that lets one account silently break
#                       another.
#   3. upstream       (--remote): git-fetch each marketplace clone (no merge)
#                     and flag clones whose HEAD is behind origin — catches the
#                     case where ALL accounts are equally stale vs upstream.
#
# Usage: sync.plugins.sh [--check|--apply] [--only <acct>] [--remote]
#   (default)  report drift + install health; exit 0 regardless (so a full
#              `sync.sh` run isn't failed just because a plugin is behind).
#   --check    report only; exit 1 if any drift/health issue found (hooks / CI).
#   --apply    reconcile each account to base.plugins.json: add missing
#              marketplaces, (re)install declared plugins at the declared scope
#              (track-latest), then report. Never `marketplace remove` (cascades).
#   --only <acct>  limit --apply/report to one account (e.g. after a fresh
#              ~/.claude is created by the desktop app: --apply --only claude).
#   --remote   also fetch marketplace clones and report upstream staleness.
#   --yes / -y accepted and ignored (apply is already non-interactive).
#
# NOTE: kept bash-3.2 compatible (macOS /bin/bash) — no associative arrays,
# no mapfile. State is held in newline-delimited strings processed with awk.
#
set -euo pipefail

# Account taxonomy (ACCOUNTS + acct_dir) is centralized in accounts.sh, shared
# by every concern's sync script (see notes there on the ~/.claude desktop app).
source "${CLAUDE_SHARED_DIR:-$HOME/.claude-shared}/accounts.sh"

MODE="report"
REMOTE=0
ONLY=""        # limit apply/report to a single account (for targeted runs)
prev=""
for arg in "$@"; do
  if [ "$prev" = "--only" ]; then ONLY="$arg"; prev=""; continue; fi
  case "$arg" in
    --check)   MODE="check" ;;
    --apply)   MODE="apply" ;;            # reconcile to base.plugins.json (mutates)
    --remote)  REMOTE=1 ;;
    --only)    prev="--only" ;;           # --only <acct>
    --yes|-y)  ;;                         # accepted, ignored
    -h|--help) echo "usage: sync.plugins.sh [--check|--apply] [--only <acct>] [--remote]"; exit 0 ;;
    *) echo "error: unknown arg: $arg" >&2; exit 2 ;;
  esac
done

command -v jq >/dev/null || { echo "error: jq is required" >&2; exit 3; }

# Colors — only on a terminal (keeps pipes / hooks / CI clean).
if [ -t 1 ]; then
  C_RESET=$'\033[0m'; C_RED=$'\033[31m'; C_GREEN=$'\033[32m'
  C_YELLOW=$'\033[33m'; C_CYAN=$'\033[36m'; C_DIM=$'\033[2m'
else
  C_RESET=''; C_RED=''; C_GREEN=''; C_YELLOW=''; C_CYAN=''; C_DIM=''
fi

installed_for_one_repository() {
  case "$1" in
    project | local) return 0 ;;
    *) return 1 ;;
  esac
}

MANIFEST="${CLAUDE_PLUGINS_MANIFEST:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/base.plugins.json}"

served_from_this_repository() {
  case "$1" in
    ./*) return 0 ;;
    *) return 1 ;;
  esac
}

marketplace_source_path() {
  local repository
  if ! served_from_this_repository "$1"; then
    printf '%s' "$1"
    return 0
  fi
  repository="$(cd "$(dirname "$MANIFEST")/../../.." && pwd -P)" || return 1
  [ -d "$repository/${1#./}" ] || return 1
  printf '%s/%s' "$repository" "${1#./}"
}

locally_served_marketplaces() {
  jq --raw-output '.marketplaces | to_entries[] | select(.value | startswith("./")) | .key' "$MANIFEST" 2>/dev/null || true
}

LOCALLY_SERVED=" $(locally_served_marketplaces | tr '\n' ' ') "

served_from_the_manifest_repository() {
  case "$LOCALLY_SERVED" in
    *" $1 "*) return 0 ;;
    *) return 1 ;;
  esac
}

# --- apply: reconcile each account to base.plugins.json ----------------------
# Track-latest, and deliberately SAFE: never runs `marketplace remove` (that
# cascades — uninstalls the marketplace's plugins). It only adds missing
# marketplaces, (re)installs declared plugins at the declared scope to localise
# their cache, and `update`s ones already correct. A marketplace that's still
# FOREIGN is reported (by the health section below), to localise by hand —
# `marketplace remove <name>` then `add` then reinstall — since that cascade is
# too destructive to run unattended.
if [ "$MODE" = "apply" ]; then
  [ -f "$MANIFEST" ] || { echo "error: missing manifest: $MANIFEST" >&2; exit 3; }
  CLAUDE_BIN="${CLAUDE_BIN:-}"
  if [ -z "$CLAUDE_BIN" ]; then
    for c in "$HOME/.local/bin/claude" "$HOME/.claude/local/claude" /opt/homebrew/bin/claude /usr/local/bin/claude; do
      [ -x "$c" ] && { CLAUDE_BIN="$c"; break; }
    done
  fi
  [ -n "$CLAUDE_BIN" ] || { echo "error: claude CLI not found (set CLAUDE_BIN)" >&2; exit 3; }

  echo "${C_CYAN}-- applying declared plugin state (track-latest) --${C_RESET}"
  for acct in "${ACCOUNTS[@]}"; do
    [ -n "$ONLY" ] && [ "$acct" != "$ONLY" ] && continue
    dir="$(acct_dir "$acct")"
    [ -d "$dir" ] || continue
    export CLAUDE_CONFIG_DIR="$dir"
    echo "${C_DIM}# $acct${C_RESET}"

    # marketplaces: add if missing, else update (never remove)
    while read -r name source; do
      [ -n "$name" ] && [ -n "$source" ] || continue
      loc="$(jq -r --arg n "$name" '.[$n].installLocation // empty' "$dir/plugins/known_marketplaces.json" 2>/dev/null || true)"
      if [ -z "$loc" ]; then
        if ! source_path="$(marketplace_source_path "$source")"; then
          echo "  ${C_RED}! marketplace $name source '$source' is not a directory under $(dirname "$MANIFEST")/../../..${C_RESET}"
        elif "$CLAUDE_BIN" plugin marketplace add "$source_path" </dev/null >/dev/null 2>&1; then
          echo "  ${C_GREEN}+ marketplace $name added${C_RESET}"
        else
          echo "  ${C_RED}! marketplace $name add failed${C_RESET}"
        fi
      else
        "$CLAUDE_BIN" plugin marketplace update "$name" </dev/null >/dev/null 2>&1 || true
      fi
    done < <(jq -r '.marketplaces | to_entries[] | "\(.key) \(.value)"' "$MANIFEST")

    # plugins: ensure installed at declared scope, local & cached; else (re)install
    while read -r id scope; do
      [ -n "$id" ] && [ -n "$scope" ] || continue
      f="$dir/plugins/installed_plugins.json"
      path="$(jq -r --arg k "$id" --arg s "$scope" '(.plugins[$k] // []) | map(select(.scope==$s)) | .[0].installPath // empty' "$f" 2>/dev/null || true)"
      ok=0
      if [ -n "$path" ]; then
        case "$path/" in
          "$dir/"*) [ -n "$(find "$path" -mindepth 1 -print -quit 2>/dev/null)" ] && ok=1 ;;
        esac
      fi
      if [ "$ok" -eq 1 ]; then
        "$CLAUDE_BIN" plugin update "$id" </dev/null >/dev/null 2>&1 || true   # track-latest
      else
        "$CLAUDE_BIN" plugin uninstall "$id" --scope user --yes </dev/null >/dev/null 2>&1 || true
        if "$CLAUDE_BIN" plugin install "$id" -s "$scope" </dev/null >/dev/null 2>&1; then
          echo "  ${C_GREEN}+ $id installed ($scope)${C_RESET}"
        else
          echo "  ${C_RED}! $id install failed ($scope)${C_RESET}"
        fi
      fi
    done < <(jq -r '.plugins | to_entries[] | "\(.key) \(.value)"' "$MANIFEST")

    while IFS=$'\t' read -r plugin_id installed_scope record_root; do
      [ -n "$plugin_id" ] && [ -n "$installed_scope" ] || continue
      if installed_for_one_repository "$installed_scope"; then continue; fi
      [ -d "$record_root" ] || continue
      if (cd "$record_root" && "$CLAUDE_BIN" plugin uninstall "$plugin_id" --scope "$installed_scope" --yes </dev/null >/dev/null 2>&1); then
        echo "  ${C_GREEN}- $plugin_id removed ($installed_scope, no longer declared)${C_RESET}"
      else
        echo "  ${C_RED}! $plugin_id remove failed ($installed_scope)${C_RESET}"
      fi
    done < <(jq --raw-output --slurpfile manifest "$MANIFEST" '
        ($manifest[0].plugins | keys) as $declared
        | (.plugins // {}) | to_entries[]
        | .key as $installed
        | select($declared | index($installed) | not)
        | .value[]
        | "\($installed)\t\(.scope)\t\(.projectPath // ".")"' \
        "$dir/plugins/installed_plugins.json" 2>/dev/null)
  done
  echo
fi

# --- collect installed versions as "plugin acct version" lines ---------------
RECORDS=""        # newline-delimited: "<plugin-id> <acct> <comma-joined versions>"
PRESENT_ACCTS=""  # space-delimited list of accounts that have a manifest

for acct in "${ACCOUNTS[@]}"; do
  [ -n "$ONLY" ] && [ "$acct" != "$ONLY" ] && continue
  f="$(acct_dir "$acct")/plugins/installed_plugins.json"
  [ -f "$f" ] || continue
  PRESENT_ACCTS="$PRESENT_ACCTS $acct"
  while read -r plugin ver; do
    [ -n "$plugin" ] || continue
    RECORDS="$RECORDS$plugin $acct $ver"$'\n'
  done < <(jq -r '
      (.plugins // {}) | to_entries[]
      | .key as $p
      | (.value | map(.version) | unique | join(",")) as $v
      | "\($p) \($v)"' "$f" 2>/dev/null)
done

if [ -z "${PRESENT_ACCTS// /}" ]; then
  echo "${C_DIM}no installed_plugins.json found in any account${C_RESET}"
  exit 0
fi

# --- cross-account comparison ------------------------------------------------
drift=0
plugins="$(printf '%s' "$RECORDS" | awk 'NF{print $1}' | sort -u)"

while read -r plugin; do
  [ -n "$plugin" ] || continue
  n_distinct="$(printf '%s' "$RECORDS" | awk -v p="$plugin" '$1==p{print $3}' | sort -u | grep -c .)"
  row=""
  for acct in $PRESENT_ACCTS; do
    v="$(printf '%s' "$RECORDS" | awk -v p="$plugin" -v a="$acct" '$1==p && $2==a{print $3}')"
    if [ -n "$v" ]; then
      row="$row $acct=$v"
    else
      row="$row ${C_DIM}$acct=-${C_RESET}"
    fi
  done
  if [ "$n_distinct" -gt 1 ]; then
    drift=1
    echo "${C_YELLOW}△ $plugin  DRIFT${C_RESET}${row}"
    echo "    ${C_DIM}→ versions differ across accounts; sync.sh plugins --apply, then /plugin update in any account still behind${C_RESET}"
  else
    echo "${C_GREEN}✓ $plugin${C_RESET}${row}"
  fi
done <<< "$plugins"

# --- install health: cache present + local to the account --------------------
# Mirrors the /plugins "Errors" tab offline, and additionally flags records
# whose installPath lives under a different account's config dir.
echo
echo "${C_CYAN}-- install health (cache + marketplace present & local to account) --${C_RESET}"
for acct in $PRESENT_ACCTS; do
  dir="$(acct_dir "$acct")"
  f="$dir/plugins/installed_plugins.json"
  [ -f "$f" ] || continue
  issues=0
  while IFS="$(printf '\t')" read -r plugin scope path; do
    [ -n "$plugin" ] || continue
    # "cached" = installPath dir exists and is non-empty. (A per-plugin
    # .claude-plugin/plugin.json is NOT reliable: e.g. typescript-lsp is
    # defined inline in the marketplace and its cache holds only LICENSE/README.)
    if [ -z "$(find "$path" -mindepth 1 -print -quit 2>/dev/null)" ]; then
      drift=1; issues=1
      echo "${C_RED}✗ $acct  $plugin ($scope)  NOT CACHED${C_RESET}"
      echo "    ${C_DIM}$path${C_RESET}"
      echo "    ${C_DIM}→ errors on session start; /plugin uninstall + reinstall in a $acct session${C_RESET}"
    else
      case "$path/" in
        "$dir/"*) : ;;   # cached and local to this account — good
        *)
          if ! served_from_the_manifest_repository "${plugin##*@}"; then
            drift=1; issues=1
            echo "${C_YELLOW}△ $acct  $plugin ($scope)  FOREIGN store${C_RESET}"
            echo "    ${C_DIM}$path${C_RESET}"
            echo "    ${C_DIM}→ loads from another account's dir; reinstall in a $acct session to localise${C_RESET}"
          fi
          ;;
      esac
    fi
  done < <(jq -r '.plugins // {} | to_entries[] | .key as $k | .value[] | "\($k)\t\(.scope)\t\(.installPath)"' "$f" 2>/dev/null)

  # marketplace registrations for this account (the layer that produced the
  # "warp (user) not cached at <marketplace>" error — a clone registered under
  # another account's dir, or missing entirely).
  km="$dir/plugins/known_marketplaces.json"
  if [ -f "$km" ]; then
    while IFS="$(printf '\t')" read -r mkt loc; do
      [ -n "$mkt" ] && [ -n "$loc" ] || continue
      if [ ! -d "$loc" ]; then
        drift=1; issues=1
        echo "${C_RED}✗ $acct  marketplace $mkt  MISSING${C_RESET}"
        echo "    ${C_DIM}$loc${C_RESET}"
      else
        case "$loc/" in
          "$dir/"*) : ;;   # registered locally — good
          *)
            if served_from_the_manifest_repository "$mkt"; then continue; fi
            drift=1; issues=1
            echo "${C_YELLOW}△ $acct  marketplace $mkt  FOREIGN store${C_RESET}"
            echo "    ${C_DIM}$loc${C_RESET}"
            echo "    ${C_DIM}→ registered under another account's dir; re-add the marketplace in a $acct session${C_RESET}"
            ;;
        esac
      fi
    done < <(jq -r 'to_entries[] | "\(.key)\t\(.value.installLocation // empty)"' "$km" 2>/dev/null)
  fi

  [ "$issues" -eq 0 ] && echo "${C_GREEN}✓ $acct${C_RESET}  ${C_DIM}all installs + marketplaces cached & local${C_RESET}"
done

# --- optional: upstream staleness of marketplace clones ----------------------
if [ "$REMOTE" -eq 1 ]; then
  echo
  echo "${C_CYAN}-- upstream check (git fetch, no merge) --${C_RESET}"
  FETCHED=""   # space-delimited list of already-checked clone realpaths
  for acct in $PRESENT_ACCTS; do
    km="$(acct_dir "$acct")/plugins/known_marketplaces.json"
    [ -f "$km" ] || continue
    while read -r mkt loc; do
      [ -n "$loc" ] && [ -d "$loc/.git" ] || continue
      real="$(cd "$loc" && pwd -P)"
      case " $FETCHED " in *" $real "*) continue ;; esac   # de-dup shared clones
      FETCHED="$FETCHED $real"

      if ! git -C "$real" fetch --quiet origin 2>/dev/null; then
        echo "${C_DIM}? $mkt  ($real)  fetch failed${C_RESET}"; continue
      fi
      # resolve the remote's default branch, fall back to main/master
      ref="$(git -C "$real" symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null || true)"
      if [ -z "$ref" ]; then
        if git -C "$real" rev-parse --verify -q origin/main >/dev/null 2>&1; then
          ref="origin/main"
        else
          ref="origin/master"
        fi
      fi
      behind="$(git -C "$real" rev-list --count "HEAD..$ref" 2>/dev/null || echo 0)"
      if [ "${behind:-0}" -gt 0 ]; then
        drift=1
        echo "${C_YELLOW}△ $mkt  $behind commit(s) behind $ref${C_RESET}  ${C_DIM}($real)${C_RESET}"
        echo "    ${C_DIM}→ git -C \"$real\" pull --ff-only, then /plugin update in each account${C_RESET}"
      else
        echo "${C_GREEN}✓ $mkt${C_RESET}  ${C_DIM}up to date ($real)${C_RESET}"
      fi
    done < <(jq -r 'to_entries[] | "\(.key) \(.value.installLocation // empty)"' "$km" 2>/dev/null)
  done
fi

if [ "$MODE" = "check" ] && [ "$drift" -eq 1 ]; then
  exit 1
fi
exit 0
