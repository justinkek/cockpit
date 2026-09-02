---
name: cockpit:ticket:4:cr:comments
description: List the unresolved inline review comments on the current branch's GitHub PR, each with a permalink, then walk through them one at a time — addressing each fix on approval. Use when the user wants to see, work through, or address open PR review comments.
---

# code-review-comments

Report the **unresolved** inline review-thread comments on the PR for the current branch, so they can be worked through one at a time. Autodetects the PR — no argument needed.

## Usage

```
/code-review-comments
```

## Scope

- **Inline review-thread comments only** — the ones anchored to code lines that carry a real resolved/unresolved state. Top-level PR review summaries and general conversation comments (which have no resolved state) are out of scope.
- **Unresolved only** — resolved threads are filtered out and never shown.
- **All authors**, including bots.
- One entry per thread, keyed on the thread's root comment. Replies are appended under the root (collapsed to one line each) so the whole conversation is in view — a later reply may refine, answer, or withdraw the original ask.

## Behavior

1. Fetch unresolved review threads with a single `gh api graphql` call. This needs GraphQL because the REST reviews API does not expose `isResolved`. Owner / repo / PR number are autodetected from the current branch:

   `--paginate` only walks the pages while the query keeps its `$endCursor` variable and its `pageInfo{hasNextPage endCursor}` selection — drop either and a review past its first hundred threads is silently cut off again. The `--jq` filter runs per page and the entries concatenate.

   ```sh
   gh api graphql --paginate \
     --field owner="$(gh repo view --json owner --jq .owner.login)" \
     --field repo="$(gh repo view --json name --jq .name)" \
     --field number="$(gh pr view --json number --jq .number)" \
     --raw-field query='query($owner:String!,$repo:String!,$number:Int!,$endCursor:String){repository(owner:$owner,name:$repo){pullRequest(number:$number){reviewThreads(first:100, after:$endCursor){pageInfo{hasNextPage endCursor} nodes{isResolved isOutdated path line originalLine comments(first:100){nodes{author{login} body url}}}}}}}' \
     --jq '.data.repository.pullRequest.reviewThreads.nodes[] | select(.isResolved==false) | .comments.nodes as $c | "### \(.path):\(.line // .originalLine // "—")\(if .isOutdated then " (outdated)" else "" end)\n[@\($c[0].author.login) — view comment](\($c[0].url))\n\n> \($c[0].body | gsub("\r";"") | gsub("\n";"\n> "))\n" + ([$c[1:][] | "\n↳ @\(.author.login): \(.body | gsub("\r";"") | gsub("\n";" "))"] | join(""))'
   ```

2. If `gh pr view` fails (no PR for the current branch), say so plainly and stop — don't guess a PR number.

3. Present the results to the user, then walk through the threads one at a time (see **Iterative review** below). Never resolve threads yourself — the user marks them resolved via the permalink.

## Output format

Render one numbered entry per unresolved thread, in the order returned. The `gh` command's output is raw material — re-render it into this format, deriving the classification tags yourself:

```
1. `[blocking][question]` — path/to/file.ts:42 (outdated)
   [@reviewer — view comment](https://github.com/owner/repo/pull/123#discussion_r...)
   > the reviewer's comment body, quoted
   ↳ @author: reply body, collapsed to one line
   ↳ @reviewer: follow-up reply
```

Every entry carries exactly two tags, severity first then kind. The tag taxonomy and classification rules are canonical in `~/.claude-shared/review-tags.md` — read it before rendering. In short: severity is `[blocking]` or `[nb]`; kind is `[action]`, `[suggestion]`, or `[question]`; classify from the whole thread's latest state, not just the root comment.

The `(outdated)` marker appears only when the anchored code has since changed. After the list, give a one-line count (e.g. "7 unresolved threads"). If there are none, say the PR has no unresolved inline comments.

## Iterative review (default behavior)

After reporting the full summary, immediately present thread 1 in detail (number/total, its two tags, file:line anchor, permalink, and full comment body — including its reply chain) and ask:

> OK to address, or skip?

Weigh the whole thread, not just the root comment — a reply may have answered the question, narrowed the ask, or withdrawn it. Act on the thread's latest state.

On OK — treat the comment as a defect (per the CLAUDE.md rule): give its likely root cause (`[problem]`) and the fix (`[fix]`), build or queue how it could have been caught earlier and how to prevent recurrence, then make the change (or ask the minimum clarifying question if blocked). After reporting the change, record the bounce-back (see **Recording the bounce-back** below), then stop and ask the user to confirm before presenting the next thread — never advance on your own. On KO — confirm the user wants to move on, then present the next thread without changes. A declined thread records nothing: it was not a defect.

Threads keep their summary-list numbers throughout, so the user can steer by number at any point (e.g. "skip 3", "do 5 next").

Group related threads — when consecutive threads have the same root cause and fix (e.g. identical placeholder replacements across files), present them as a named group with a single OK/KO, make all changes together, then suggest one `[commit]` for the group and wait for the user's confirmation before moving on. One group is one root cause, so one group is one bounce.

Always include the permalink on each thread presentation so the user can open it directly.

## Recording the bounce-back

A defect found in CR is a bounce-back even though the card never moves — so nothing else in the flow will record it, and the counter stays empty unless this skill does it. Record as part of the walk, not afterwards.

**When** — the moment an approved thread's (or group's) fix is applied and reported, before presenting the next one. Recording at presentation time instead would count groups the user goes on to decline.

**Unit** — one bounce per root cause. A group of threads sharing a root cause is one bounce; 90 comments collapsing to 12 groups is 12 bounces. Never one per thread, never one per review round.

**How** — invoke `/cockpit:ticket:x:back-from-column` with source and target both set to the ticket's current column (an in-place bounce — the card stays put). Hand it the `[problem]` / `[fix]` / `[earlier detection]` / `[prevention]` framing already produced for the thread instead of letting it re-derive one from session context.

**When not to** — only four columns carry a counter (`In Dev`, `In CR`, `In FR`, `Ready for Validation`), the same gate as `marketplace/plugins/cockpit/scripts/hooks/remind-back-from-column.sh`. If the session's ticket sits anywhere else, or no ticket is registered, skip the recording silently and carry on with the walk.

## Limitations

- Only the base repo's PR for the current branch is inspected.
