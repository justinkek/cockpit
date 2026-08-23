# Estimating a ticket

Read this before proposing Complexity on a ticket, and before deciding whether one has to be split.

## Complexity (delivery effort)

Complexity measures delivery effort on a Fibonacci scale (1, 2, 3, 5, 8, 13).

- **1 point** = the smallest unit of work that brings value to the user (e.g. a typo fix, a templated status email).
- **Daily speed** = 5 points (starting assumption - actual velocity will be measured).
- **Split threshold** = tickets with Complexity > 5 must be broken down before Ready for Sprint.
- **Timebox exclusion** = timebox tickets don't get Complexity points (they have explicit time bounds via Timebox (mins)).
- **Cross-domain** = one speed across all domains (Tech, Bizdev). Each domain has its own reference tickets for calibration; references converge iteratively during an initial calibration phase, then lock as stable anchors.
- **Reference database** = the board's `reference-tickets` id, read with `cockpit-board-id` (see `~/.claude-shared/templates/board-ids.md`). Agents must consult reference tickets when proposing Complexity.
- **Derived from layers** = a ticket's Complexity is the sum of its Tech Steps layer points, and reference tickets are consulted per-layer rather than per-ticket.

## Split at the exit gate

Split at any exit gate if Complexity exceeds 5 (daily speed). The `cockpit:ticket:x:split` skill owns how: the original stays as a validation-only parent (Complexity 0, no Tech Steps) and each part becomes a sub-ticket, linked by the `Dependent on` relation.
