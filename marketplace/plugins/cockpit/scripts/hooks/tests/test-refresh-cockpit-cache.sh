#!/usr/bin/env bash

HOOK="$(cd "$(dirname "$0")/.." && pwd)/refresh-cockpit-cache.sh"
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

pass=0
fail=0

assert_eq() {
  local label="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then
    printf "  OK  %s\n" "$label"
    pass=$((pass + 1))
  else
    printf "  KO  %s — expected '%s', got '%s'\n" "$label" "$expected" "$actual"
    fail=$((fail + 1))
  fi
}

PLUGIN="$TMPDIR/plugin"
CACHE="$TMPDIR/cache.json"
RAN="$TMPDIR/ran"
mkdir -p "$PLUGIN/scripts"

install_stub() {
  local exit_code="$1"
  cat > "$PLUGIN/scripts/cockpit-cache-refresh" <<STUB
#!/usr/bin/env bash
echo ran >> "$RAN"
exit $exit_code
STUB
  chmod +x "$PLUGIN/scripts/cockpit-cache-refresh"
}

write_cache() {
  local hours_old="$1" updated
  updated="$(TZ=UTC date -v-"${hours_old}"H '+%Y-%m-%dT%H:%M:%S.000Z')"
  printf '{"updated_at": "%s"}\n' "$updated" > "$CACHE"
}

run_hook() {
  rm -f "$RAN"
  printf '{"session_id": "test"}' \
    | COCKPIT_CACHE="$CACHE" COCKPIT_PLUGIN_DIR="$PLUGIN" bash "$HOOK" >/dev/null 2>&1
  printf '%s' "$?"
}

refresh_count() {
  if [ -f "$RAN" ]; then grep --count ran "$RAN" | tr -d ' '; else printf '0'; fi
}

install_stub 0

printf "Test group: the refresh runs when there is nothing fresh to read\n"

rm -f "$CACHE"
assert_eq "no cache at all — the hook exits clean" "0" "$(run_hook)"
assert_eq "no cache at all — the refresh ran" "1" "$(refresh_count)"

printf '{"user": {}}\n' > "$CACHE"
run_hook >/dev/null
assert_eq "cache with no timestamp — the refresh ran" "1" "$(refresh_count)"

write_cache 48
run_hook >/dev/null
assert_eq "two days old — the refresh ran" "1" "$(refresh_count)"

write_cache 24
run_hook >/dev/null
assert_eq "exactly at the threshold — the refresh ran" "1" "$(refresh_count)"

printf "\nTest group: a cache inside the window is left alone\n"

write_cache 1
assert_eq "an hour old — the hook exits clean" "0" "$(run_hook)"
assert_eq "an hour old — the refresh did not run" "0" "$(refresh_count)"

write_cache 23
run_hook >/dev/null
assert_eq "just inside the window — the refresh did not run" "0" "$(refresh_count)"

printf "\nTest group: a broken refresh never blocks the session\n"

install_stub 1
write_cache 48
assert_eq "the refresh failed — the hook still exits 0" "0" "$(run_hook)"
assert_eq "the refresh was attempted" "1" "$(refresh_count)"

rm -f "$PLUGIN/scripts/cockpit-cache-refresh"
write_cache 48
assert_eq "the refresh is missing — the hook still exits 0" "0" "$(run_hook)"

printf "\nTest group: the threshold is settable\n"

install_stub 0
write_cache 2
rm -f "$RAN"
printf '{"session_id": "test"}' \
  | COCKPIT_CACHE="$CACHE" COCKPIT_PLUGIN_DIR="$PLUGIN" COCKPIT_CACHE_REFRESH_AFTER_HOURS=1 \
    bash "$HOOK" >/dev/null 2>&1
assert_eq "an hour threshold fires on a two hour old cache" "1" "$(refresh_count)"

printf "\n%d passed, %d failed\n" "$pass" "$fail"
[ "$fail" -eq 0 ]
