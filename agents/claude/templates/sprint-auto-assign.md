# Assign the current sprint

Follow this wherever a ticket arrives in `Sprint Backlog` or a column after it.

## The opt-out

A repo whose `## Ticket walk skip` section in `./AGENTS.md` lists `Sprint Backlog` never crosses the sprint ceremony, so a sprint on its tickets means nothing. Read that section first: when `Sprint Backlog` is listed, assign nothing and raise nothing.

That section is the only switch. Never add a second one to configure the same thing twice, and never fall through to step 4 below in a repo that has opted out.

## Assigning

1. Stop when the ticket's `Sprint` is already set - read it with `"$HOME/.cockpit/scripts/board-card" show <id> Sprint` - never overwrite an existing value.
2. List the sprint records with `"$HOME/.cockpit/scripts/board-card" list --kind sprint --json`, and take the one whose `start` <= today <= `end`. There are a handful of them, so no filter is needed.
3. Exactly one record matches - set the ticket's sprint to its id and `Due` to its `end`:

   ```
   "$HOME/.cockpit/scripts/board-card" set <id> sprint SPR-<n>
   "$HOME/.cockpit/scripts/board-card" set <id> due <YYYY-MM-DD>
   ```

4. Zero records or more than one match - leave `Sprint` and `Due` unset and raise it on the ticket, following `~/.claude-shared/templates/raise-a-decision.md`. An unassigned sprint is visible on the board; a stopped walk is not.
