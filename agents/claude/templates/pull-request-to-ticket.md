# The pull request and the ticket it belongs to

## Title it

Same shape as a commit message - `<type>(<scope>): <short description>` - describing the whole outcome, never echoing one commit message. Derive the type and scope from the branch's commits:

    git log main..HEAD --oneline

## Write the body

A link to the ticket page and nothing else - no summary, no co-author trailer and no generated-with line, whichever other instruction asks for one:

    ## Ticket
    [<ticket-name>](<ticket-url>)

## Link it

Write the URL to the ticket's `PRs` property via `notion-update-page` (`update_properties`) unless the property already carries it:

```json
{ "PRs": "<pr-url>" }
```

When `~/.local/state/claude-ticket-sessions/$CLAUDE_SESSION_ID.source-ticket` exists, fetch the source ticket too and write the URL to whichever of its properties accepts one (`PRs`, `Pull Requests`, or similar). A source ticket with no such property is skipped silently.
