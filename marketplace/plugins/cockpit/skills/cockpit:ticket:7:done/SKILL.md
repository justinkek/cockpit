---
name: cockpit:ticket:7:done
description: Move the session's cockpit ticket to Done.
---

# done

Move the registered cockpit ticket to the `Done` column. Two things trigger it: the user, and the watcher's line when a person dragged the card to Done. In the second case the card is already there, so the status skill runs the close-out without moving anything.

Invoke the `cockpit:ticket:x:status` skill with target `Done`. The skill handles the ordered walk, date-stamp polling, usage recording, and source ticket sync.
