#!/usr/bin/env bash

account_reached_without_a_wrapper() {
  [ "$1" = "claude" ]
}

account_works_the_ticket_board() {
  ! account_reached_without_a_wrapper "$1"
}
