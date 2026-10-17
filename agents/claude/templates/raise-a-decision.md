# Raise a decision on the ticket

A session drafting in a by-AI column is unattended: nobody is reading the chat. A decision asked there waits on an answer that is not coming. So it goes on the ticket, beside the line it concerns, and the session carries on.

## Post it

Anchor the comment to the line it concerns:

    "$HOME/.cockpit/scripts/board-card" comment <card-id> --anchor "<line>" <<'EOF'
    **[suggestion]** …
    **[why]** …
    EOF

`<line>` is matched exactly against the ticket's markdown body, so copy it from a fresh `board-card show <card-id> --json` rather than from the text you sent earlier, list markers and inline markdown included. A validation step is often quoted again in the tech steps, so pick a span unique to the line - a middle clause usually is - rather than its first words.

| Exit | What it means                                        | What to do                                       |
| ---- | ---------------------------------------------------- | ------------------------------------------------ |
| 0    | Posted. The comment id is on stdout.                 | Nothing. Carry on drafting.                      |
| 2    | The anchor text is not in the body, or no text came. | Copy the line again from a fresh read and rerun. |
| 3    | No such ticket.                                      | Check the ticket id.                             |

A decision about the ticket as a whole takes no `--anchor` and goes on the page. Open that comment by quoting the line it concerns, if any:

    **On:** Then I see a summary card for each subscription
    **[suggestion]** …
    **[why]** …

## Then carry on

Posting is not a pause. The comment is where the decision now lives, so the session takes the default its caller names and finishes the run.

A caller that names no default has the defect, not the session. Take the option that changes nothing - leave the value unset, leave the page as it was - and say in the comment which one you took.

## Once it is answered

A decision still open after it is made reads as feedback waiting at every later stage, and the PR inherits it. Whichever session next reads the thread acts on the person's reply, and closes it:

1. Read the section the answer changes fresh, with `board-card show <card-id> --section <heading>`, and write it back amended with `board-card section` - an approved divergence rewrites its step in `## Tech Steps`. A reply that keeps what the ticket already says changes nothing here.
2. Resolve the thread with `"$HOME/.cockpit/scripts/board-card" resolve <card-id> <thread-id>`, where `<thread-id>` is the id on the thread's first line.

A `[suggestion]` nobody replied to is closed by `## A decision a session raised` in `~/.claude-shared/templates/page-comments.md` instead.

## What is worth a comment

A decision the draft cannot settle: a scope question, a choice between two readings, a constraint that changes the outcome. One comment per decision, posted when it surfaces - never held back to the end, which a session that is stopped never reaches.

Anything the session worked around, and anything it merely noticed, stays in the transcript.
