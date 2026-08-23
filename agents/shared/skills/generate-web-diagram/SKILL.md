---
name: generate-web-diagram
description: Draw one standalone HTML diagram into .artifacts/ and report its path. Use when a flow, an architecture, a comparison or a learning is being explained and a picture carries it better than prose - the fd, td, problem-solving and share-learning skills all call it, and a ticket's Details section is drawn with it.
---

# generate-web-diagram

One HTML file, one diagram, one path reported back. The caller uploads that file or screenshots it; this skill neither uploads nor opens anything.

## Where it goes

`.artifacts/<descriptive-name>.html` in the repo root. On first use in a repo:

    mkdir -p .artifacts
    echo '.artifacts/' >> .gitignore

Report the path as the last thing you say. A caller that attaches the file to a Notion page reads it off that line.

## Picking the form

| The subject                      | The form                                     |
| -------------------------------- | -------------------------------------------- |
| a process with steps and choices | a flowchart, lanes when actors differ        |
| how parts of a system connect    | boxes and labelled arrows                    |
| two or more options weighed      | a table, one row per option                  |
| something that happened in order | a timeline on one axis                       |
| a single idea to be shared       | one large statement with a supporting figure |

Pick the one that fits; never draw a second form beside it.

## Building the file

- **One file, no build step.** Styles inline in a `<style>` block. A flowchart may load Mermaid from a CDN; anything else is hand-written HTML and CSS, or an inline `<svg>`.
- **It will be read as an image.** Assume the reader sees a screenshot at a glance: body text no smaller than 16px, headings well above it, and enough contrast to survive a Slack preview.
- **Fixed width, so the screenshot is predictable.** 1280px for a diagram a reviewer scrolls; 1600x900 for one going to Slack.
- **Every label says what the thing is.** A box reading "Service A" tells the reader nothing they could challenge.
- **No animation, no interactivity.** Neither survives a screenshot.

## Before reporting the path

1. Open the file and confirm it holds the diagram, not an error.
2. Check every arrow starts and ends on a box that exists.
3. Check the widest element fits the fixed width without clipping.
