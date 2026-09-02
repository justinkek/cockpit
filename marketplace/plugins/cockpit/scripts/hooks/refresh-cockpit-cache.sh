#!/usr/bin/env bash

cat >/dev/null

SHARED_DIRECTORY="${CLAUDE_SHARED_DIR:-$HOME/.claude-shared}"
CACHE="${COCKPIT_CACHE:-$HOME/.local/state/cockpit/cache.json}"
REFRESH_AFTER_HOURS="${COCKPIT_CACHE_REFRESH_AFTER_HOURS:-24}"

cache_is_older_than_threshold() {
  local updated epoch age_hours

  [ -f "$CACHE" ] || return 0
  command -v jq >/dev/null 2>&1 || return 1

  updated="$(jq --raw-output '.updated_at // empty' "$CACHE" 2>/dev/null)"
  [ -n "$updated" ] || return 0

  updated="${updated%%.*}"
  updated="${updated%Z}"
  epoch="$(TZ=UTC date -j -f '%Y-%m-%dT%H:%M:%S' "$updated" +%s 2>/dev/null \
    || date --utc --date="$updated" +%s 2>/dev/null)" || return 1

  age_hours=$(( ($(date +%s) - epoch) / 3600 ))
  [ "$age_hours" -ge "$REFRESH_AFTER_HOURS" ]
}

if cache_is_older_than_threshold; then
  "$SHARED_DIRECTORY/cockpit-cache-refresh" >/dev/null 2>&1 || true
fi

exit 0
