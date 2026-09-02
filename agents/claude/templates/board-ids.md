# Board ids

The ids a skill reaches Notion through are config, not text in the skill. Read each one:

    "$HOME/.cockpit/scripts/cockpit-board-id" get <key>

It answers for the board serving the checkout this session was opened in - the same resolution `/cockpit:ticket:0:copilot` uses, so a session is never handed another project's ids. Pass a board name as a third argument to reach a board this checkout does not serve.

    "$HOME/.cockpit/scripts/cockpit-board-id" boards

prints one configured board name per line, and prints nothing when no board list has been recorded yet. It is how a skill finds the name to pass as that third argument when a person names a board rather than a checkout.

## Keys

A key names the Notion object its id points at, so the id's format reads off the key rather than off the value. A database holds one or more data sources, a data source holds the rows and the property schema, and a view is a filter over them.

| Key                             | What it reaches                                      |
| ------------------------------- | ---------------------------------------------------- |
| `page`                          | the board's own page                                 |
| `tickets-data-source`           | the Tickets data source                              |
| `epics-data-source`             | the Epics data source                                |
| `projects-data-source`          | the Projects data source                             |
| `reference-tickets-data-source` | the reference tickets used for complexity estimation |
| `sprints-data-source`           | the Sprints data source                              |
| `sprints-view`                  | the Sprints view a person looks at                   |
| `tickets-database`              | the database the Tickets data source sits in         |
| `epics-database`                | the database the Epics data source sits in           |
| `projects-database`             | the database the Projects data source sits in        |
| `reference-tickets-database`    | the database the reference tickets sit in            |

A `-data-source` key answers with a `collection://` id, which the MCP tools take. A `-database` key answers with a plain hex id, which the endpoints the shell scripts curl take.

A key outside this list is refused, so a typo cannot be recorded under a name nothing reads.

## When the id is not recorded

Exit 6 means the board is configured but that key is not. It is a question, not a failure:

1. Ask which id the board uses, once.
2. Record the answer, always - never leave it unrecorded and ask again:

       "$HOME/.cockpit/scripts/cockpit-board-id" set <key> <value>

An unattended session has nobody to ask, so the finding rule applies instead - flag the ticket `Blocked`, comment, and stop. See the "a finding in a copilot session" section of the shared rules.

## When no board claims the checkout

Exit 3 is a question, and every entry point that needs a board asks it.

1. Print the names `cockpit-board-id boards` returns and ask which of them serves this checkout. Nothing printed means no board is configured at all - ask for the name of the one this checkout works to.
2. A name outside that list is a board nobody has recorded yet:

       "$HOME/.cockpit/scripts/cockpit-board-id" create <name>

3. Record the checkout against it:

       "$HOME/.cockpit/scripts/cockpit-board-claim" <name>

4. Read the id again. A board created a moment ago holds no ids at all, so the read names the first one it needs - record each with `cockpit-board-id set <key> <value> <name>` until it answers.

Never pick for the user, and never guess from the checkout's name. If the user declines to choose, say so and stop rather than falling back to any board. An unattended session has nobody to ask, so the finding rule applies here too.

## The other exits

| Exit | What it means                           | What to do                       |
| ---- | --------------------------------------- | -------------------------------- |
| 0    | the id is on stdout                     | nothing                          |
| 2    | usage, or a key outside the list above  | fix the call                     |
| 3    | no board claims this checkout           | ask, following the section above |
| 4    | a board was named that the config lacks | fix the name                     |
| 6    | board found, key not recorded           | ask once, then `set` it          |

## Where the answer lives

`~/.local/state/cockpit/boards.json`, beside the board it belongs to - never the cockpit cache. The cache is derived data that `/cockpit:cache` rebuilds from Notion, so an id recorded there would be erased by the next refresh, and `cockpit-cache-refresh` needs the ids to run in the first place.

It sits outside the repository because `cockpit-board-id set` and `cockpit-board-claim` write it as the agent runs, and it holds one machine's Notion ids and checkout paths. `cockpit-board-id create` and `cockpit-board-id set` each create it on first use; until then every read exits 5.
