#!/usr/bin/env bash

input="$(cat)"

if command -v jq >/dev/null 2>&1; then
  fp="$(printf '%s' "$input" | jq -r '.tool_input.file_path // empty')"
else
  fp="$(printf '%s' "$input" | sed -n 's/.*"file_path"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')"
fi

[ -n "$fp" ] || exit 0
[ -f "$fp" ] || exit 0

git_root="$(git -C "$(dirname "$fp")" rev-parse --show-toplevel 2>/dev/null)" || git_root=""

prettier_version="3.9.10"

project_prettier() {
  local directory parent
  directory="$(cd "$(dirname "$fp")" && pwd -P)" || return 1
  while :; do
    if [ -x "$directory/node_modules/.bin/prettier" ]; then
      printf '%s\n' "$directory/node_modules/.bin/prettier"
      return 0
    fi
    [ "$directory" = "$git_root" ] && return 1
    parent="$(dirname "$directory")"
    [ "$parent" = "$directory" ] && return 1
    directory="$parent"
  done
}

format_with_prettier() {
  local local_prettier
  if local_prettier="$(project_prettier)"; then
    "$local_prettier" --ignore-unknown --write "$fp" 2>/dev/null
  else
    npx --yes --prefer-offline "prettier@$prettier_version" --ignore-unknown --write "$fp" 2>/dev/null
  fi || echo "[format] warning: prettier format failed for $fp" >&2
}

case "${fp##*.}" in
  md|mdx)
    format_with_prettier
    exit 0
    ;;
esac

has_project_config() {
  [ -z "$git_root" ] && return 1
  local name
  for name in "$@"; do
    [ -f "$git_root/$name" ] && return 0
  done
  return 1
}

biome_bin="$(mise which biome 2>/dev/null)"

if has_project_config biome.json biome.jsonc; then
  if [ -n "$biome_bin" ]; then
    "$biome_bin" format --write "$fp" 2>/dev/null || \
      echo "[format] warning: biome format failed for $fp" >&2
  fi
elif has_project_config .prettierrc .prettierrc.json .prettierrc.yml .prettierrc.yaml .prettierrc.js .prettierrc.cjs .prettierrc.mjs prettier.config.js prettier.config.cjs prettier.config.mjs .prettierrc.toml; then
  format_with_prettier
else
  if [ -n "$biome_bin" ]; then
    "$biome_bin" format --write --config-path "$HOME/.claude-shared/biome.json" "$fp" 2>/dev/null || \
      echo "[format] warning: biome format failed for $fp" >&2
  else
    echo "[format] warning: biome not found — install with 'mise use -g biome'" >&2
  fi
fi

exit 0
