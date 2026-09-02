# Bringing a split parent along

Read this when the ticket's `Dependency for` relation is populated - it is one part of a split (see the `cockpit:ticket:x:split` skill). After the walk completes:

1. Read the parent's `Dependent on` to get every sibling, then each one's `Status`, both with `"$HOME/.cockpit/scripts/ticket-read"`.
2. Check whether **all** of them have reached the landed column or later in the canonical order. If any is behind, stop here - the parent stays put.
3. Only when all have, walk the parent to that column by re-entering the `cockpit:ticket:x:status` skill with the parent's URL and that column as target.

**Last-in, never first-in.** The parent's Validation Steps assert the whole outcome, so it has not reached a column until every part has. First-in would let the parent claim `Done` while a sibling is still open.

**The parent's roll-up is exempt from the sprint ceremony.** It crosses `Ready for Sprint → Sprint Backlog` without one, and that is deliberate: its sub-tickets were pulled by hand at the ceremony, and the parent carries zero points so it cannot distort the pull. This is the only exemption to that boundary.
