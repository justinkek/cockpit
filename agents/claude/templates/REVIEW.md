<!--
  REVIEW.md — customizes Claude Code's built-in /code-review for this repo.
  Drop at the repo root. Docs: https://code.claude.com/docs/en/code-review.md
  Tag taxonomy embedded from ~/.claude-shared/review-tags.md (canonical copy —
  regenerate this section when that file changes).
-->

# Review instructions

## Finding format

Report findings as a **numbered list**. Prefix every finding with exactly two tags, severity first then kind, written as inline code — e.g. `[blocking][action]`, `[nb][suggestion]`.

### Severity — exactly one

- `[blocking]` — must be addressed before merge.
- `[nb]` — non-blocking; merge may proceed with it open.

### Kind — exactly one

- `[action]` — asks for a concrete change.
- `[suggestion]` — offers an optional improvement.
- `[question]` — needs an answer.

### Classification rules

1. When severity is explicit in context (e.g. "nit", "must fix"), honor it; otherwise infer from impact.
2. A question whose answer would force a code change before merge is `[blocking][question]`; a curiosity is `[nb][question]`.

## Severity mapping

Map the built-in severity levels onto the taxonomy: critical/major findings are `[blocking]`; minor/nit findings are `[nb]`.

## Output shape

1. Order findings most severe first (`[blocking]` before `[nb]`).
2. Anchor each finding to `path/to/file.ts:line`.
3. End with a one-line count per severity (e.g. "2 blocking, 5 nb").
