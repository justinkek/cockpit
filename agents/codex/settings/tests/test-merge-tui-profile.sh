#!/usr/bin/env bash
#
# run-tests collects *.sh under a tests directory, so this is what reaches the
# python suite beside merge-tui-profile.

DIR="$(cd "$(dirname "$0")" && pwd)"
exec python3 "$DIR/../test_merge_tui_profile.py"
