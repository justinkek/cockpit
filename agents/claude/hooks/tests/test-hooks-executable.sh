#!/usr/bin/env bash

HOOKS="$(cd "$(dirname "$0")/.." && pwd)"
PLUGIN_HOOKS="$(cd "$HOOKS/../../../marketplace/plugins/cockpit/scripts/hooks" && pwd)"
SETTINGS="$(cd "$(dirname "$0")/../../settings" && pwd)/base.settings.json"

pass=0
fail=0

assert_executable() {
  local name="$1"
  if [ -x "$HOOKS/$name" ] || [ -x "$PLUGIN_HOOKS/$name" ]; then
    printf "  OK  %s\n" "$name"
    pass=$((pass + 1))
  else
    printf "  KO  %s — the settings entry names no interpreter, so a non-executable hook never runs\n" "$name"
    fail=$((fail + 1))
  fi
}

while IFS= read -r name; do
  assert_executable "$name"
done < <(jq --raw-output '.hooks | to_entries[] | .value[] | .hooks[] | .command' "$SETTINGS" \
  | sed 's/ .*//; s|.*/||' \
  | sort --unique)

printf "\n%d passed, %d failed\n" "$pass" "$fail"
[ "$fail" -eq 0 ]
