# Open comments on a cockpit card

Drafting from the card body alone misses feedback a reviewer left as a comment. Read the comments first, so the draft answers them instead of the chat re-asking what the card already answers.

## Reading them

One read sees everything open:

    "$HOME/.cockpit/scripts/board-card" comments <card-id>

It prints one block per thread: the thread id and the text it is anchored to (or `the page`), then each comment in it with its id and author. Page comments and line-anchored ones come back alike. Resolved threads stay out - a resolved comment is feedback already acted on - so `--all` is never passed here.

No output means there are none. Say so in the report and draft as normal.

When a comment contradicts the card body, the comment wins - it is the later statement.

## A file left on a comment

A comment that points at a file names a path under `attachments/<card-id>/`. That path is relative to the board directory `"$HOME/.cockpit/scripts/board-card" path` prints. Open it with the Read tool.

Asking the person to paste the file into the chat is not the fallback.

## Leave no comment behind

A comment the draft has answered must not still be open on the card - the reviewer would have to re-read it to find out it is dead. Once the redrafted section is written, resolve each thread it answered by the id on its first line:

    "$HOME/.cockpit/scripts/board-card" resolve <card-id> <thread-id>

- Resolve only what the draft actually answered, and what the next section counts as accepted. A comment it left open stays open, and the report names it.
- Do this once, at the end, not per section.
- No open comments means nothing to resolve.

## A suggestion the card has moved past

A `[suggestion]` this flow posted - its author starts `claude` - with no reply under it counts as accepted once a person has moved the card out of an In-X column after it was posted, so long as the card still carries the default it names. Moving the card on is the approval, as `~/.claude-shared/templates/cockpit-operating-contract.md` sets out. The next skill that reads the comments resolves it, whether or not its draft touched that line.

A thread a person has replied to is closed by `## Once it is answered` in `~/.claude-shared/templates/raise-a-decision.md` instead.
