#!/usr/bin/env bash

CODEX_HOMES=(codex codex-cockpit)

codex_home_dir() {
  printf '%s' "$HOME/.$1"
}

codex_home_reached_without_a_wrapper() {
  [ "$1" = "codex" ]
}

codex_home_works_the_ticket_board() {
  ! codex_home_reached_without_a_wrapper "$1"
}
