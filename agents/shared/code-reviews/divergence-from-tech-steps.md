# What the diff did differently from the tech steps

Read the ticket's `## Tech Steps` and the diff side by side, and report where the two do not match.

## Getting the steps

The registered ticket's URL is on one line in the session marker at `~/.local/state/claude-ticket-sessions/<session id>.ticket`. Fetch that page and read `## Tech Steps` off it.

A page with no `## Tech Steps` ends the pass: say so and report nothing.

## What counts

- **A step delivered another way** - it named a file, a call or a shape, and the diff uses a different one.
- **A step not delivered** - nothing in the diff answers it.
- **A step delivered somewhere else** - the change is there, under a path the step did not name.
- **A change no step asked for** - something in the diff that no step names.

## What does not count

Wording. A step delivered in different words from the ones it was drafted in is delivered.

A step whose code block was elided down to the decisions, where the diff fills in what was elided.

A fix made in response to an earlier pass on this same landing.

## Reporting

One finding per line, each naming the step it came from and opening with the `path/to/file.ext:123` it is about. A step not delivered has no line in the diff - name the file the step pointed at.

A divergence is not a defect on its own. It is a human amendment decision, and the shared rules say who makes it.
