# Check the ticket is not already done

A ticket can sit on the board long enough that other work delivers what it asks for. Nothing later in the flow asks whether that happened, so the refinement gets written and the diff gets built a second time.

Run this before drafting refinement output, and before the first edit.

## What to look for

The outcome is the validation steps' Then and And clauses, not the title. Take each one and ask what would have to be in the repo for it to hold already.

## Looking

Grep for the behaviour and read what the grep hits. Search the words the behaviour would be written in, not the ticket's own wording - whoever put it in place phrased it their way, not the way the ticket was raised.

## What you found

- Nothing - say so in one line and carry on.
- The whole outcome - name the files and lines that hold it, quote the part that answers the Then, and stop. No refinement output, no edit.
- Part of it - name what is there and what is missing, and stop the same way. A partial hit narrows the ticket, and narrowing is not yours.

Stopping means asking what to do - close the ticket, narrow it, or carry on because what is there is not enough. Report the finding and wait.
