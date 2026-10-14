# Check the ticket is not already done

A ticket can sit on the board long enough that other work delivers what it asks for. Nothing later in the flow asks whether that happened, so the refinement gets written and the diff gets built a second time.

Run this before drafting refinement output, and before the first edit.

## What to look for

The outcome is the validation steps' Then and And clauses, not the title. Take each one and ask what would have to be in the repo for it to hold already.

Before the validation steps exist, at BR, the outcome is what the card's `## Context` asks for.

## Looking

Grep for the behaviour and read what the grep hits. Search the words the behaviour would be written in, not the ticket's own wording - whoever put it in place phrased it their way, not the way the ticket was raised.

## What you found

- Nothing - say so in one line and carry on.
- The whole outcome - name the files and lines that hold it, quote the part that delivers the outcome, and stop. No refinement output, no edit.
- Part of it - name what is there and what is missing, and stop the same way. A partial hit narrows the ticket, and narrowing is not yours.

Stopping means asking what to do - close the ticket, narrow it, or carry on because what is there is not enough. The ticket waits on that answer, so set `Blocked` and comment the finding and the three options on the card, following `~/.claude-shared/templates/blocked-flag.md`. Then:

Who started the session decides it, not the column the card is in:

- Nobody reads the chat of a session a board watcher line or `/cockpit:ticket:0:copilot` started - BR or TR in a by-AI column, and dev on a card it claimed in `In Dev`, included. Leave the card in its column and end the run.
- A person reads the chat of a session they started with their own message - a BR that `/cockpit:ticket:0:register` hands on from it included. Ask the same question there and wait.

A finding the card already carries is not posted again. With no answer under it, go straight to the step after the comment. An answer settles the question: act on it, and clear the flag as `~/.claude-shared/templates/blocked-flag.md` says.
