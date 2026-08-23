#!/usr/bin/env bash

HOOK="$(cd "$(dirname "$0")/.." && pwd)/challenge-code-comment.sh"

pass=0
fail=0
marker="#"

run_edit() {
  local fp="$1" old="$2" new="$3"
  jq -nc --arg fp "$fp" --arg o "$old" --arg n "$new" \
    '{tool_name:"Edit",tool_input:{file_path:$fp,old_string:$o,new_string:$n}}' \
    | bash "$HOOK" 2>/dev/null
}

run_write() {
  local fp="$1" content="$2"
  jq -nc --arg fp "$fp" --arg c "$content" \
    '{tool_name:"Write",tool_input:{file_path:$fp,content:$c}}' \
    | bash "$HOOK" 2>/dev/null
}

assert_denies() {
  local label="$1" output="$2"
  if printf '%s' "$output" | grep -qF '"permissionDecision":"deny"'; then
    printf "  OK  %s\n" "$label"
    pass=$((pass + 1))
  else
    printf "  KO  %s — expected a deny, got '%s'\n" "$label" "$output"
    fail=$((fail + 1))
  fi
}

assert_silent() {
  local label="$1" output="$2"
  if [ -z "$output" ]; then
    printf "  OK  %s\n" "$label"
    pass=$((pass + 1))
  else
    printf "  KO  %s — expected silence, got '%s'\n" "$label" "$output"
    fail=$((fail + 1))
  fi
}

printf "Test group: a comment added to code is denied\n"

assert_denies "line comment in TypeScript" \
  "$(run_edit /tmp/a.ts 'const x = 1;' '// the padding the menu needs
const x = 1;')"
assert_denies "block comment continuation" \
  "$(run_edit /tmp/a.ts 'const x = 1;' '/**
 * what x is for
 */
const x = 1;')"
assert_denies "hash comment in a shell script" \
  "$(run_edit /tmp/a.sh 'x=1' '# set x
x=1')"
assert_denies "comment in an extensionless script" \
  "$(run_edit /tmp/ticket-thing 'x=1' '# set x
x=1')"
assert_denies "whole-file Write carrying a comment below the header block" \
  "$(run_write /tmp/a.ts '// what this module is for

const x = 1;
// the padding the menu needs
const y = 2;')"
assert_denies "header block in an Edit fragment is not a header" \
  "$(run_edit /tmp/a.sh 'x=1' '# set x
x=1')"

printf "\nTest group: only the lines an edit adds count, so a comment already present is not a new one\n"

assert_silent "plain code edit" \
  "$(run_edit /tmp/a.ts 'const x = 1;' 'const x = 2;')"
assert_silent "comment already present, code around it changed" \
  "$(run_edit /tmp/a.ts '// the padding the menu needs
const x = 1;' '// the padding the menu needs
const x = 2;')"
assert_silent "comment re-indented, not added" \
  "$(run_edit /tmp/a.ts '// the padding the menu needs
const x = 1;' '  // the padding the menu needs
  const x = 1;')"
assert_silent "shebang is not a comment" \
  "$(run_write /tmp/a.sh '#!/usr/bin/env bash
x=1')"

printf "\nTest group: a house-style header block is refused like any other comment\n"

assert_denies "shell header block under the shebang" \
  "$(run_write /tmp/a.sh '#!/usr/bin/env bash
#
# test-thing.sh — what this script asserts.
#
# Why it exists and what it stays clear of.

x=1
printf "%s\n" "$x"')"
assert_denies "header block with no shebang" \
  "$(run_write /tmp/a.ts '// What this module is for.
// A second line of the same block.

const x = 1;')"
assert_denies "extensionless script with a header block" \
  "$(run_write /tmp/ticket-thing '#!/usr/bin/env bash
# ticket-thing — what it does.

x=1')"

printf "\nTest group: a licence header is exempt, and carries the whole run it opens\n"

assert_silent "licence identifier line" \
  "$(run_write /tmp/a.sh '#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0

x=1')"
assert_silent "copyright line, spelled out" \
  "$(run_write /tmp/a.ts '// Copyright (c) 2026 Acme Ltd

const x = 1;')"
assert_silent "copyright line, symbol form" \
  "$(run_write /tmp/a.ts '// Copyright © 2026 Acme Ltd

const x = 1;')"
assert_silent "licence prose continuing under its own marker" \
  "$(run_write /tmp/a.sh '#!/usr/bin/env bash
# Licensed under the Apache License, Version 2.0
# you may not use this file except in compliance with it.

x=1')"
assert_denies "house-style header sitting above a licence header" \
  "$(run_write /tmp/a.sh '#!/usr/bin/env bash
# what this script does and why it exists
# Copyright (c) 2026 Acme Ltd

x=1')"
assert_denies "house-style header sitting below a licence header" \
  "$(run_write /tmp/a.sh '#!/usr/bin/env bash
# Copyright (c) 2026 Acme Ltd

# what this script does and why it exists

x=1')"
assert_denies "licence marker on an Edit fragment exempts nothing" \
  "$(run_edit /tmp/a.sh 'x=1' '# Copyright (c) 2026 Acme Ltd
# the padding the menu needs
x=1')"

printf "\nTest group: comment syntax that is data, not a comment\n"

assert_silent "shell case glob branch" \
  "$(run_edit /tmp/a.sh 'x=1' 'case "$t" in
  *) exit 0 ;;
esac')"
assert_silent "shell case glob with extensions" \
  "$(run_edit /tmp/a.sh 'x=1' 'case "$f" in
  *.md|*.mdx) exit 0 ;;
esac')"
assert_silent "marker inside a quoted multi-line string" \
  "$(run_edit /tmp/a.sh 'x=1' "usage=\"run it like this:
$marker not a comment, part of the message
\"")"
assert_denies "a real comment after a closed quoted string" \
  "$(run_edit /tmp/a.sh 'x=1' "usage=\"one line\"
$marker this one really is a comment
x=1")"

printf "\nTest group: prose and comment-less data formats are out of scope\n"

assert_silent "markdown heading" "$(run_write /tmp/a.md '# Title')"
assert_silent "yaml section comment" "$(run_write /tmp/a.yml '# build steps
steps: []')"
assert_silent "json with a url" "$(run_write /tmp/a.json '{"u":"https://x.dev"}')"

printf "\nTest group: a hash in a C family file opens a directive, not a comment\n"

assert_silent "include directive in a C++ source" \
  "$(run_edit /tmp/a.cpp 'int x = 1;' '#include <string>
int x = 1;')"
assert_silent "conditional directives in a header" \
  "$(run_edit /tmp/a.h 'int x;' '#ifndef A_H
#define A_H
int x;
#endif')"
assert_silent "directive indented inside a block" \
  "$(run_edit /tmp/a.cc 'int x;' 'int f() {
#ifdef DEBUG
  return 1;
#endif
}')"
assert_silent "import directive in an Objective-C source" \
  "$(run_edit /tmp/a.m 'int x;' '#import <Foundation/Foundation.h>
int x;')"
assert_denies "a line comment in the same C++ source is still a comment" \
  "$(run_edit /tmp/a.cpp 'int x = 1;' '// the padding the menu needs
int x = 1;')"
assert_denies "a block comment in a C source is still a comment" \
  "$(run_edit /tmp/a.c 'int x = 1;' '/* what x is for */
int x = 1;')"
assert_denies "a hash comment in a shell script is untouched by the carve-out" \
  "$(run_edit /tmp/a.sh 'x=1' '# error handling for the retry
x=1')"

printf "\nTest group: other tools are none of its business\n"

assert_silent "Bash tool" \
  "$(jq -nc '{tool_name:"Bash",tool_input:{command:"# not an edit"}}' | bash "$HOOK" 2>/dev/null)"

printf "\n%d passed, %d failed\n" "$pass" "$fail"
[ "$fail" -eq 0 ]
