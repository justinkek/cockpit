# Open comments on a cockpit ticket

Drafting from the ticket body alone misses feedback a reviewer left as a comment. Read the comments first, so the draft answers them instead of the chat re-asking what the ticket already answers.

## Reading them

One read sees everything open:

    "$HOME/.cockpit/scripts/board-card" comments <card-id>

It prints one block per thread: the thread id and the text it is anchored to (or `the page`), then each comment in it with its id and author. Page comments and line-anchored ones come back alike. Resolved threads stay out - a resolved comment is feedback already acted on - so `--all` is never passed here.

No output means there are none. Say so in the report and draft as normal.

When a comment contradicts the ticket body, the comment wins - it is the later statement.

## A file left on a comment

A comment that points at a file names a path under `attachments/<card-id>/`. That path is relative to the board directory `"$HOME/.cockpit/scripts/board-card" path` prints. Open it with the Read tool.

Asking the person to paste the file into the chat is not the fallback.

## Leave no comment behind

A comment the draft has answered must not still be open on the ticket - the reviewer would have to re-read it to find out it is dead. Once the redrafted section is written, resolve each thread it answered by the id on its first line:

    "$HOME/.cockpit/scripts/board-card" resolve <card-id> <thread-id>

- Resolve only what the draft actually answered, and the decisions the next section closes. A comment it left open stays open, and the report names it.
- Do this once, at the end, not per section.
- No open comments means nothing to resolve.

## A decision a session raised

A thread whose first comment carries `**[suggestion]**` and an author starting `claude` is a decision a session raised. The session reading it now acts on it, whether or not its draft touched that line:

- **A person has replied under it.** Act on the reply by `## Once it is answered` in `~/.claude-shared/templates/raise-a-decision.md`. A reply that asks something back is not an answer: reply in the thread following `~/.claude-shared/templates/ticket-comment-reply.md`, and leave it open.
- **No person has replied, and the ticket has moved past a gate since it was posted.** Resolve it and change nothing on the card. What the ticket holds now is what the person let through, whether that is the default the suggestion names, a value a person put there instead, or the original a redraft was offered against.
- **No person has replied, and the ticket has not moved past a gate since.** It stays open.

A gate is `In BR`, `In TR`, `In CR` or `In FR` on a ticket, and `In FD`, `In TD` or `In Ticket Breakdown` on an epic. Two reads say whether the ticket has moved past one:

    "$HOME/.cockpit/scripts/board-card" comments <card-id> --json
    "$HOME/.cockpit/scripts/board-card" show <card-id> --json

The first carries each comment's `at`. The second carries the ticket's `status`, and under `dates` the time it first reached each gate. The ticket has moved past a gate when its `status` comes after that gate in the order `board-card statuses` prints, with `--kind epic` for an epic, and the thread's first `at` is earlier than that gate's date. A card in `Done` has moved past every gate, whenever the thread was posted.

A card a person dragged back to a gate or before it has not moved past that gate.
