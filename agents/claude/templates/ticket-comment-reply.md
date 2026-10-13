# Replying to a comment on a ticket

Read this before posting a reply on a cockpit ticket.

A reply goes in the thread it answers - `"$HOME/.cockpit/scripts/board-card" comment <card-id> --reply <comment-id>`, with the text on stdin - and names what changed on the ticket and stops.

- **Say what changed, not why it changed.** "Tech steps redrafted, complexity 3 to 2" answers "do the tech steps change?". The root cause behind it is what the redrafted tech steps themselves now show.
- **Open with the agent marker** - the robot emoji.
- **The fixed formats are exempt** - a blocked flag, a bounce-back and a raised decision each have their own shape, defined where they are raised, and each carries more than one statement by design.

The `guard-ticket-comment-length.sh` hook refuses a reply past the ceiling, counting only the comment being posted.
