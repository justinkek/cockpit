# The pull request and the ticket it belongs to

## Title it

Same shape as a commit message - `<type>(<scope>): <short description>` - describing the whole outcome, never echoing one commit message. Derive the type and scope from the branch's commits:

    git log main..HEAD --oneline

## Write the body

A link to the ticket page and nothing else - no summary, no co-author trailer and no generated-with line, whichever other instruction asks for one. The page is the card's page on the local board app:

    ## Ticket
    [<card-id> <ticket-name>](http://localhost:4646/card/<card-id>)

## Link it

Write the URL to the card's `PRs` unless it already carries it - read them with `"$HOME/.cockpit/scripts/board-card" show <id> PRs`, and write every URL the card should carry, the new one added to the ones already there:

```
"$HOME/.cockpit/scripts/board-card" set <id> prs "<pr-urls>"
```
