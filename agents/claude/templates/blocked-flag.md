# The Blocked flag

Read this when work on a ticket cannot go on without something from outside the session.

When work on a ticket cannot proceed without external input - a colleague's answer, an approval, a venue reply, a CI result, or any response from outside the session - set the `Blocked` flag and comment immediately. Do not wait to be asked.

**Setting the flag:**

1. Set the ticket's `blocked` field to the reason, in one statement:

       "$HOME/.cockpit/scripts/board-card" set <ticket-id> blocked "<reason>"

2. Comment on the ticket. The comment opens with the agent marker and the reason on one line:

       "$HOME/.cockpit/scripts/board-card" comment <ticket-id> <<'EOF'
       🤖 🚧 **Blocked** - [reason, in one statement]
       ...
       EOF

   and then names:
   - What is needed (the specific input or decision).
   - Who needs to provide it (person, team, or system).
   - Why work cannot continue without it.

**Clearing the flag:**

When the blocking input arrives and the agent resumes work:

1. Clear the field with `board-card set <ticket-id> blocked ""`.
2. Comment on the ticket confirming the unblock.

**Judgement call:** "cannot proceed" means no useful work on this ticket is possible without the input. If the agent can work around the dependency or tackle other parts of the ticket, it is not blocked - continue and note the pending dependency in the ticket body instead.

**A question to the user is that input.** The base rules already say a question blocks the action it gates, so a reply that asks one has nothing left to do on the ticket until the answer lands - set the flag and comment the question in the same turn as the reply.

`note-unflagged-question.sh` records the missing flag and the next prompt opens on it. It reads the shape of the reply, not the judgement above it, so a question asked alongside work that could have carried on is named too. Answer it and the flag comes off.

This applies to any ticket type (Feature or Timebox) in any board column.
