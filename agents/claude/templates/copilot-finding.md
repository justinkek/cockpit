# A finding in a copilot session

Read this when a session started by `/cockpit:ticket:0:copilot` hits something it cannot resolve.

A session started that way is unattended: nobody is reading the chat. A finding stops the ticket and is reported on it:

1. Set `Blocked` on the ticket and comment, exactly as `~/.claude-shared/templates/blocked-flag.md` says - same property, same comment format, same agent marker.
2. Then stop work on the ticket and say in the chat that you did.

- **A finding is a defect, a blocker, or a question the session cannot resolve.** Anything it worked around, and anything it merely noticed, stays in the transcript.
- **One comment per finding, posted when it surfaces** - never held back to the end, which a session that is stopped never reaches.
- **A finding about one line goes on that line.** Follow `~/.claude-shared/templates/raise-a-decision.md`, which posts it beside the line and falls back to the agent's own Notion connection on a machine with no credential stored. A page-level comment is for a finding about the ticket as a whole.
- **Never raise a ticket for it.** Raising one is the user's decision, and the comment is what lets them make it.
- **Never move the card.** The flag and the comment both sit on it and leave the work in the column it was in.
