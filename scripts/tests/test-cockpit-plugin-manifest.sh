#!/usr/bin/env bash

repo_root_through_symlink() {
  cd "$(dirname "$0")" && cd "$(pwd -P)/../.." && pwd
}

REPO="$(repo_root_through_symlink)"
MARKETPLACE="$REPO/marketplace/.claude-plugin/marketplace.json"
PLUGIN="$REPO/marketplace/plugins/cockpit"
MANIFEST="$PLUGIN/.claude-plugin/plugin.json"
PLUGIN_HOOKS="$PLUGIN/hooks/hooks.json"
SETTINGS="$REPO/agents/claude/settings/base.settings.json"

pass=0
fail=0

assert_ok() {
  printf "  OK  %s\n" "$1"
  pass=$((pass + 1))
}

assert_ko() {
  printf "  KO  %s — %s\n" "$1" "$2"
  fail=$((fail + 1))
}

assert_eq() {
  local label="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then
    assert_ok "$label"
  else
    assert_ko "$label" "expected '$expected', got '$actual'"
  fi
}

printf "Test group: the marketplace and the manifest agree\n"

declared_source="$(jq --raw-output '.plugins[0].source' "$MARKETPLACE" | sed 's|^\./||')"
manifest_the_marketplace_points_at="$REPO/marketplace/$declared_source/.claude-plugin/plugin.json"

assert_eq "the marketplace names the cockpit plugin" "cockpit" \
  "$(jq --raw-output '.plugins[0].name' "$MARKETPLACE")"
assert_eq "and points at the directory holding the manifest" "$MANIFEST" \
  "$manifest_the_marketplace_points_at"
assert_eq "the manifest declares the same name" "cockpit" \
  "$(jq --raw-output '.name' "$MANIFEST")"

commands_under() {
  local prefix="$1" file="$2"
  jq --raw-output --arg prefix "$prefix" \
    '.hooks | to_entries[] | .value[] | .hooks[] | .command | select(startswith($prefix))' "$file" |
    sed 's/ .*//' | sort --unique
}

executable_under_the_plugin() {
  local prefix="$1" file="$2" script path missing=""
  while IFS= read -r script; do
    [ -n "$script" ] || continue
    path="$PLUGIN/${script#"$prefix"}"
    [ -x "$path" ] || missing="$missing ${script##*/}"
  done < <(commands_under "$prefix" "$file")
  printf '%s' "$missing"
}

printf "\nTest group: every hook the plugin declares is a file it carries\n"

assert_eq "hooks.json names every command through the plugin root variable" "" \
  "$(jq --raw-output '.hooks | to_entries[] | .value[] | .hooks[] | .command | select(startswith("${CLAUDE_PLUGIN_ROOT}/") | not)' "$PLUGIN_HOOKS")"

missing="$(executable_under_the_plugin '${CLAUDE_PLUGIN_ROOT}/' "$PLUGIN_HOOKS")"
if [ -z "$missing" ]; then
  assert_ok "every command in hooks.json is an executable file under the plugin root"
else
  assert_ko "every command in hooks.json is an executable file under the plugin root" "missing:$missing"
fi

printf "\nTest group: the settings reach the same files through the symlink\n"

missing="$(executable_under_the_plugin '$HOME/.cockpit/' "$SETTINGS")"
if [ -z "$missing" ]; then
  assert_ok "every board hook the settings declare is an executable file under the plugin root"
else
  assert_ko "every board hook the settings declare is an executable file under the plugin root" "missing:$missing"
fi

printf "\nTest group: the plugin never reaches its own files through the shared root\n"

reached_through_the_shared_root=""
while IFS= read -r carried; do
  [ -n "$carried" ] || continue
  hits="$(grep --recursive --line-number --extended-regexp \
    "(CLAUDE_SHARED_DIR|SHARED_DIRECTORY|SHARED_DIR|\.claude-shared)[^\"']*/$carried([^A-Za-z0-9._-]|\$)" \
    "$PLUGIN/scripts" 2>/dev/null | grep --invert-match '/tests/')"
  [ -z "$hits" ] || reached_through_the_shared_root="$reached_through_the_shared_root
$hits"
done < <(find "$PLUGIN/scripts" -type f -not -path '*/tests/*' -exec basename {} \; | sort --unique)

if [ -z "$reached_through_the_shared_root" ]; then
  assert_ok "no script the plugin carries is reached through the shared root"
else
  assert_ko "no script the plugin carries is reached through the shared root" "$reached_through_the_shared_root"
fi

printf "\nTest group: install.sh links the plugin directory\n"

grep --quiet --fixed-strings 'marketplace/plugins/cockpit:$HOME/.cockpit' "$REPO/install.sh" &&
  assert_ok "install.sh maps the plugin directory onto ~/.cockpit" ||
  assert_ko "install.sh maps the plugin directory onto ~/.cockpit" "no such entry in its MAP"

printf "\nTest group: the skills sync carries the plugin root until the plugin is enabled\n"

SKILLS_SYNC="$REPO/agents/claude/skills/sync.skills.sh"
grep --quiet --fixed-strings 'COCKPIT_SKILLS_DIR="$COCKPIT_PLUGIN_DIR/skills"' "$SKILLS_SYNC" &&
  assert_ok "sync.skills.sh reads the plugin's skills directory" ||
  assert_ko "sync.skills.sh reads the plugin's skills directory" "no such root in the script"

! grep --quiet --fixed-strings '"cockpit@cockpit"' "$REPO/agents/claude/plugins/base.plugins.json" &&
  assert_ok "and no account enables the plugin yet" ||
  assert_ko "and no account enables the plugin yet" "base.plugins.json declares it, so the third root is now a second source"

printf "\n%d passed, %d failed\n" "$pass" "$fail"
[ "$fail" -eq 0 ]
