#!/usr/bin/env bash

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
printf '#!/usr/bin/env bash\nsed "s/^/seen /"\n' > "$guard"
chmod +x "$guard"

printf "Test group: the cockpit reaches a plugin's guard\n"

report "stdin reaches the guard and its output comes back" \
  "seen a write" \
  "$(printf 'a write' | COCKPIT_PLUGIN_SEARCH_ROOT="$workspace" "$RESOLVER" guard-tech-steps.sh)"

report "a guard no plugin carries is silent" \
  "" \
  "$(printf 'a write' | COCKPIT_PLUGIN_SEARCH_ROOT="$workspace" "$RESOLVER" guard-validation-steps.sh)"

report "no guard named is silent" \
  "" \
  "$(printf 'a write' | COCKPIT_PLUGIN_SEARCH_ROOT="$workspace" "$RESOLVER")"

chmod -x "$guard"
report "a guard that is not executable is silent" \
  "" \
  "$(printf 'a write' | COCKPIT_PLUGIN_SEARCH_ROOT="$workspace" "$RESOLVER" guard-tech-steps.sh)"

printf "\n%d passed, %d failed\n" "$pass" "$fail"
[ "$fail" -eq 0 ]
