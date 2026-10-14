# What the diff did differently from the tech steps

Read the ticket's `## Tech Steps` and the diff side by side, and report where the two do not match.

## Getting the steps

The registered card's id is on one line in the session marker at `~/.local/state/claude-ticket-sessions/<session id>.ticket` - read it with the Read tool. Read the steps with `"$HOME/.cockpit/scripts/board-card" show <id> --section "Tech Steps"`.

Exit 7 means the card has no `## Tech Steps`: say so and report nothing.

## What counts

- **A step delivered another way** - it named a file, a call or a shape, and the diff uses a different one.
- **A step not delivered** - nothing in the diff answers it.
- **A step delivered somewhere else** - the change is there, under a path the step did not name.
- **A change no step asked for** - something in the diff that no step names.

## What does not count

Wording. A step delivered in different words from the ones it was drafted in is delivered.

A step whose code block was elided down to the decisions, where the diff fills in what was elided.

A fix made in response to an earlier pass on this same landing.

A divergence a person approved in a reply on the card before this pass ran. A settled thread may already be resolved, and the section read above prints only open ones, so read every thread with `"$HOME/.cockpit/scripts/board-card" comments <id> --all`.

## Reporting

One finding per line, each naming the step it came from and opening with the `path/to/file.ext:123` it is about. A step not delivered has no line in the diff - name the file the step pointed at.

A divergence is not a defect on its own. It is a human amendment decision, and the shared rules say who makes it.
