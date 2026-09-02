---
name: cockpit:ticket:1:br
description: Write BR (business refinement) output for a cockpit ticket - Validation Steps for features, Expected Outcome for timeboxes. Use when a ticket enters BR by AI.
---

# BR

Write the business refinement output for the registered cockpit ticket. BR captures _what and why_ (user-facing outcome), never _how_ (implementation).

Read `~/.claude-shared/templates/ticket-page.md` before writing.

Read `~/.claude-shared/templates/cockpit-operating-contract.md` first.

Read `~/.claude-shared/templates/cockpit-cross-board.md` when the registered ticket carries a source ticket on another board.

Read `~/.claude-shared/templates/notion-writing.md` before writing to the page.

Read the ticket's open comments before drafting, following `~/.claude-shared/templates/page-comments.md`.

Check the outcome is not already delivered before drafting, following `~/.claude-shared/templates/already-done-check.md`. A hit stops the draft.

A decision the draft cannot settle is raised on the ticket, beside the line it concerns - never in a chat nobody is reading. Follow `~/.claude-shared/templates/raise-a-decision.md`.

## Pre-existing content guard

Before writing BR output, read the target section with `"$HOME/.cockpit/scripts/ticket-read" <ticket-url> --section "<heading>"` and check whether it already has content. Exit 7 is the section being absent:

- Feature: `## Validation Steps` with at least one checklist item.
- Bug: `## Replication/Validation Steps` with at least one checklist item.
- Timebox: `## Expected Outcome` with at least one numbered item.

If the section exists and has content, the guard's job is to stop the agent rewording someone else's text unasked - never to re-ask a change they have already asked for.

**A standing instruction stands the guard down.** When the person's own words - a comment on the page, or an instruction in this session - already say what changes in that section, make the change, report what was written, and ask nothing. There is no question, so the ticket is not flagged Blocked either.

An instruction covers the change when acting on it has one reading. "Raise the second scenario as its own ticket" says that scenario leaves the page, so removing it is covered. "Have a look at the second scenario" names no change, so it is not - and a change the instruction is silent on stays behind the guard even when the same comment covered another one.

Otherwise the guard stands:

1. Do **not** write to the ticket page - leave the original content unchanged.
2. Draft the suggested BR content following all the rules below (ticket type, golden path, exclusion list, formatting).
3. Raise the redraft on the ticket, following `~/.claude-shared/templates/raise-a-decision.md`, with the drafted content in the comment itself - that comment is the only copy a reader gets, so a redraft summarised rather than quoted is a redraft nobody can accept.
4. Keep the original. Overwriting what a person wrote is theirs to ask for.

If the section is absent or empty, write directly as before.

## Output by ticket type

### Feature tickets

BR writes exactly one section - no others:

```
## Validation Steps
```

No `## User Story`, `## Risks`, `## Complexity`, `## Implementation Notes`, or any other heading. User Story is redundant when validation steps are clear - the ticket title carries the outcome, validation steps carry the acceptance criteria. Complexity belongs in TR; Risks are not written on tickets at all.

**Validation Steps** - one scenario covering the golden path only. Use first person (`I`), `AaUser` on its own line, Given/When/Then at the same level as AaUser, and nest `And` under its parent clause:

```
- [ ] AaUser
- [ ] Given I have active subscriptions
- [ ] When I open the dashboard
- [ ] Then I see a summary card for each subscription
	- [ ] And each card shows the renewal date
```

**Golden path only** - validation steps cover the single most important user journey. Edge cases, error states, and secondary flows are split into separate tickets - never added as extra scenarios on the same ticket. One scenario per feature. Invoke `/cockpit:ticket:x:split` to do it: the ticket stays as the parent carrying the golden path, and each extra scenario becomes a sub-ticket.

**Title** - succinct, the outcome not an instruction (e.g. "Agents understand BR vs TR" not "Teach agents to distinguish BR vs TR").

### Bug tickets

BR writes exactly one section:

```
## Replication/Validation Steps
```

One scenario reproducing the bug and stating the expected fix. Use the same Given/When/Then structure as features, with two additions:

- Annotate the `Then` clause with `(bug)` to mark the current broken behavior.
- Nest an `Instead of` clause under `Then` with `(fix)` to state the expected correct behavior.

```
- [ ] AaUser
- [ ] Given I am on the settings page
- [ ] When I tap the save button
- [ ] Then the app crashes (bug)
	- [ ] Instead of saving my changes and showing a confirmation (fix)
```

Same golden-path-only rule and exclusion list as features. One scenario per bug.

**Title** - succinct, the defect not an instruction (e.g. "App crashes on save" not "Fix the crash when saving").

### Timebox tickets

BR writes exactly one section:

```
## Expected Outcome
```

Numbered items defining what success looks like.

**Title** - `[duration] topic`.

A timebox page runs Expected Outcome, Outcome, Context, Details - the shape is in `~/.claude-shared/templates/ticket-page.md`. BR writes only the Expected Outcome; the rest is written while the timebox is worked.

### Rename the session with the ticket

The session was named after the ticket's title as it stood at registration. When the title rule above gives the ticket a different title, do both in the same pass:

1. Set the ticket's `Name` property via `notion-update-page` (`update_properties`).
2. Rename the session under `~/.claude-shared/templates/session-name.md`, which holds the retitle rule: the bracket stays, the description becomes the new title.

Never leave out the second step - the session and the card then read as two different pieces of work for the rest of the session.

## Validation Steps must describe observable behavior

Every Validation Step must describe what a user _sees or does_ - never how the system implements it.

**Wrong** (implementation detail leak):

```
- [ ] AaUser
- [ ] Given I have set region filters in the config
- [ ] When the system calls the Bedrock ListFoundationModels API
- [ ] Then it filters results by the configured region and returns matching models
```

**Right** (observable behavior):

```
- [ ] AaUser
- [ ] Given I have set region filters
- [ ] When I open the model selection page
- [ ] Then I see only models available in the configured region
```

The wrong example names an API, describes a system call, and talks about returning results. The right example describes what I see on screen.

**Wrong** (too many scenarios):

```
- [ ] AaUser
- [ ] Given the sign-in screen is showing a QR code
- [ ] When I scan it with my phone
- [ ] Then the TV transitions to the home screen
- [ ] AaUser
- [ ] Given I pressed "Trouble signing in?"
- [ ] When I reach the fallback sign-in screen
- [ ] Then I see a user code and instructions
- [ ] AaUser
- [ ] Given the fallback screen is showing a user code
- [ ] When I enter the code on the website
- [ ] Then the TV transitions to the home screen
```

**Right** (golden path only, edge cases split to separate tickets):

```
- [ ] AaUser
- [ ] Given I am on the sign-in screen
- [ ] When I scan the QR code with my phone
- [ ] Then the TV transitions to the home screen
```

The wrong example splits three paths into three scenarios on one ticket. The right example covers the golden path; the fallback flow becomes its own ticket.

**Exclusion list** - these never belong in Validation Steps:

- API names (Bedrock, S3, GraphQL mutations)
- File paths or config keys
- Config values (indentation settings, strict mode flags, naming conventions)
- Function, class, or component names
- Library or framework names
- Code patterns or algorithms
- Database queries or schemas
- Technical error codes

## Anti-examples

**Tech detail leak** - an agent investigating which AWS API to use during BR wrote the API choice and implementation approach under the BR section. That is TR output - it belongs in Tech Steps, not in Validation Steps. BR should have captured _what the user needs to see_ (filtered model list), not _how to filter it_ (Bedrock ListFoundationModels API).

**Verbose scenarios** - an agent writing validation steps for a sign-in feature created four separate scenarios (QR code flow, fallback flow, manual code entry, error state). Only the golden path (QR code scan → home screen) belongs in validation steps. The fallback and error flows are edge cases that should be split into separate tickets.

## Self-check

After writing BR content to the ticket page, verify:

1. **Sections** - only the allowed sections for this ticket type exist as top-level `##` headings (plus `## Context` if background is needed). No ad-hoc headings. Verify `## User Story` is absent - it is never written.
2. **Validation Steps** (features) - one scenario, golden path only, first person (`I`), `AaUser` on its own line. Scan each clause for anything from the exclusion list. If edge cases exist, they become separate tickets.
   - **Actor check** - for each `When`, confirm a human could perform it through a surface they actually interact with. An agent-only command or an internal call fails this even when no exclusion-list term appears.
   - **Board-transition check** - when a `When` names a board column, it must exist in the canonical column order and be the column the ticket's behaviour actually targets.
   - **Symmetric-subject carve-out** - when the subject is inherently two-sided (BR and TR, create and delete), both sides are the golden path. Do not split one half out as an edge case.
3. **Replication/Validation Steps** (bugs) - one scenario, `AaUser` on its own line, `Then ... (bug)` with nested `Instead of ... (fix)`. Scan each clause for anything from the exclusion list.
4. **Expected Outcome** (timeboxes) - describes what the timebox should produce, not how.

If any check fails, fix the content before moving on.

## Advance

After the self-check passes, invoke `/cockpit:ticket:x:status` targeting Ready for BR. This advances the ticket out of In BR by AI so the board reflects that BR drafting is complete and the card is ready for human review.
