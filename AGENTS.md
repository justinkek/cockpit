# Dotfiles conventions

## File paths

This repo IS the source of truth that `~/.claude-shared`, `~/.agents-shared` and `~/.cockpit` symlink into. Both paths reach the same file, so which one to use depends on the verb:

- **Reading or editing a file** → repo path, e.g. `agents/claude/settings/base.settings.json`. This keeps `git diff` clean and avoids confusion about which repo the edit lands in.
- **Executing a script** → the `~/` symlink path, e.g. `"$HOME/.cockpit/scripts/cockpit-cache-query"`. Permission patterns match the literal command string and never resolve symlinks, so the repo path misses the allowlist and prompts on every call.

Which symlink depends on what the file is: the Claude configuration executes via `~/.claude-shared/`, the shared agent rules and the cross-agent skills are read via `~/.agents-shared/`, and everything the ticket board owns - its hooks, its skills and the scripts they call - executes via `~/.cockpit/`.

One execution path, always. Never add repo-path twins to the allowlist to make the other form work - that leaves two valid conventions and the prompt comes back the next time the wrong one is picked.

The shared agent rules and the adapter name each config file by its role and never by a path, so this list is what answers where a config edit lands.

Key mappings:

- `~/.claude-shared/` → `agents/claude/`
- `~/.agents-shared/` → `agents/shared/`
- `~/.cockpit/` → `marketplace/plugins/cockpit/`
- the shared agent rules - `~/.agents-shared/base.AGENTS.md` → `agents/shared/base.AGENTS.md`
- the Claude adapter - `~/.claude-shared/claude-md/adapter.CLAUDE.md` → `agents/claude/claude-md/adapter.CLAUDE.md`
- the base settings file - `~/.claude-shared/settings/base.settings.json` → `agents/claude/settings/base.settings.json`
- the base plugins file - `~/.claude-shared/plugins/base.plugins.json` → `agents/claude/plugins/base.plugins.json`

## The cockpit plugin

`marketplace/` is a plugin marketplace this repo hosts, and `marketplace/plugins/cockpit/` is the one plugin in it. It holds `hooks/hooks.json`, `scripts/` for every script the board's hooks and skills call, `scripts/hooks/` for the hooks themselves, and `skills/` for the board's skills. A test moves with its subject, so a test under `scripts/hooks/tests/` reaches its subject through the same `..` and `../..` a test in the shared root reaches its own.

`hooks/hooks.json` names its commands through the plugin root variable, which Claude Code sets only while it runs a plugin's own hook. Nothing else can read that variable, so `base.settings.json`, the permission allowlist and a skill's shell call all reach the same files through `$HOME/.cockpit/` instead.

`base.settings.json` still declares the board's hooks and `base.plugins.json` still enables no cockpit plugin, so `hooks.json` runs nothing yet. Until it does, `sync.skills.sh` carries the plugin's skills directory as a third source root; that root comes out on the commit that enables the plugin per account.

Three libraries are shared with hooks that stay in `agents/claude/hooks/` - `hook-argv-lib.sh`, `hook-stop-note-lib.sh` and `session-name-lib.sh`. A moved hook reads each through `${CLAUDE_SHARED_DIR:-$HOME/.claude-shared}`, so a test can point it at this checkout rather than a temporary home.

## Sync concerns

A concern is a folder holding a `sync.*.sh`. The orchestrator (`agents/*/sync.sh`) globs them, so a new folder is picked up with no registration step.

- **Call `confirm` before any write; never source `prompts.sh`.** The orchestrator exports it via `BASH_ENV`, so a worker has `confirm` before its own first line. A hand-rolled `/dev/tty` prompt is the bug this replaced: it swallowed the no-terminal case and printed "skipped" while applying nothing.
- **Run a concern through the orchestrator, never by its own path** - `sync.sh <concern> [--check|--apply|-y]`. The workers are deliberately not executable: run one directly and `confirm` would be undefined, which inside `if ! confirm ...` reads as "user said no" and silently skips every write.
- **`sync.plugins.sh` needs no gate** - its apply is non-interactive.
- **A plugin comes off an account by leaving `base.plugins.json`.** The apply uninstalls what the manifest no longer declares, and still never removes a marketplace. Every plugin it uninstalls is one installed for the whole account: a plugin installed for one repository is that repository's own config, and the manifest never speaks for it.

## Running every test

`./scripts/run-tests` runs every `test-*.sh` git tracks or would track under a `tests` directory, prints one line per test, and repeats each failure with its own output below the summary. It is run from this checkout on purpose, wired into no commit hook, no push hook and no shell alias, and every test runs under `bash` whatever its executable bit says.

## What a state script confirms against

A script that records session state writes its sidecar under the id the shell resolves, and its confirmation reads back that one file. Neither variable set is the only case that reaches the older scan, which takes any sidecar of the same suffix touched in the last ten seconds - so a second session's write can satisfy it. The PreToolUse hook still writes the same path from the id on its stdin, and the two agree because neither invents a name for it.

`bash ~/.claude-shared/hooks/tests/test-ticket-state-confirm.sh` covers what each of them confirms.

## The drawings that open the tech steps

A file tree in a `diff` block and, when the change spans more than one call, a sequence flow in a `mermaid` block sit above the first layer toggle. The markers, the joins, the headings, the sentence column and the shading are all in the `cockpit:ticket:2:tr` skill.

## Core instructions and on-demand references

`agents/shared/base.AGENTS.md` is loaded into every session on every turn, so it holds only what must fire before any skill runs. Procedure that a skill loads when it runs lives in `agents/claude/templates/`, and the core names the file rather than restating it. A section moves out only once something reads it back in; one that nothing would load stays in the core however rarely it fires.

A pointer at a reference carries the path and the trigger that says when to open it. A clause summarising what the reference says is not part of the trigger and comes out - the core and a skill alike.

The same holds for these project instructions, which are loaded on every turn too.

A worked example is written out in the file that carries the rules it demonstrates, and named from the others. The repetition guard skips fenced code, so nothing else catches a second copy.

Five references hold a body the core used to state: `templates/board-event.md`, `templates/blocked-flag.md`, `templates/copilot-finding.md`, `templates/ticket-comment-reply.md` and `templates/coding-conventions.md`. The two board watchers name the first on every line they emit.

## A sentence written twice

An instruction is stated in one file and named from the others. `guard-instruction-repetition.sh` refuses an edit that adds a sentence of 60 characters or more which another markdown file in this repo already holds, and names that file. Line wrapping is not part of the sentence, so rewrapping it on the way across is caught too. Moving a sentence is two edits: the cut lands first, then the pointer.

A fenced code block is skipped and only an exact match counts, so a repeated worked example and a sentence reworded on the way across both still get through.

The corpus is whichever tree the edited file sits in: a file under `.claude/worktrees/` is compared against that worktree alone, and a file in the main checkout against the checkout with every worktree left out. A dev session is therefore held to the branch it is building rather than to what main happened to say when it started. A symlink is not scanned, so the root `CLAUDE.md` does not read as a second file holding everything `AGENTS.md` says.

## Markdown wrapping

Prose in this repo's markdown is never hard-wrapped - a paragraph is one line, however long it runs. `.prettierrc` sets it, and `format-on-edit.sh` sends every `.md` and `.mdx` file it touches through prettier before it reaches any biome branch. Biome ships no markdown formatter at all, so prettier is the only one in play for these files.

That config's `useTabs` and `printWidth` are what hold everything else to what `agents/claude/biome.json` writes. A `.prettierrc` at the repo root is on `has_project_config`'s list, which moves every non-markdown edit here off biome and onto prettier - without those two keys the next edit to a settings file reformats it from tabs to spaces.

## Ticket walk skip

- Ready for Sprint
- Sprint Backlog
- Daily Plan

## Model setting

Never set `model` in `base.settings.json`. The model varies per account (direct API vs Bedrock, different ARNs) so it belongs exclusively in per-account overrides (`agents/claude/settings/overrides/<account>.settings.json`).

## Permission allowlist patterns

Every new script, hook, or skill that the agent invokes must have a matching allowlist entry in `agents/claude/settings/base.settings.json` **in the same commit**. A feature without its allowlist entry is incomplete - it will prompt on first use.

When a feature reads or writes files outside the repo (e.g. `~/.local/state/`), two things must ship in the same commit:

1. A `confine-to-repo-policy.sh` exemption for the path (otherwise the hook hard-denies writes and prompts for reads).
2. A `Read(path/**)` entry in the settings allowlist (otherwise Claude Code's permission system prompts independently of the hook).

Write the pattern the way the command is written - nothing is expanded on either side, so a pattern saying `$HOME` matches a command saying `$HOME` and a spelled-out path matches a spelled-out path. Skills invoke their scripts as `"$HOME/.claude-shared/<script>"`, so every script needs two committed entries: the `$HOME` form, quoted and unquoted. The settings sync writes each one out a second time with the home directory it runs under spelled out, so a path spelled out in this file is one machine's and matches on no other. Hooks that auto-approve a script hide a missing entry, so a pattern that has never been exercised without its hook is not known to work.

For format rules, checklist, and diagnostics, invoke `/fewest-permission-prompts`.

## Which instruction file a section belongs in

A section describing something that fires outside this repo goes in `agents/shared/base.AGENTS.md`. This repo's own layout, tests and sync stay here.

A hook or script whose behaviour is confined to this checkout is exempt, and the check names it alongside the ones documented in neither file.
