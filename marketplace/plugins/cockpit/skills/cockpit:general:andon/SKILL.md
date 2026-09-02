---
name: cockpit:general:andon
description: Write an andon message in the team's standard format, ready to paste into Slack.
---

# Andon

Write a message in the team's standard andon format and hand it to the user to paste into the channel themselves.

## Message format

```
[Andon][<short label for the andon, e.g. "CI pipeline", "deploy blocker">]
🔴 *Problem*
<what is actually blocking you, never the fix you got stuck on - asking about
an attempted fix is not stating the problem - with enough background for
someone who has none to follow it>
💥 *Impact*
<what breaks or is at risk if this is not resolved>
❓ *Question*
<the specific help needed, asking the reader to challenge the proposal rather
than only to help>
🔧 *What we tried*
<what has already been attempted, and the alternatives weighed against each
other>
```

## Workflow

### 1. Gather the five values

Take them from the skill arguments. Ask for any the arguments do not carry - one question per missing value, in the order the format lists them. All five are required.

### 2. Hand it over

Fill the format with the values verbatim - never rewritten, summarised or embellished - and print the result in a fenced code block. Which channel it goes in, and sending it, are the user's own steps.
