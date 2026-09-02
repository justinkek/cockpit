---
name: fewest-permission-prompts
description: Diagnose and fix permission prompts for internal toolchain scripts. Replaces the denied fewer-permission-prompts skill. Use when the user says /fewest-permission-prompts, "reduce prompts", or "fewest permission prompts".
---

# Fewest permission prompts

Diagnose which commands trigger permission prompts and add correct allowlist entries to `agents/claude/settings/base.settings.json`.

## Step 1: Identify what's prompting

Analyse `~/.claude-logs/prompt-audit.jsonl`. Each line records an actual permission prompt: `{ts, account, session_id, cwd}`.

To find which tool triggered a prompt, correlate `session_id` + nearest preceding `tool_use` in that session's transcript.

```bash
# Recent prompts grouped by session
tail -50 ~/.claude-logs/prompt-audit.jsonl | jq -r '[.ts, .session_id, .cwd] | @tsv'
```

## Never allowlist

Some commands must stay prompted regardless of how often they fire.

**Destructive** - delete or overwrite files: `rm`, `mv`

**Arbitrary execution** - run unconstrained code: `bash`, `python3`, `python`, `node`, `ruby`, `perl`, `sh`

**Broad script runners** - execute arbitrary project scripts: `npm run` (broad), `npm install`, `npx` (bare, without a known-safe tool)

**Navigation** - leave the repo: `cd`

When the audit identifies prompts from these commands, report them in the summary as "kept prompted (destructive/execution/navigation)" - do not propose allowlist entries for them.

**Destructive subcommands.** When allowing a read-only command that has a destructive subcommand (e.g. `npm audit` vs `npm audit fix`), add the destructive variant to the **deny** list explicitly.

## Step 2: Add allowlist entries

### Bash pattern format

Bash allowlist entries use `Bash(prefix:*)` where `prefix` must be a complete command token - the exact string the tool sees before the first argument.

**Nothing is expanded on either side - the pattern is matched against the command string as written.** So the pattern has to be written the same way the command is. A command that says `$HOME` needs a pattern that says `$HOME`; one that spells the home directory out needs a pattern that spells it out the same way. The skills in this repo invoke their scripts as `"$HOME/.claude-shared/<script>"`, so the `$HOME` form is what goes in the committed list, and `sync.settings.sh` writes the spelled-out twin of each entry into every account's `settings.json` against the home directory the apply runs under.

| Pattern                                    | Matches                                                                           |
| ------------------------------------------ | --------------------------------------------------------------------------------- |
| `Bash($HOME/.claude-shared/sync.sh:*)`     | a command written as `$HOME/.claude-shared/sync.sh`                               |
| `Bash("$HOME/.claude-shared/sync.sh":*)`   | the same, quoted - the quotes are part of the string                              |
| `Bash(/home/you/.claude-shared/sync.sh:*)` | a command that spells the path out - the apply writes this one, nobody commits it |
| `Bash(~/.claude-shared/sync.sh:*)`         | a command written with a literal `~`                                              |
| `Bash($HOME/.claude-shared/:*)`            | nothing - a partial path is not a complete command token                          |

### Adding a new script

For each `~/.claude-shared/` script, add two variants to `agents/claude/settings/base.settings.json` under `permissions.allow` - the `$HOME` form, quoted and unquoted. The apply writes the spelled-out pair beside them:

```json
"Bash($HOME/.claude-shared/script-name:*)",
"Bash(\"$HOME/.claude-shared/script-name\":*)"
```

For subdirectory scripts:

```json
"Bash($HOME/.cockpit/scripts/hooks/require-ticket.sh:*)",
"Bash(\"$HOME/.cockpit/scripts/hooks/require-ticket.sh\":*)"
```

Never commit an entry that spells a home directory out.

### Read patterns

`"Read"` in the allow list only covers in-project reads. Cross-project reads (e.g. `~/.claude-shared/templates/`) need explicit entries. A `Read` pattern is matched against an already-resolved path, so the `$HOME` form matches nothing on its own - the spelled-out twin the apply writes is what does the work:

```json
"Read($HOME/.claude-shared/**)"
```

### MCP plugin tools

MCP plugin tools bypass the permission prompt when not denied ([claude-code#80135](https://github.com/anthropics/claude-code/issues/80135)). The three-state model collapses to two: deny or auto-allow. Keep `permissions.allow` entries for when the bug is fixed, but don't expect them to gate anything today.

## Step 3: Deploy and test

1. Run `sync.sh --apply` to deploy settings to all profiles.
2. **Restart the session** - settings are cached at session start.
3. Test each script by invoking it directly (no arguments or with `--help`).
4. Confirm zero prompts appeared.

## Gotchas

- **Settings cached at session start.** Mid-session allowlist changes have no effect. Always restart after editing settings.
- **Hooks can mask broken patterns.** PreToolUse hooks that auto-approve commands (e.g. `require-rename.sh` auto-approves `auto-rename`) bypass the permission system entirely. A broken allowlist entry will appear to work until the hook is removed. Test patterns with scripts that have no auto-approve hook.
- **Piped commands.** `sync.sh --apply 2>&1 | tail -3` - the full command string is the prefix. The pattern `Bash($HOME/.claude-shared/sync.sh:*)` matches because the command starts with that path regardless of trailing pipes.
