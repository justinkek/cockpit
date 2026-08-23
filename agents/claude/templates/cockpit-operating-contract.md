# Cockpit operating contract

Operating contract for humans and AI agents working the cockpit. Agents drafting FDs, TDs, BRs, TRs, or code against a ticket read this first.

## How the boards work

1. **Column pattern (refinement stages):** _Backlog_ - captured, not yet committed to refinement; only a human pull moves a card out → _Ready for X by AI_ - the agent drafts, entry is automatic → _Ready for X_ - draft attached, waiting for a human pull → _In X_ - group refinement session decides. Session membership rotates. Nobody nurses a by-AI column; cards pass through in minutes.
2. **Statuses are the gates.** Moving a card out of an In-X column _is_ the approval. Moving a ticket into Ready for Sprint asserts the Definition of Ready: TR approved, validation steps executable, Complexity ≤ 5 (within daily speed).
3. **Breakdown:** accepting the AI-proposed ticket set - and creating the tickets - _is_ the breakdown approval; the epic then moves straight to Tickets In Dev.
4. **Sprint planning is the only way onto the Sprint Board.** Ticket Kanban and Sprint Board are two views of the same tickets database, split by status. At the weekly ceremony, tickets are dragged by hand from Ready for Sprint into Sprint Backlog, pulled against last sprint's completed Complexity points. Never automated, and never outside the ceremony.
5. **Ticket types:** _Feature_ = fixed scope, output is a reviewable diff. _Bug_ = a regression in delivered functionality - behavior that contradicts the validation steps of a Done ticket. Output is a reviewable diff. Bugs use Replication/Validation Steps (not Validation Steps) for BR. A defect found during the flow (back from CR/FR/Validation) is not a bug - it is a back-from-column on the existing ticket. _Timebox_ = fixed time (Timebox (mins), clock starts at In Dev), output is a written, evidenced answer. Timebox tickets flow through the full Sprint Board: CR reviews the code it produced, FR checks the outcome against the Expected Outcome and decides follow-ups (follow-ups become new tickets), Validation checks the evidence. A timebox that produced no code walks from In Dev straight to Ready for FR - there is no code to review, and FR is what reads the answer.

## Rules

1. **One tickets database.** Both boards are saved views of it, so a card _can_ physically skip the pipeline. The boundary that must not be crossed outside the ceremony, and the split parent's exemption from it, are in the always-loaded rules - a card is dragged with no skill running.
2. Every project, epic, and ticket gets a fitting emoji icon at creation - recognisability at a glance. Agents creating pages set one without being asked.
3. **Blocked requires a comment.** When setting a ticket's status to Blocked, also add a page-level comment with a single-statement summary: **Blocked:** [reason]. See Context > [toggle name] for details. Unblocked by [link to unblocking ticket]. The detailed problem thread lives in the Context toggle; the comment is the scannable summary for the team.
4. **All ticket creation goes through `/cockpit:ticket:0:new`** - the rule is in the always-loaded rules, because it fires the moment a ticket is wanted. The skill enforces body content: a `## Context` toggle with enough detail for a fresh session to start without asking questions.
5. **An epic is chosen by the kind of work, not the closest name.** A project typically runs a dev epic and a delivery epic whose names differ by one word. Work whose output is a diff on the product belongs to the dev epic; work whose output is reporting, ceremony, or client-facing process belongs to the delivery epic.
