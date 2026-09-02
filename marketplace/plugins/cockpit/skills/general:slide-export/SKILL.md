---
name: general:slide-export
description: Generate Gemini-compatible prompts for Google Slides from the current branch's work (commits, diffs, PR). Use when the user wants to create review slides from a branch.
argument-hint: "[slide-type]"
---

# Slide Export

Generate copy-pasteable Gemini prompts from the current branch's work. Each prompt edits one slide in an existing Google Slides presentation via Gemini in Slides.

## Key constraints (Gemini in Slides)

1. Gemini can only edit one slide at a time.
2. Every prompt must start with `Edit the current slide only.`
3. Gemini can only reference styles from the current slide and nearby slides - always point it at a reference slide for styling.
4. Keep prompts concise - Gemini works best with clear, structured instructions.

## Workflow

### 1. Gather branch data

Run these in parallel:

```sh
# Commits since divergence from main
git log --oneline main..HEAD

# Full diff summary
git diff --stat main..HEAD

# Full diff for content extraction
git diff main..HEAD

# PR description (if a PR exists)
gh pr view --json title,body,url 2>/dev/null
```

If the branch has no commits ahead of main, check for uncommitted changes. If nothing to export, tell the user.

### 2. Identify the slide type

If the user provided a type argument, use it. Otherwise infer from the branch work or ask. Supported types:

| Type         | Template                        | When to use                                |
| ------------ | ------------------------------- | ------------------------------------------ |
| `shift-left` | 3-card + prevention strategy    | Bug fixes, incidents, process improvements |
| `feature`    | Problem → Solution → Demo       | New features, enhancements                 |
| `learning`   | Context → Insight → Application | Learnings, discoveries, tech spikes        |

Default to `shift-left` when the work contains a bug fix or process change.

### 3. Generate prompts

Generate one prompt per slide. Write all prompts to a single fenced code block so the user can copy each one individually.

Separate each slide's prompt with a horizontal rule and a slide label comment.

#### shift-left template (3 cards + prevention)

**Slide 1 - Problem card:**

```
Edit the current slide only. Use the same styling as the current slide.

Replace the content with:
Title: [Short problem title]
Body:
- [What happened - one line]
- [Impact - one line]
- [How it was detected - one line]
```

**Slide 2 - Root cause card:**

```
Edit the current slide only. Use the same styling as the current slide.

Replace the content with:
Title: Root Cause
Body:
- [Why it happened - the actual root cause]
- [Contributing factors]
- [What made it hard to catch]
```

**Slide 3 - Fix card:**

```
Edit the current slide only. Use the same styling as the current slide.

Replace the content with:
Title: Fix Applied
Body:
- [What was changed - link to PR if available]
- [How it was verified]
- [Files changed: N files, +X/-Y lines]
```

**Slide 4 - Prevention strategy:**

```
Edit the current slide only. Use the same styling as the current slide.

Replace the content with:
Title: Prevention Strategy
Body:
- Earlier detection: [How to catch this class of bug sooner]
- Prevention: [How to stop it from recurring - lint rule, CI check, test, hook]
- Scope: [What other areas might have the same issue]
```

#### feature template

**Slide 1 - Problem:**

```
Edit the current slide only. Use the same styling as the current slide.

Replace the content with:
Title: [Feature name]
Body:
- Problem: [What user pain this solves]
- Context: [Why now]
```

**Slide 2 - Solution:**

```
Edit the current slide only. Use the same styling as the current slide.

Replace the content with:
Title: Solution
Body:
- [Approach taken - 2-3 bullets]
- [Key design decision and why]
- [Trade-offs accepted]
```

**Slide 3 - Demo / Evidence:**

```
Edit the current slide only. Use the same styling as the current slide.

Replace the content with:
Title: Result
Body:
- [What changed for the user]
- [Metrics or evidence if available]
- [PR: <url>]
```

#### learning template

**Slide 1 - Context:**

```
Edit the current slide only. Use the same styling as the current slide.

Replace the content with:
Title: [Learning title]
Body:
- Context: [What we were doing when we discovered this]
- Assumption: [What we assumed before]
```

**Slide 2 - Insight:**

```
Edit the current slide only. Use the same styling as the current slide.

Replace the content with:
Title: What We Learned
Body:
- [The key insight - 1-2 sentences]
- [Evidence / what proved it]
- [Why it matters]
```

**Slide 3 - Application:**

```
Edit the current slide only. Use the same styling as the current slide.

Replace the content with:
Title: Applying It
Body:
- [What we changed or will change as a result]
- [Where else this applies]
- [Open questions remaining]
```

### 4. Output

Print the prompts in a single output block. Before each prompt, print a label:

```
--- Slide 1: Problem ---
<prompt>

--- Slide 2: Root Cause ---
<prompt>

--- Slide 3: Fix ---
<prompt>

--- Slide 4: Prevention ---
<prompt>
```

After the prompts, print usage instructions:

> **How to use:** Navigate to each slide in Google Slides, open Gemini, and paste the corresponding prompt. Start from a slide that already has the styling you want - Gemini will match it.

### 5. Populate content from branch data

Fill every template placeholder with real data extracted from the branch:

- Titles: derive from commit messages or PR title.
- Problem/root cause: extract from commit messages, PR body, or diff context.
- Fix details: summarize from the diff (files changed, lines added/removed, key changes).
- Prevention: infer from the type of fix (e.g. added a test → "test coverage", added a lint rule → "static analysis").
- PR URL: from `gh pr view` if available.

Never leave a placeholder like `[What happened]` in the output - always fill with real content from the branch. If information is genuinely missing, write a concrete TODO (e.g. `TODO: add impact metrics from monitoring`).
