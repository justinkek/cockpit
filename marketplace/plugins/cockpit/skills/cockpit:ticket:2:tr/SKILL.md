---
name: cockpit:ticket:2:tr
description: Write TR (technical refinement) output for a cockpit ticket - Tech Steps and Complexity. Use when a ticket enters TR by AI.
---

# TR

Write the technical refinement output for the registered cockpit ticket. TR captures _how_ (implementation) - never _what/why_ (that's BR).

Read `~/.claude-shared/templates/ticket-page.md` before writing.

Read `~/.claude-shared/templates/cockpit-operating-contract.md` first.

Read `~/.claude-shared/templates/cockpit-estimating.md` before proposing Complexity.

Read `~/.claude-shared/templates/coding-conventions.md` before drafting the code a tech step shows.

Read `~/.claude-shared/templates/cockpit-cross-board.md` when the session has a source ticket.

Read `~/.claude-shared/templates/notion-writing.md` before writing to the page.

Read the ticket's open comments before drafting, following `~/.claude-shared/templates/page-comments.md`.

A decision the draft cannot settle is raised on the ticket, beside the line it concerns - never in a chat nobody is reading. Follow `~/.claude-shared/templates/raise-a-decision.md`.

## Prerequisite

The ticket must have BR content before TR can start:

- Feature: `## Validation Steps` present with at least one checklist item.
- Bug: `## Replication/Validation Steps` present with at least one checklist item.
- Timebox: timeboxes skip TR entirely (no tech steps). If invoked on a timebox, say so and stop.

If BR content is missing, block and name what's missing.

Then check the outcome is not already delivered, following `~/.claude-shared/templates/already-done-check.md`. A hit stops the draft.

## Output

TR writes into exactly two sections - no others:

```
## Tech Steps
## Details
```

Never add `## Risks`, `## Complexity`, `## Implementation Notes`, or any other heading. Complexity goes inside `## Details`; Risks are not written at all.

Never modify `## Validation Steps` - that is BR output.

### Tech Steps

A diff code block opens the section: the file tree the steps touch, each file marked `+` new, `-` removed or `!` edited, then one sentence of what it needs - the step summary above its `In <path>` toggle is that sentence. Directory lines carry a leading space, so the markers line up and the tree stays aligned.

Every file line is joined to the folder above it: `├── ` when another entry follows it in that folder, `└── ` when it is the last, and a folder with entries still to come carries `│` down the column its own join sat in. A file line reaching its name on indentation alone is refused.

```
======================================== add a visualisation of the tech steps =========================================
  dotfiles/
! ├── CLAUDE.md                             add a section for the drawings that open the tech steps
  └── agents/claude/
      ├── skills/
!     │   └── cockpit:ticket:2:tr/SKILL.md  add instructions for a file tree then a sequence flow
      └── hooks/tests/
+         └── test-tech-step-drawings.sh    add tests for the markers, the headings and the shading
```

One tree per thing the ticket does, each headed by what it does, centred in a 120 character rule of `=`. A ticket doing one thing has one tree, and it carries that heading too. One line per file, however many changes that file takes - the step toggles below carry them one by one. A file two trees both touch appears in both, carrying the sentence for that tree only. Every sentence in a tree starts at the same column, one space past the longest path line in that tree.

Below it sits a sequence flow, drawn only when the change spans more than one call: one lane per file or skill it runs through, the calls between them in order, and what each returns. The tree is a `diff` block, the sequence flow a `mermaid` one carrying `title` and `autonumber`. Both sit above the first layer toggle, tree first.

A `rect` shading a run of calls carries the tree's meaning: green `rgb(220, 245, 220)` for a call the change adds, red `rgb(255, 225, 225)` for one it removes, and no shading for one that already happens and about which nothing has changed. A call that changes is drawn twice - the old one red, above the new one in green. `autonumber 1` between them resets the counter.

Each arrow's label is the middle of a sentence - the sender, the label, then the receiver - so `writes the file tree as a diff code block on` between `cockpit:ticket:2:tr` and `the ticket page` reads as one line. A call a participant makes to itself has no receiver to append, so its label is the whole predicate.

The flow carries the call immediately before the shaded run and the one immediately after, unshaded.

A lane is named for what it is - a file or a skill by its name, anything else by a plain noun phrase, as in `the ticket page`. One flow per thing the ticket does, matching the trees. Every tree sits in one `diff` block, and each thing's flow in its own `mermaid` block below it, in the order the trees are in.

Every step, change and `In <path>` summary opens on one of five verbs: `add`, `replace`, `remove`, `rename`, `move`. Two rules on what follows:

1. **Name the thing.** "name what holds the key" names nothing - say which declaration in which file.
2. **No `so ...` clause.** The summary says what the change does, never why it was wanted.

`guard-tech-steps.sh` refuses a write that breaks either of these, or any rule above about how the tree and the flow are built. Whether a summary names the thing, whether an arrow label reads as a sentence and whether the right calls are drawn are not machine-checkable and stay rules here.

Implementation steps structured as nested toggles, organized by layer, concern, and intent. Every individual change gets its own toggle: the summary carries the intent, the body carries the code.

````
## Tech Steps
<details>
<summary>FE Layer **(3 points)**</summary>
	<details>
	<summary>[data] fetch and cache the user profile so the settings form can pre-fill</summary>
		<details>
		<summary>In src/hooks/useUserProfile.ts - one query hook, cached under a stable key</summary>
			```ts
			export const useUserProfile = (): UseQueryResult<UserProfile> =>
			  useQuery({ queryKey: ['user', 'profile'], queryFn: getUserProfile });
			```
		</details>
	</details>
	<details>
	<summary>[ui] stop the settings form losing edits when the profile refetches</summary>
		<details>
		<summary>In src/components/ProfileForm.tsx</summary>
			<details>
			<summary>a background refetch must not clobber a dirty form</summary>
				```diff
				-  const { data } = useUserProfile();
				+  const { data } = useUserProfile({ refetchOnWindowFocus: false });
				```
			</details>
			<details>
			<summary>surface the submit failure instead of swallowing it</summary>
				```diff
				   const onSubmit = async (values: ProfileValues) => {
				     ...
				-    await updateProfile(values);
				+    const result = await updateProfile(values);
				+    if (result instanceof Error) setError(result.message);
				   };
				```
			</details>
			- regenerate the form's snapshot test (output is a fixture, cannot be shown here)
		</details>
	</details>
</details>
````

Format rules:

1. Top-level toggles are **layers**, picked from the fixed set below - never invented to fit a ticket. A layer is a distinct execution context; the test is _who or what runs this?_ Two things run by the same thing in the same way are one layer, not two.

   | Layer     | Who runs it                                          |
   | --------- | ---------------------------------------------------- |
   | `FE`      | the browser or RN runtime                            |
   | `BE`      | the server                                           |
   | `Native`  | the OS directly - iOS/Android, bridge, manifests     |
   | `Infra`   | the cloud provider or CI                             |
   | `Testing` | CI, against product code                             |
   | `Tooling` | the user's shell - scripts, aliases, local commands  |
   | `Agent`   | the agent or its harness                             |
   | `Board`   | the Notion cockpit - schema, properties, automations |
   | `Docs`    | a human reading them                                 |

   The toggle summary is the layer name followed by the word `Layer` - `Agent Layer`, `FE Layer`, `Docs Layer`.

   If a change genuinely fits none of these, name a new layer and add it to this table in the same commit - never leave it as a one-off label.

2. Second-level toggles are **concerns**, picked from the fixed set for that layer. A layer with no entry below has no concern level - and no `[concern]` prefix either. Never invent a concern to fill the slot.

   | Layer                                | Concerns                                                            |
   | ------------------------------------ | ------------------------------------------------------------------- |
   | `FE`                                 | `data`, `ui`, `state`, `routing`                                    |
   | `BE`                                 | `routes`, `middleware`, `services`, `persistence`, `jobs`, `auth`   |
   | `Infra`                              | `networking`, `iam`, `storage`, `ci`                                |
   | `Testing`                            | `unit`, `integration`, `e2e`                                        |
   | `Agent`                              | `skills`, `instructions`, `hooks`, `settings`, `scripts`, `testing` |
   | `Native`, `Tooling`, `Board`, `Docs` | none - the layer is already the division                            |

   A concern toggle's summary is the concern in square brackets - `[skills]`, `[ui]` - never bare.

   When a layer has concerns but one of them holds a single step, drop the concern toggle and prefix the step summary with the same bracketed form, e.g. `[ui] let the user edit their profile`, so collapsed and expanded concerns read alike. A concern outside this table means adding it to the table in the same commit - never a one-off label.

3. Step toggles explain **why** (the purpose/intent) in the summary. The toggle body contains the **what**: the `In <path>` toggles, and bullets for any change that cannot be shown as code. Never leave a toggle body empty.
   - **The summary names what the change achieves, never the defect it removes.** "nothing names the shape that fails the rule" proposes leaving that gap in place, and a reviewer reads it as an argument for the defect; "name the shape that fails the rule" says what the step delivers. Write the state the step brings about.
4. **One toggle per change, never a wall** - inside `In <path>`, each individual change gets its own toggle: summary is the intent, body is a single code block.
   - **Never stack changes into one block.** Two edits to the same file are two toggles. No `@@` hunk headers - the summary is the header.
   - **A file with exactly one change collapses**: the `In <path>` toggle holds the block directly and its summary carries the intent, e.g. `In src/hooks/useUserProfile.ts - one query hook, cached under a stable key`.
   - **Edits** use a `diff` block; **new files** use a block in the file's own language showing what defines it - signature, exported shape, or the whole body when under ~10 lines.
   - **Elide down to the decisions**, the `+` side included. Keep the line's `-`, `+` or context marker, put `...` on its own line, and name what was dropped - `... (2 sub-bullets: exact values; create/update prefix)`. Wording is dev's job; every line someone could say no to stays in full.
   - **After-text that cannot be known yet** stays inside the block as a single `+` line, never as prose beside it.
   - **Changes with nothing showable** - one that is itself a code fence, which cannot nest - stay as plain bullets under the toggles.
   - **Many changes group.** When an `In <path>` toggle would hold more than five change toggles, add a level between them: toggles named for the theme their changes share (the point rules / the output format / the gates). These are free-form groupings within one file, not concerns from rule 2.
5. **Shared paths nest** - when multiple changes share a parent directory, group them under an `In path/` toggle instead of repeating the full path on each item. When the toggle covers more than one file, each change toggle's summary names its file, e.g. `useUserProfile.ts - cache the profile`.
6. Omit layers that have no steps - never show an empty layer toggle.
7. No numbered items inside toggles.
8. List direct dependencies only.
9. **Every layer carries its estimate** - each top-level layer summary ends with a bold point figure in round brackets: `Agent Layer **(2 points)**`, `Docs Layer **(1 point)**`. Singular `point` at 1, plural above. Only top-level layers carry points - concern, step and change toggles never do.

### Details

`## Details` holds Complexity. If the section already exists (e.g. from a prior bounce-back), append to it rather than replacing.

**Complexity** - Fibonacci estimate with rationale and reference comparison.

Output format - a toggle whose summary carries the arithmetic:

```
<details>
<summary>Complexity Breakdown: 3 = FE 2 + Testing 1</summary>
	**FE 2** - matches [reference ticket name]: [why]
	**Testing 1** - matches [reference ticket name]: [why]
</details>
```

Estimation procedure:

1. Read reference tickets by running `"$HOME/.cockpit/scripts/cockpit-cache-query" reference-tickets`. On a non-zero exit or an empty list, fetch from the `reference-tickets` id (see `~/.claude-shared/templates/board-ids.md`).
2. Compare each layer's scope (number of files, conceptual difficulty, blast radius) against references at each Fibonacci level - never the ticket as a whole.
3. Sum the layer points. The per-layer breakdown is the rationale; no independent whole-ticket figure is proposed.
4. A sum landing off the Fibonacci scale rounds up to the next value on it - 4 rounds to 5, 7 rounds to 8. Never down: rounding down hides a split.
5. If the query limit is hit, estimate without references and note that the reference comparison was skipped.
6. The proposed value is a suggestion; the human adjusts during the TR session.

### Split threshold

Propose splitting the ticket before finalizing tech steps when the summed Complexity crosses the threshold in `~/.claude-shared/templates/cockpit-estimating.md`. Name the split boundaries and suggest ticket titles, then invoke `/cockpit:ticket:x:split` to execute it - that skill owns the parent convention.

## Workflow

1. **Read the ticket** - read the BR section with `"$HOME/.cockpit/scripts/ticket-read" <ticket-url> --section "<heading>"`, and confirm it is present. Exit 7 is the block named under Prerequisite.
2. **Understand the codebase** - read the files and patterns relevant to the implementation. Grep callers of functions you plan to touch. When the steps introduce a shared procedure, grep the other skills for the concept too and make every call site its own step - a procedure wired into one caller and missed on another is the defect, not the missing caller.
3. **Draft tech steps** - write the nested checklist covering every scenario from `## Validation Steps` (features) or `## Replication/Validation Steps` (bugs).
4. **Estimate complexity** - price each layer against the reference database, then sum.
5. **Write the tree, then the sequence flow** - both are code blocks this step writes itself. The drafted steps are the input to both, so this runs before the write below, not after it. A change touching one call skips the sequence flow.
6. **Write to the ticket** - insert `## Tech Steps` and `## Details` in the correct positions to maintain canonical section order (BR section → Tech Steps → Context → Details):
   - **Tech Steps**: if a later section (`## Context` or `## Details`) already exists on the page, use `update_content` to insert `## Tech Steps` and its content before that section's heading. If no later section exists, use `insert_content` at position `end`.
   - **Details**: always insert at position `end` (it is the last section). If `## Details` already exists, append to it rather than creating a duplicate.
7. **Set the Complexity database property** - call `notion-update-page` (`update_properties`) with `{"Complexity": <numeric value>}` using the same Fibonacci number written to the page body.
8. **Self-check** - verify the output (see below).
9. **Advance** - invoke `/cockpit:ticket:x:status` targeting Ready for TR. This advances the ticket out of In TR by AI so the board reflects that TR drafting is complete and the card is ready for human review.

## Self-check

After writing TR content to the ticket page, verify:

1. **Sections** - only the allowed sections for the ticket type exist as top-level `##` headings: Validation Steps (feature) or Replication/Validation Steps (bug), Tech Steps, Context (optional), Details. No ad-hoc headings. Verify `## User Story` is absent.
2. **Section order** - `##` headings appear in canonical order: BR section → Tech Steps → Context → Details (per the ticket page template). If any section is out of order, fix it before proceeding.
3. **Tech steps format** - nested toggles organized by layer and concern. No flat lists, no empty layer toggles, no numbered sub-items. Every change carries its own toggle with one code block inside; a block stacking several changes, an item describing its change in prose, or more than five change toggles sitting flat under one path, fails this check. Every top-level layer summary ends with a bold point figure in round brackets, and no nested toggle carries one. Read every step and change summary on its own: it says what the change achieves. One naming the defect the step removes fails this check. The tree is the first thing under the heading and is a diff code block, every file it shows is a file an `In <path>` toggle names, and each is marked `+`, `-` or `!` then carries the sentence that toggle's step summary already states. The sequence flow below it is there only when the change spans more than one call, and every lane it draws is a file the tree already shows. Every thing the ticket does has its own tree under its own heading centred in a 120 character rule of `=`, one line per file, and every sentence in a tree starting at the same column. Every tree is in one `diff` block and each flow in its own `mermaid` block below, in the order the trees are in. Every summary opens on one of the five verbs, names the thing it acts on, and carries no `so` clause.
4. **Complexity** - inside `## Details`, not a standalone section. The figure equals the sum of the layer points.
5. **Coverage** - every scenario from the BR section (`## Validation Steps` or `## Replication/Validation Steps`) is addressed by at least one tech step.
6. **BR untouched** - the BR section is identical to before TR ran.

If any check fails, fix the content before moving on.
