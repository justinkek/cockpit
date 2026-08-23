# A ticket whose content lives on another board

Read this when the registered ticket was created from a URL on another board, and when splitting one.

## Cross-board work (cockpit + source ticket)

When a ticket originates from another board, the cockpit stub is a lightweight tracking card - it carries status, dates, cost, and epic linkage, but no content. All content (BR user story, validation steps, TR tech steps, dev notes) is written to the **source ticket** (the page on the originating board). The source ticket owns status: a change is written there first, and the cockpit is then walked to the column that mirrors it. The map both ways, and what happens when the source card moves backwards, are in `~/.claude-shared/templates/mirror-source-status.md`. The source-ticket URL is stored in `~/.local/state/claude-ticket-sessions/<session_id>.source-ticket`; when this file exists, write content there instead of the cockpit ticket. When it does not exist (native cockpit ticket, no source), write to the cockpit ticket as before. The `/cockpit:ticket:0:register` skill registers the source ticket automatically for external URLs (case 2).

Detection runs on both boards too, not just the cockpit. The boards the agent reads are listed in `~/.local/state/cockpit/boards.json`, each naming the checkouts it serves: `/cockpit:ticket:0:copilot` offers a card waiting on the board for the checkout the session was opened in, and asks which board serves a checkout none of them claims - recording the answer, so it asks once. There is no default board, ever. A registered cross-board session watches the source card alongside the stub, so a move made by hand on either is picked up. A card claimed off the cockpit gets its stub created first, via `/cockpit:ticket:0:new`, before it can be registered.

**A claimed card stays with the session that picked it up until it reaches Done.** Both entry paths take the claim - `/cockpit:ticket:0:copilot` when it takes a waiting card, `/cockpit:ticket:0:register` when a URL is pasted - and only two things release it: the status hop that lands on `Done`, and the SessionEnd hook when the session ends first. Never a refinement column boundary, which puts the card back in the pool between stages for a second session to claim while the first still carries it. A claim is expired on whether its session is still alive, never on which column the card is sitting in.

## Splitting one

**Cross-board splits inherit the cross-board pattern.** When splitting a ticket whose session has a source ticket (cross-board), create the new ticket on the source board first via `notion-create-pages`, then pass the source page URL to `/cockpit:ticket:0:new` as the source ticket URL. The cockpit stub is tracking-only; content lives on the source board.
