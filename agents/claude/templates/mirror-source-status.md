# Mirroring the source card's status

Cross-board work has two cards for one piece of work: the source ticket on the project board, and the cockpit stub. **The source ticket owns status.** A change is written there first, and the cockpit is then walked to the column that mirrors it.

The cockpit measures the work; it does not direct it. Read the two the other way round and the agent pushes a stale cockpit column onto a project board card a person has already moved on - which is how a card that had moved forward got reported as moved backwards.

Read this before writing either card's `Status`.

## The cockpit column a source status mirrors

Match by keyword, and take the **first** row that matches, top to bottom: the by-AI rows sit above their human twin because `Ready for TR` would otherwise swallow `Ready for TR by AI`.

| Source board status pattern                   | Cockpit column          |
| --------------------------------------------- | ----------------------- |
| `Backlog`                                     | `Backlog` (no catch-up) |
| `Ready for BR by AI`, `In BR by AI`           | `In BR by AI`           |
| `Ready for BR`, `In BR`                       | `In BR by AI`           |
| `Ready for TR by AI`                          | `Ready for TR by AI`    |
| `In TR by AI`                                 | `In TR by AI`           |
| `Ready for TR`, `In TR`                       | `Ready for TR by AI`    |
| `Ready for Sprint`, `Sprint Backlog`, `Daily` | `In Dev`                |
| `In Dev`, `In Progress`                       | `In Dev`                |
| `Ready for CR`, `In CR`, `In Review`          | `In CR by AI`           |
| `Ready for FR`, `In FR`                       | `Ready for CR`          |
| `Ready for Validation`                        | `Ready for Validation`  |
| `Done`                                        | `Done`                  |

A source status no row matches leaves the cockpit card where it is. Say so rather than guessing a column.

## The source status a cockpit column mirrors

The source board names its own columns, so this direction matches semantically against that board's `Status` options rather than against a fixed list. Read the options from `"$HOME/.cockpit/scripts/cockpit-cache-query" project-boards`, keyed by the board's `collection://` url, and fetch the data source schema only when the cache has no entry.

| Cockpit column          | Source status it mirrors                             |
| ----------------------- | ---------------------------------------------------- |
| `In Dev`                | `In Progress` / `In Dev`                             |
| `In CR by AI`           | none - the machine gates are the cockpit's own stage |
| `Ready for CR`, `In CR` | `In Review` / `Ready for CR`                         |
| `Ready for Validation`  | `Ready for Validation` / `QA`                        |
| `Done`                  | `Done`                                               |

When several cockpit columns mirror one source status, only the first transition into that group writes it. A source board with no `Status` property is not written to at all.

## The cockpit walks, it never jumps

The board stamps a column's `Date:` field on first arrival only, and a skipped column cannot be repaired afterwards. So mirroring steps every column between where the cockpit card sits and where the source card put it, through the `cockpit:ticket:x:status` skill - never a direct write to the landing column.

## A backward move on the source board is not mirrored

Walking the cockpit backwards would re-enter columns whose dates are already stamped, and the stamps would keep the first arrival while the card claimed a second. So a source card moved to an earlier column is reported and nothing else: the cockpit card stays where it is, and the session says which card moved and where to.

Anything more than reporting it - a bounce-back record, a reconciliation of the two - is not defined here.
