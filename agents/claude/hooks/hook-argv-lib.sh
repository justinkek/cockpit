#!/usr/bin/env bash

hook_argv_words() {
  printf '%s' "$1" | awk '
    function endword() { if (inword) { words[++k] = word; word = ""; inword = 0 } }
    function operator() { endword(); words[++k] = ""; isop[k] = 1 }
    {
      n = length($0); word = ""; inword = 0; quote = ""
      for (i = 1; i <= n; i++) {
        c = substr($0, i, 1)
        if (quote != "") {
          if (c == quote) quote = ""; else word = word c
          inword = 1
          continue
        }
        if (c == "\"" || c == "\047") { quote = c; inword = 1; continue }
        if (c == " " || c == "\t") { endword(); continue }
        if (index(";|&<>()`", c)) { operator(); continue }
        word = word c; inword = 1
      }
      operator()  # a line break ends the invocation too
    }
    END {
      for (j = 1; j <= k; j++) {
        if (isop[j]) print "o"; else print "w " words[j]
      }
    }'
}

# hook_argv_after <cmd> <script-basename>
#
# Print the shell words that follow the FIRST token whose basename is
# <script-basename>, one per line, stopping at the first shell operator — a
# chained command's own words are not this invocation's arguments.
# Prints nothing when the token is absent — callers guard on empty output,
# never on "did sed echo its input back".
hook_argv_after() {
  hook_argv_words "$1" | awk -v s="$2" '
    $0 == "o" { if (found) exit; next }
    {
      w = substr($0, 3)
      if (!found) { if (w ~ ("(^|/)" s "$")) found = 1; next }
      print w
    }'
}

hook_argv_segments() {
  hook_argv_words "$1" | awk '
    BEGIN { head = 1 }
    $0 == "o" { if (segment != "") print segment; segment = ""; head = 1; drop = 0; next }
    {
      w = substr($0, 3)
      if (head) {
        if (w == "cd") { drop = 1; next }
        if (drop) { drop = 0; next }
        if (w ~ /^[A-Za-z_][A-Za-z_0-9]*=/) next
        head = 0
      }
      segment = (segment == "" ? w : segment " " w)
    }
    END { if (segment != "") print segment }'
}

# The commands a session may run before it is named or has a ticket. Every one
# of them only reads, and none takes a flag that writes: find is deliberately
# absent (-delete, -exec) and so are sed and awk (-i, print >). `date -s` needs
# root, which these sessions do not have.
#
# Widening this set widens what an unnamed, unticketed session can do, so it is
# a deliberate act — test-hook-readonly-bash.sh pins it.
HOOK_READONLY_CMDS="ls cat head tail grep egrep fgrep rg wc file stat pwd date basename dirname realpath jq"

# hook_is_readonly_bash <cmd>
#
# True when the command is a single invocation of a command that only reads:
# the first token's basename is in HOOK_READONLY_CMDS, and the whole line
# carries exactly one operator marker — the one hook_argv_words appends at the
# end of every line. Two or more means a pipe, a chain, a redirection, a
# subshell, a substitution, or a second line, any of which can carry a write
# the first token does not admit to.
hook_is_readonly_bash() {
  hook_argv_words "$1" | awk -v set="$HOOK_READONLY_CMDS" '
    $0 == "o" { ops++; next }
    !seen { seen = 1; first = substr($0, 3); sub(/^.*\//, "", first) }
    END {
      if (ops != 1 || !seen || first == "") exit 1
      n = split(set, a, " ")
      for (i = 1; i <= n; i++) if (a[i] == first) exit 0
      exit 1
    }'
}

hook_heredoc_body() {
  printf '%s\n' "$1" | awk '
    !opened && /<<-?[[:space:]]*[\047"]?[A-Za-z_][A-Za-z_0-9]*[\047"]?/ && !/<<</ {
      line = $0
      sub(/^.*<</, "", line)
      strip = (substr(line, 1, 1) == "-")
      if (strip) line = substr(line, 2)
      sub(/^[[:space:]]*/, "", line)
      match(line, /^[\047"]?[A-Za-z_][A-Za-z_0-9]*/)
      delimiter = substr(line, RSTART, RLENGTH)
      gsub(/[\047"]/, "", delimiter)
      opened = 1
      next
    }
    opened && !closed {
      body = $0
      if (strip) sub(/^\t+/, "", body)
      if (body == delimiter) { closed = 1; next }
      print body
      found = 1
    }
    !opened && !herestring && /<<</ {
      line = $0
      sub(/^.*<<<[[:space:]]*/, "", line)
      herestring = line
    }
    END {
      if (!found && herestring != "") {
        quote = substr(herestring, 1, 1)
        if (quote == "\047" || quote == "\"") {
          herestring = substr(herestring, 2)
          end = index(herestring, quote)
          if (end > 0) herestring = substr(herestring, 1, end - 1)
        }
        print herestring
      }
    }'
}
