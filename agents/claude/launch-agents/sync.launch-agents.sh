#!/usr/bin/env bash
set -euo pipefail

SHARED_DIR="${CLAUDE_SHARED_DIR:-$HOME/.claude-shared}"
LAUNCHCTL="${LAUNCHCTL_BIN:-launchctl}"
LABEL="com.cockpit.board-maintenance"
LAUNCH_AGENTS_DIR="$HOME/Library/LaunchAgents"
TARGET="$LAUNCH_AGENTS_DIR/$LABEL.plist"
LOG="$HOME/.local/state/cockpit/board-maintenance.log"
DOMAIN="gui/$(id -u)"

source "$SHARED_DIR/accounts.sh"
source "$SHARED_DIR/board-accounts.sh"

MODE="apply"
ASSUME_YES=0
for arg in "$@"; do
  case "$arg" in
    --check)   MODE="check" ;;
    --apply)   MODE="apply" ;;
    --yes|-y)  ASSUME_YES=1 ;;
    -h|--help) echo "usage: sync.launch-agents.sh [--check|--apply] [--yes]"; exit 0 ;;
    *)         echo "error: unknown arg: $arg" >&2; exit 2 ;;
  esac
done

if [ -t 1 ]; then
  C_RESET=$'\033[0m'; C_RED=$'\033[31m'; C_GREEN=$'\033[32m'
  C_YELLOW=$'\033[33m'; C_DIM=$'\033[2m'
else
  C_RESET=''; C_RED=''; C_GREEN=''; C_YELLOW=''; C_DIM=''
fi

render_plist() {
  cat <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>Label</key>
	<string>$LABEL</string>
	<key>ProgramArguments</key>
	<array>
		<string>$HOME/.cockpit/scripts/board-card</string>
		<string>maintenance</string>
		<string>--close</string>
	</array>
	<key>EnvironmentVariables</key>
	<dict>
		<key>PATH</key>
		<string>/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin</string>
	</dict>
	<key>StartCalendarInterval</key>
	<dict>
		<key>Day</key>
		<integer>1</integer>
		<key>Minute</key>
		<integer>5</integer>
	</dict>
	<key>StandardOutPath</key>
	<string>$LOG</string>
	<key>StandardErrorPath</key>
	<string>$LOG</string>
</dict>
</plist>
PLIST
}

board_account=""
for acct in "${ACCOUNTS[@]}"; do
  if account_works_the_ticket_board "$acct"; then
    board_account="$acct"
    break
  fi
done

if [ -z "$board_account" ]; then
  echo "${C_DIM}no account here works the board, so $LABEL is left alone${C_RESET}"
  exit 0
fi

if [ "$(uname -s)" != Darwin ]; then
  echo "${C_DIM}launchd is macOS only, so $LABEL is left alone${C_RESET}"
  exit 0
fi

desired="$(render_plist)"
current=''
[ -f "$TARGET" ] && current="$(cat "$TARGET")"
loaded=0
"$LAUNCHCTL" print "$DOMAIN/$LABEL" >/dev/null 2>&1 && loaded=1

if [ "$current" = "$desired" ] && [ "$loaded" -eq 1 ]; then
  echo "${C_GREEN}✓ $LABEL${C_RESET}  in sync and loaded  ${C_DIM}($TARGET)${C_RESET}"
  exit 0
fi

if [ "$current" != "$desired" ]; then
  echo "${C_YELLOW}△ $LABEL  DRIFT${C_RESET}  ${C_DIM}($TARGET)${C_RESET}"
  echo "    ${C_DIM}--- diff: current (${C_RED}<${C_DIM}) → desired (${C_GREEN}>${C_DIM}) ---${C_RESET}"
  diff <(printf '%s\n' "$current") <(printf '%s\n' "$desired") \
    | awk -v r="$C_RED" -v g="$C_GREEN" -v d="$C_DIM" -v x="$C_RESET" '
        /^</  { print "    " r $0 x; next }
        /^>/  { print "    " g $0 x; next }
        { print "    " d $0 x }
      ' || true
fi
if [ "$loaded" -eq 0 ]; then
  echo "${C_YELLOW}△ $LABEL${C_RESET}  not loaded in $DOMAIN"
fi

[ "$MODE" = "check" ] && exit 1

if ! confirm "    " "install and load $LABEL?"; then
  echo "    skipped"
  exit 0
fi

mkdir -p "$LAUNCH_AGENTS_DIR" "$(dirname "$LOG")"
if [ "$loaded" -eq 1 ]; then
  "$LAUNCHCTL" bootout "$DOMAIN/$LABEL"
  echo "    unloaded $DOMAIN/$LABEL"
fi
if [ "$current" != "$desired" ]; then
  printf '%s\n' "$desired" > "$TARGET"
  echo "    ✓ wrote $TARGET"
fi
"$LAUNCHCTL" bootstrap "$DOMAIN" "$TARGET"
echo "    ✓ loaded $LABEL in $DOMAIN"
exit 0
