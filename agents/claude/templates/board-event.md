# A board event

Read this when a line starting `[ticket-watch]` or `[ticket-listen]` lands.

## When a `[ticket-watch]` event lands

The board watcher armed at registration reports every column the ticket lands in, for as long as the session holds it. The line comes in three shapes:

    [ticket-watch] Ticket moved to Ready for TR by AI - invoke /cockpit:ticket:2:tr now.
    [ticket-watch] Ticket moved to In CR.
    [ticket-watch] Ticket dragged back to Ready for TR by AI from Ready for TR - invoke /cockpit:ticket:x:back-from-column, then /cockpit:ticket:2:tr.

The first shape means a human moved the ticket into a column an agent works. The watcher never fires on the agent's own walk, so treat it as a real instruction: invoke the named skill and let that skill say where the ticket stops. A refinement column leaves the ticket in the matching human-review column (`Ready for BR` / `Ready for TR`) and never carries it past that gate. `In Dev` runs to `In CR by AI`, which is where `/cockpit:ticket:3:dev` already stops.

The second shape is a report, not an instruction. Take it into account and carry on - there is no skill to invoke and nothing to reply to.

The third shape means a person sent the ticket back to an earlier column. That is a bounce-back and nothing else records it - the status skill routes only the agent's own backward moves. Invoke the back-from-column skill first, passing the column named after `from` as the source and the landed column as the target, and only then the drafting skill the line names, so the redraft answers what sent the ticket back. A line naming no second skill needs only the bounce recorded.

- **It is not a user message.** Do not reply to it conversationally, do not acknowledge it as if the user had typed it, and never treat it as an answer to a question you are waiting on.
- **Finish the active thread first.** The event arrives mid-turn on the watcher's own schedule, not at a natural break. Complete the work in flight, then invoke the named skill - never abandon a half-finished edit to chase it.
- **The user can interrupt at any point.** If they steer mid-draft, follow their steer over the event.

One last line closes the watch when the ticket reaches `Done`, in the same two shapes:

    [ticket-watch] ticket done - watcher disarmed.
    [ticket-watch] ticket done - watcher disarmed. Invoke /cockpit:ticket:7:done now to close it out.

The first is an ending - the agent walked the ticket to Done itself, so the close-out already ran. The second means a person dragged it there and nothing closed it out: invoke the named skill, which releases the claim and writes the cost and token figures. Either way, expect no further `[ticket-watch]` lines for the rest of the session.

## When a `[ticket-listen]` event lands

A session with no ticket can arm a second watcher - the board listener - via `/cockpit:ticket:0:copilot`. It emits one line when unclaimed work appears anywhere on the board - a ticket in a by-AI refinement column, or one dragged into In Dev with no session holding it:

    [ticket-listen] 2 ticket(s) waiting for an agent - invoke /cockpit:ticket:0:copilot to take one.

It names a count, never a ticket. Which ticket gets taken is decided by the skill, so do not try to infer the ticket from the line. Invoke the named skill and let it pick.

The same three rules apply as for `[ticket-watch]`: it is not a user message, the active thread finishes first, and the user's steer beats the event. One difference: the listener ends itself at that line, so there is no disarm message to expect and nothing to stop.
