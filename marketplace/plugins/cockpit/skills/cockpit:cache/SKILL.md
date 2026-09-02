---
name: cockpit:cache
description: Refresh the local cache of cockpit board reference data (statuses, epics, projects, reference tickets, user ID). Run manually to pull long-lived structural data so skills can read locally instead of making Notion API calls.
---

# cache

Cache long-lived cockpit board reference data locally so skills can read from `~/.local/state/cockpit/cache.json` instead of making Notion API calls for structural lookups.

## Board constants

Read each with `"$HOME/.cockpit/scripts/cockpit-board-id" get <key>`, following `~/.claude-shared/templates/board-ids.md`.

This skill needs: `tickets-data-source`, `epics-data-source`, `projects-data-source`, `reference-tickets-data-source`, and the four `-database` keys beside them.

## Cache location

`~/.local/state/cockpit/cache.json`

## Procedure

### 1. Fetch connected user

Call `notion-fetch` with `id: "self"`. Store the user's `id` and `name`.

### 2. Fetch cockpit data sources

Make the following calls in parallel where possible:

1. **Tickets schema** - `notion-fetch` on the `tickets` id. Extract the `Status` select property's options list (the valid status values), and every property's name and type.
2. **Epics** - `query-data-sources` on the `epics` id. Capture each epic's page ID (`url`), `Name`, `Status`, and `Project`.
3. **Projects** - `query-data-sources` on the `projects` id. Capture each project's page ID (`url`) and `Name`.
4. **Reference Tickets** - `query-data-sources` on the `reference-tickets` id. Capture each ticket's page ID (`url`), `Name`, and `Complexity`.

### 3. Re-fetch cached project boards

Read the existing cache file at `~/.local/state/cockpit/cache.json`. If it exists and contains a `project_boards` object with entries, re-fetch each project board's data source using `notion-fetch` on its `collection://` URL to get the updated schema and `Status` select options.

If the cache file does not exist or has no `project_boards` entries, skip this step.

### 4. Write the cache file

```sh
mkdir -p ~/.local/state/cockpit
```

Write the combined data to `~/.local/state/cockpit/cache.json`:

```json
{
  "user": {
    "id": "<user-id>",
    "name": "<user-name>"
  },
  "cockpit": {
    "tickets": {
      "data_source_id": "<the tickets id>",
      "statuses": ["Backlog", "Ready for BR by AI", "..."],
      "properties": { "Name": "title", "Status": "status", "Epic": "relation" }
    },
    "epics": {
      "data_source_id": "<the epics id>",
      "items": [
        {
          "id": "<page-url>",
          "name": "<epic-name>",
          "status": "<status>",
          "project": "<project-name>"
        }
      ]
    },
    "projects": {
      "data_source_id": "<the projects id>",
      "items": [{ "id": "<page-url>", "name": "<project-name>" }]
    },
    "reference_tickets": {
      "data_source_id": "<the reference-tickets id>",
      "items": [
        {
          "id": "<page-url>",
          "name": "<ticket-name>",
          "points": 3,
          "domain": "Tech"
        }
      ]
    }
  },
  "project_boards": {
    "collection://<data-source-id>": {
      "name": "<board-name>",
      "statuses": ["Status A", "Status B"]
    }
  },
  "updated_at": "<ISO-8601-timestamp>"
}
```

### 5. Confirm

Report what was cached:

- Number of statuses, epics, projects, and reference tickets
- Number of project boards refreshed (if any)
- Cache file path and timestamp
