# Assign the current sprint

Follow this wherever a ticket arrives in `Sprint Backlog` or a column after it.

## The opt-out

A repo whose `## Ticket walk skip` section in `./AGENTS.md` lists `Sprint Backlog` never crosses the sprint ceremony, so a sprint on its tickets means nothing. Read that section first: when `Sprint Backlog` is listed, assign nothing and raise nothing.

That section is the only switch. Never add a second one to configure the same thing twice, and never fall through to step 4 below in a repo that has opted out.

## Assigning

1. Stop when the `Sprints` relation is already populated - never overwrite an existing value.
2. Read the Sprints view - its id comes from `"$HOME/.cockpit/scripts/cockpit-board-id" get sprints-view`, see `~/.claude-shared/templates/board-ids.md` - with `notion-query-database-view`, and take the row whose `Start Date` <= today <= `End Date`. The database holds a handful of rows, so no filter is needed. Never `notion-fetch` on the data source instead: it returns the schema only and never the rows, so it cannot answer this.
3. Exactly one row matches - set `Sprints` to its URL and `Due` to its `End Date` via `notion-update-page` (`update_properties`).
4. Zero rows or more than one match - leave `Sprints` and `Due` unset and raise it on the ticket, following `~/.claude-shared/templates/raise-a-decision.md`. An unassigned sprint is visible on the board; a stopped walk is not.
