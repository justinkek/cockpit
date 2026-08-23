---
name: cockpit:general:share-learning
description: Turn a learning into a visual diagram and a caption ready to post to Slack. Use when the user wants to post a takeaway to Slack with a generated visual.
argument-hint: "[learning description]"
---

# Share Learning

Generate a visual diagram illustrating a learning or takeaway, and a caption to go with it, for the user to post themselves.

## Workflow

### 1. Extract the learning

If the user provided a learning description as an argument, use it. Otherwise ask: "What did you learn? One sentence is enough."

Look at the session context for clues - the learning often comes from whatever the user just worked on.

### 2. Generate the visual

Invoke the `generate-web-diagram` sub-skill with this prompt:

> Create a single-page visual diagram that explains this learning: "{learning description}"
>
> Make it clear, concise, and visually striking - this will be screenshotted and shared on Slack, so it needs to communicate the concept at a glance. Use a simple layout with large text and clear visual hierarchy. Aim for a 16:9 aspect ratio suitable for Slack preview.

The skill writes an HTML file to `.artifacts/` and reports its path. Note it.

### 3. Compose the caption

Write a single-line takeaway that captures the learning. Keep it under 100 characters. Open it with 💡 and format the rest as bold text.

### 4. Report

Tell the user:

1. The visual is open in their browser at `{path}`
2. The caption, in a fenced code block so it can be copied whole
3. To complete the post: screenshot the visual and paste both into the channel they want it in
