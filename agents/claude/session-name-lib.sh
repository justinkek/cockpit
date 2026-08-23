#!/bin/sh

session_name_read() {
  transcript="$1"
  type_file="$2"
  name=""
  [ -f "$transcript" ] && name=$(grep --only-matching '"customTitle":"[^"]*"' "$transcript" 2>/dev/null | tail -1 | sed 's/"customTitle":"//;s/"$//')
  [ -n "$name" ] || [ ! -f "$type_file" ] || name=$(sed -n 's/^name=//p' "$type_file" | tail -1)
  printf '%s\n' "$name"
}

session_name_tab_label() {
  printf '%s\n' "${1#*] }"
}
