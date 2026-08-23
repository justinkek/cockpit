# Review tag taxonomy

Canonical classification for code-review comments and findings. Every comment/finding carries **exactly two tags, severity first then kind**, written as inline code (e.g. `[blocking][question]`).

This file is the single source of truth. Consumers:

- `skills/code-review-comments/SKILL.md` — tags unresolved PR threads.
- `templates/REVIEW.md` — embeds a copy for repo-level `/code-review` customization (regenerate that copy when this file changes).

## Severity — exactly one

- `[blocking]` — must be addressed before merge.
- `[nb]` — non-blocking; merge may proceed with it open.

## Kind — exactly one

- `[action]` — asks for a concrete change.
- `[suggestion]` — offers an optional improvement.
- `[question]` — needs an answer.

## Classification rules

1. Classify from the whole thread, not just the root comment — a reply may have downgraded the severity, answered the question, or withdrawn the ask.
2. When the author states a severity explicitly (e.g. "nit:", "non-blocking", "must fix"), honor it; otherwise infer from content.
3. A question whose answer would force a code change before merge is `[blocking][question]`; a curiosity is `[nb][question]`.
