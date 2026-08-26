#!/usr/bin/env bash

WORKER="$(cd "$(dirname "$0")/.." && pwd)/sync.plugins.sh"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

pass=0
fail=0

assert_contains() {
  local label="$1" needle="$2" haystack="$3"
  case "$haystack" in
    *"$needle"*)
      printf "  OK  %s\n" "$label"
      pass=$((pass + 1))
      ;;
    *)
      printf "  KO  %s — expected to find '%s' in '%s'\n" "$label" "$needle" "$haystack"
      fail=$((fail + 1))
      ;;
  esac
}

assert_absent() {
  local label="$1" needle="$2" haystack="$3"
  case "$haystack" in
    *"$needle"*)
      printf "  KO  %s — expected not to find '%s' in '%s'\n" "$label" "$needle" "$haystack"
      fail=$((fail + 1))
      ;;
    *)
      printf "  OK  %s\n" "$label"
      pass=$((pass + 1))
      ;;
  esac
}

ACCOUNT_DIR="$WORK/home/.claude-probe"
REPOSITORY="$WORK/one-repo"
export CALLS_FILE="$WORK/calls"

build_fixture() {
  rm -rf "$WORK/home" "$WORK/shared" "$REPOSITORY"
  mkdir -p "$WORK/shared" "$REPOSITORY" "$ACCOUNT_DIR/plugins/cache/slack" "$ACCOUNT_DIR/plugins/cache/github"
  cat > "$WORK/shared/accounts.sh" <<'ACCOUNTS'
ACCOUNTS=(probe)
acct_dir() { printf '%s' "$HOME/.claude-$1"; }
ACCOUNTS
  : > "$ACCOUNT_DIR/plugins/cache/slack/plugin.json"
  : > "$CALLS_FILE"

  cat > "$WORK/stub-claude" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$CALLS_FILE"
exit 0
STUB
  chmod +x "$WORK/stub-claude"

  cat > "$WORK/base.plugins.json" <<'MANIFEST'
{
	"marketplaces": { "claude-plugins-official": "anthropics/claude-plugins-official" },
	"plugins": {
		"slack@claude-plugins-official": "user",
		"notion@claude-plugins-official": "user"
	}
}
MANIFEST

  jq --null-input \
    --arg account "$ACCOUNT_DIR" \
    --arg repository "$REPOSITORY" '{
      plugins: {
        "slack@claude-plugins-official": [
          { scope: "user", installPath: ($account + "/plugins/cache/slack") },
          { scope: "project", projectPath: $repository, installPath: ($repository + "/plugins/slack") }
        ],
        "figma@claude-plugins-official": [
          { scope: "project", projectPath: $repository, installPath: ($repository + "/plugins/figma") }
        ],
        "github@claude-plugins-official": [
          { scope: "user", projectPath: ".", installPath: ($account + "/plugins/cache/github") }
        ]
      }
    }' > "$ACCOUNT_DIR/plugins/installed_plugins.json"
}

run_apply() {
  HOME="$WORK/home" \
    CLAUDE_SHARED_DIR="$WORK/shared" \
    CLAUDE_BIN="$WORK/stub-claude" \
    CLAUDE_PLUGINS_MANIFEST="$WORK/base.plugins.json" \
    bash "$WORKER" --apply >/dev/null 2>&1
}

build_fixture
run_apply
every_call="$(cat "$CALLS_FILE")"
uninstall_calls="$(grep "^plugin uninstall" "$CALLS_FILE" || true)"

assert_absent "a plugin installed for one repository is never uninstalled at project scope" "--scope project" "$uninstall_calls"
assert_absent "a plugin installed for one repository is never uninstalled at local scope" "--scope local" "$uninstall_calls"
assert_absent "the repository's own figma install is left alone" "figma" "$uninstall_calls"
assert_absent "the repository's own slack install is left alone" "slack" "$uninstall_calls"
assert_contains "a plugin the manifest dropped is still uninstalled for the whole account" "plugin uninstall github@claude-plugins-official --scope user" "$uninstall_calls"
assert_contains "the pre-install sweep still reaches the whole account" "plugin uninstall notion@claude-plugins-official --scope user --yes" "$every_call"

printf "\n%d passed, %d failed\n" "$pass" "$fail"
[ "$fail" -eq 0 ]
