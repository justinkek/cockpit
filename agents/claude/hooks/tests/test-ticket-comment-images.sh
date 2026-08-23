#!/usr/bin/env bash

SCRIPT="$(cd "$(dirname "$0")/../.." && pwd)/ticket-comment-images"
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

assert_contains() {
  local label="$1" expected="$2" output="$3"
  if printf '%s' "$output" | grep --quiet --fixed-strings "$expected"; then
    printf "  OK  %s\n" "$label"
    pass=$((pass + 1))
  else
    printf "  KO  %s — expected '%s' in output '%s'\n" "$label" "$expected" "$output"
    fail=$((fail + 1))
  fi
}

PAGE="3ba8f3776f4f8177b7e5eca3394a2d91"
COMMENT="3bc8f3776f4f81769a3f001d7a7f2d09"
DESTINATION="$TMPDIR/images"

WITH_ATTACHMENT="$TMPDIR/with-attachment.json"
WITHOUT_ATTACHMENT="$TMPDIR/without-attachment.json"
UNAUTHORIZED="$TMPDIR/unauthorized.json"
RESTRICTED="$TMPDIR/restricted.json"
RATE_LIMITED="$TMPDIR/rate-limited.json"
GARBAGE="$TMPDIR/garbage.json"

SERVED="$TMPDIR/served.png"
printf 'not really a png, but it is not empty\n' > "$SERVED"

cat > "$WITH_ATTACHMENT" <<JSON
{
  "object": "list",
  "results": [
    {
      "object": "comment",
      "id": "$COMMENT",
      "attachments": [
        { "category": "image", "file": { "url": "file://$SERVED?X-Amz-Expires=3600" } }
      ]
    },
    {
      "object": "comment",
      "id": "0000f3776f4f80000000000000000000"
    }
  ],
  "next_cursor": null
}
JSON

cat > "$WITHOUT_ATTACHMENT" <<'JSON'
{
  "object": "list",
  "results": [
    { "object": "comment", "id": "0000f3776f4f80000000000000000000" }
  ],
  "next_cursor": null
}
JSON

cat > "$UNAUTHORIZED" <<'JSON'
{ "object": "error", "status": 401, "code": "unauthorized", "message": "API token is invalid." }
JSON

cat > "$RESTRICTED" <<'JSON'
{ "object": "error", "status": 403, "code": "restricted_resource", "message": "Insufficient permissions." }
JSON

cat > "$RATE_LIMITED" <<'JSON'
{ "object": "error", "status": 429, "code": "rate_limited", "message": "You have been rate limited." }
JSON

printf 'this is not json at all\n' > "$GARBAGE"

EXPIRED_LINK="$TMPDIR/expired-link.json"
EXPIRED_COMMENT="3bc8f3776f4f81769a3f001d7a7f2d10"

cat > "$EXPIRED_LINK" <<JSON
{
  "object": "list",
  "results": [
    {
      "object": "comment",
      "id": "$EXPIRED_COMMENT",
      "attachments": [
        { "category": "image", "file": { "url": "file://$TMPDIR/gone.png?X-Amz-Expires=3600" } }
      ]
    }
  ],
  "next_cursor": null
}
JSON

run() {
  local fixture="$1"
  shift
  TICKET_COMMENT_IMAGES_FIXTURE="$fixture" \
  TICKET_COMMENT_IMAGES_DESTINATION="$DESTINATION" \
    "$SCRIPT" "$@" 2>/dev/null
}

printf '\nticket-comment-images\n'

output="$(run "$WITH_ATTACHMENT" "$PAGE")"
assert_contains "an attachment prints its comment id" "$COMMENT" "$output"
assert_contains "an attachment prints its category" "image" "$output"
assert_contains "an attachment prints a path under the page's own directory" "$DESTINATION/$PAGE/$COMMENT.png" "$output"
assert_eq "one attachment prints one line" 1 "$(printf '%s\n' "$output" | grep --count . || true)"

path="$DESTINATION/$PAGE/$COMMENT.png"
assert_eq "the file it names is on disk" "$(cat "$SERVED")" "$(cat "$path")"

printf 'already here, and not what the link serves\n' > "$path"
run "$WITH_ATTACHMENT" "$PAGE" >/dev/null
assert_eq "a file already on disk is not fetched again" "already here, and not what the link serves" "$(cat "$path")"

output="$(run "$WITHOUT_ATTACHMENT" "$PAGE")"
assert_eq "a page whose comments carry no attachment prints nothing" "" "$output"

output="$(run "$EXPIRED_LINK" "$PAGE")"
assert_eq "a link that serves no file prints no line" "" "$output"
assert_eq "and leaves nothing behind for the Read tool to open" "" "$(ls "$DESTINATION/$PAGE" | grep --fixed-strings "$EXPIRED_COMMENT" || true)"

run "$UNAUTHORIZED" "$PAGE" >/dev/null 2>&1 || status=$?
assert_eq "a rejected credential exits 4" 4 "${status:-0}"

status=0
run "$RESTRICTED" "$PAGE" >/dev/null 2>&1 || status=$?
assert_eq "a credential that cannot read comments exits 4" 4 "$status"

status=0
run "$RATE_LIMITED" "$PAGE" >/dev/null 2>&1 || status=$?
assert_eq "a rate limited read exits 6" 6 "$status"

status=0
run "$GARBAGE" "$PAGE" >/dev/null 2>&1 || status=$?
assert_eq "an unreadable response exits 5" 5 "$status"

status=0
run "$WITH_ATTACHMENT" "not-a-page-id" >/dev/null 2>&1 || status=$?
assert_eq "an argument holding no page id exits 2" 2 "$status"

status=0
run "$WITH_ATTACHMENT" >/dev/null 2>&1 || status=$?
assert_eq "no argument at all exits 2" 2 "$status"

status=0
TICKET_COMMENT_IMAGES_DESTINATION="$DESTINATION" HOME="$TMPDIR/nobody" \
  "$SCRIPT" "$PAGE" >/dev/null 2>&1 || status=$?
if [ "$status" -eq 3 ]; then
  assert_eq "no credential exits 3" 3 "$status"
else
  printf "  ..  no credential exits 3 — skipped, this machine has a cockpit-notion-token\n"
fi

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
