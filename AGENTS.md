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

`hooks/hooks.json` names its commands through the plugin root variable, which Claude Code sets only while it runs a plugin's own hook. Nothing else can read that variable, so the permission allowlist and a skill's shell call reach the same files through `$HOME/.cockpit/` instead.

`base.plugins.json` declares the marketplace as `./marketplace` and the plugin at user scope, and `sync.plugins.sh` resolves that leading `./` against the repository its own manifest sits in. A marketplace served that way is registered from a path outside the account directory, so the install-health check does not report it as a foreign store.

`base.settings.json` enables the plugin for every account, and the settings sync turns it back off for one that does not work the board. Installed and not enabled is what leaves a desktop chat the skills without the hooks.

A marketplace registration is not a managed setting. `claude plugin marketplace add` writes `extraKnownMarketplaces` into an account's `settings.json` with a path only that machine has, so `base.settings.json` declares none: managing the key would make each sync strip what the other had just written. `base.plugins.json` is where a marketplace is declared, and the plugin apply is what registers it.

A skill the plugin serves is invoked under the plugin's own name, so `skills/ticket:3:dev` is reached as `/cockpit:ticket:3:dev` and its directory carries no `cockpit:` of its own. `daily-mail` is the one whose name changes, to `/cockpit:daily-mail`.

A plugin cannot carry always-on instructions, so the board's rules stay in the memory sync: `agents/shared/board.AGENTS.md` holds them and `sync.claude-md.sh` appends it to an account that works the board. The Claude adapter had no board section to move, so there is no `board.adapter.CLAUDE.md`; `sync.claude-md.sh` appends one if it ever appears.

Codex has the same shape one level up: `agents/codex/homes.sh` names the two homes, `agents/codex/sync.sh` runs every concern once per home with `CODEX_HOME` and `CODEX_HOME_NAME` set, and `~/.codex` gets neither the board rules nor `board.hooks-profile.toml` while `~/.codex-cockpit` gets both. The shell wrapper that points `CODEX_HOME` at the second one lives in the dotfiles repository, not this one.

`agents/claude/board-accounts.sh` is the one statement of which accounts those are, and both the settings sync and the memory sync read it. It sits beside `accounts.sh` rather than inside it because a test stubs `accounts.sh` to control the account list, and a stubbed-away answer here would quietly take the board off every account.

The plugin reads the shared root and nothing reads back. Four libraries stay in `agents/claude/` because a hook or script that is not the board's own also reads them - `hook-argv-lib.sh`, `hook-stop-note-lib.sh`, `session-name-lib.sh` and `ticket-state-lib.sh` - and the plugin reaches each through `${CLAUDE_SHARED_DIR:-$HOME/.claude-shared}`, so a test can point it at this checkout rather than a temporary home. `test-cockpit-plugin-manifest.sh` refuses an arrow in the other direction: a cycle would mean neither directory could be reasoned about alone.

The marketplace source is a path inside this repository, so the plugin is only ever installed from a checkout of it. That is what makes the dependency on the shared root safe, and what would have to change before the plugin could be served from anywhere else.

## The unsolicited-text plugin

How a reply reads is not this repository's any more. Response formatting, plain english, the pre-send checklist and the line ceiling live in the `unsolicited-text` repository, a sibling checkout, and arrive as a plugin installed from `../unsolicited-text/harness-adapters/claude-code`. Its own session start hook prints its `AGENTS.md` into every session, so an edit to any of those four rules lands in that repository and not in `agents/shared/base.AGENTS.md`.

`note-long-reply.sh` and `remind-response-length.sh` went with them. `replay-stop-notes.sh`, `hook-stop-note-lib.sh` and `hook-transcript-lib.sh` stayed, because `note-unflagged-question.sh` and `advance-after-dev.sh` still record through them. The plugin carries its own copies of all three and writes to a notes directory of its own, so the two sets never drain each other.

The clauses of those four rules that name the board stayed too, under `## Writing a reply about the board` in `board.AGENTS.md`. That plugin must not know a ticket board exists, and a test in its own repository refuses a board word anywhere in it.

`../unsolicited-text/...` is the first marketplace source outside this repository. `sync.plugins.sh` resolves a source starting `../` as well as one starting `./`. The two checkouts being siblings is a convention between them rather than a machine's own path, so it stays in the committed manifest.

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

A section describing something that fires outside this repo goes in `agents/shared/base.AGENTS.md` when every client needs it, and in `agents/shared/board.AGENTS.md` when only an account that works the ticket board does. This repo's own layout, tests and sync stay here.

A hook or script whose behaviour is confined to this checkout is exempt, and the check names it alongside the ones documented in neither file.
