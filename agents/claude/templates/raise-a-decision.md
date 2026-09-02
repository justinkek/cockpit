# Raise a decision on the ticket

A session drafting in a by-AI column is unattended: nobody is reading the chat. A decision asked there waits on an answer that is not coming. So it goes on the ticket, beside the line it concerns, and the session carries on.

## Post it

Run the script. It anchors the comment to the exact block, a line nested under another line included.

    "$HOME/.cockpit/scripts/ticket-comment-line" "<page-id>" "<line>" "<suggestion>" "<why>"

`<line>` is the text of the line as it appears in the draft. Indentation, list markers and inline markdown are all stripped before matching, so the line can be pasted as written.

| Exit | What it means                                                             | What to do                                              |
| ---- | ------------------------------------------------------------------------- | ------------------------------------------------------- |
| 0    | Posted, and read back from the block it was meant for.                    | Nothing. Carry on drafting.                             |
| 1    | No single block matched, or Notion refused.                               | Name a longer, unique line and run it again.            |
| 2    | An argument is missing, or the line is under 12 characters once squashed. | Send more of the line.                                  |
| 3    | No credential on this machine, and the line is at the top level.          | Post it through the Notion connection - see below.      |
| 4    | No credential, and the line sits under another line.                      | Comment on the page and open with the line - see below. |

Exit 3 and exit 4 are never a reason to give up on the comment. Each is the machine saying which path to take, not that the decision cannot be raised.

## Then carry on

Posting is not a pause. The comment is where the decision now lives, so the session takes the default its caller names and finishes the run.

A caller that names no default has the defect, not the session. Take the option that changes nothing - leave the value unset, leave the page as it was - and say in the comment which one you took.

## The fallback

On exit 3, call `notion-create-comment` with the ticket's `page_id` and `selection_with_ellipsis` built from the line.

On exit 4, call it with the `page_id` and no selection at all. The comment goes on the page. A selection here resolves to the line above, and Notion has no delete-comment API to take that back with.

Either way, open the comment body by quoting the line it concerns:

    **On:** Then I see a summary card for each subscription
    **[suggestion]** …
    **[why]** …

On a page-level comment the quote is the only thing saying which line the decision is about.

Two ways a call carrying a selection is refused, both worth knowing before you make it:

1. **The selection appears more than once.** Notion matches across the whole page, and a validation step is often quoted again in the tech steps. Build the ellipsis from a span unique to the line - a middle clause usually is - rather than from its first and last words.
2. **The selection spans blocks.** First and last words drawn from different lines match the run between them, which is never what was meant.

## Exact anchoring on this machine

The fallback needs no setup and is the floor. A credential raises the floor to exact anchoring, and is worth storing on a machine that does refinement often.

1. Create a Notion internal integration named `cockpit-comment` with read content and insert comment capabilities, and share the Tickets database with it - `"$HOME/.cockpit/scripts/cockpit-board-id" get tickets-data-source` names which one. The API returns 404 on pages the integration has not been shared with.
2. Store the token in the macOS Keychain - never on disk, never in the environment. Run this yourself, with the `!` prefix; storing a credential is your setup step, not the agent's.

       security add-generic-password -a "$USER" -s cockpit-notion-comment-token -w

   Pass `-w` with no value: it prompts, so the token never lands in shell history. `security` warns against the inline `-w '<token>'` form itself.

The board poller's token (`cockpit-notion-token`) is deliberately read-only and cannot stand in for this one.

## What is worth a comment

A decision the draft cannot settle: a scope question, a choice between two readings, a constraint that changes the outcome. One comment per decision, posted when it surfaces - never held back to the end, which a session that is stopped never reaches.

Anything the session worked around, and anything it merely noticed, stays in the transcript.
