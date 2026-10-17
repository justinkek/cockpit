# Machine gates on In CR by AI

Read this when the walk lands on `In CR by AI`. Landing on the column is the only thing that fires the review, so a walk that passes straight through never runs it, and a ticket that landed once never fires it twice. The ticket stays in the column until the PR is up: `/cockpit:ticket:4:ready-for-cr` is what carries it on to `Ready for CR`, not this step.

**Once per landing, whatever the review found.** A fix made in response to a finding is not a new landing, so it does not re-arm the review - re-running it on the fixes puts the gate in a loop that reviews its own output, and two passes over the same ticket have already contradicted each other on it. The fixes go to human CR unread by the machine; that is what the human gate is for.

**Name the level on every invocation.** Left off, the review reuses whatever level a person last typed in some other session, so the same ticket gets a different gate depending on who ran what beforehand. `low` is this gate's level: it is one diff pass over the hunks, and the human pull behind it is what reads the rest.

## The reviews this project runs

Every review reads the branch's own commits - the range the pull request `/cockpit:ticket:4:ready-for-cr` opens will carry. The ticket lands here with its work committed, so the working tree holds nothing to read. Find where the branch left the default branch, then read from there to HEAD, in two commands as dev step 5 runs them, because the worktree isolation gate refuses a command substitution:

```
git merge-base HEAD origin/<default-branch>
```

```
git diff <the commit it printed>..HEAD
```

Then list what that range holds before any review reads it:

```
git log --no-merges --oneline <the commit it printed>..HEAD
```

Every line it prints has to be this ticket's own work. Cut from the local HEAD, the branch also holds every commit that HEAD had beyond the remote, and each review below would read them as this ticket's diff. On a commit that is not this ticket's, name it and stop before the first review, as step 2.4 of `/cockpit:ticket:4:ready-for-cr` stops before the push. In an unattended session that stop follows the finding rule: flag the ticket Blocked, comment, stop.

Pass that same range to the shared review as its target: `/code-review low <the commit it printed>..HEAD`.

`/code-review low` runs on every project, and two more run after it on every project, in this order:

    ~/.agents-shared/code-reviews/readability.md
    ~/.agents-shared/code-reviews/divergence-from-tech-steps.md

A project neither lists those two nor leaves them out.

A project adds its own under `## Extra reviews` in its `./AGENTS.md`, one path per `- ` item, each naming a file that says what that review looks for:

    ## Extra reviews
    - agents/code-reviews/screen-reader-labels.md
    - ~/.agents-shared/code-reviews/permissions.md

A review the project owns sits in its own `agents/code-reviews/`. One shared across projects sits in `agents/shared/code-reviews/` in the dotfiles repo, which every checkout reaches through `~/.agents-shared/`. Neither path names an agent: the file is prose about what to look for in a diff, and any agent can run a pass against it.

Each listed file is a separate review of the same diff. Run them one at a time after the two above, and fix what each finds on the branch before anything is pushed - one commit per finding, exactly as the shared review's findings are fixed.

An entry pointing at a file that is not there: say which, and run the rest.

A project with no `## Extra reviews` section gets the three above and nothing else.

## Where the findings land

- **`PRs` empty - the normal path.** The gates run before the branch is pushed, so on the first pass there is nothing to comment on. Invoke `/code-review low` on the range above and fix what it finds here, on the branch, before `/cockpit:ticket:4:ready-for-cr` publishes anything. In an unattended session a finding the session cannot fix follows the finding rule: flag the ticket Blocked, comment, stop.
- **`PRs` holds a URL - the ticket came back.** Run the same `/code-review low` on the range above, and leave `--comment` off. That flag posts only when the target is a pull request, and a pull request target reads what was pushed, which is missing the commits that brought the ticket back. Everything else is the normal path: fix what it finds here, then `/cockpit:ticket:4:ready-for-cr` pushes the fixes to that PR and its step 4.5 posts each unfixed line there.
- **Leave the evidence on the ticket.** Until `/cockpit:ticket:4:ready-for-cr` pushes, the findings have nowhere durable to land, and human CR reads them instead of re-executing the diff. Write a `### Machine gates` subsection into `## Details`, the way `~/.cockpit/skills/ticket:x:back-from-column/SKILL.md` says under "Writing under `## Details`", holding what the review found and what was fixed in response, one line each, and "Nothing found" when it came back clean. Open every line the session did not fix with `unfixed -`, name the review it came from, and keep the `path/to/file.ext:123` the review reported - that is what anchors it beside the line once the PR is up. On a ticket that came back, this replaces the subsection its first landing wrote, whose unfixed lines step 4.5 already put on the PR.
- **End on a clean tree.** A fix made here is a working-tree change, and `cockpit:ticket:4:ready-for-cr` blocks on any uncommitted change - so commit each one through `/cockpit:ticket:4:commit` as it is made, one commit per finding, before this step reports. Leaving them uncommitted hands the next skill a block the gate itself created.
- **An unfixed line holds the publish only when it is a defect.** A divergence from the tech steps is not one: `divergence-from-tech-steps.md` calls it a human amendment decision, and the person who makes it reads the diff beside it. So publish, and leave the posting to `/cockpit:ticket:4:ready-for-cr` step 4.5, which puts every unfixed line on the pull request as an inline comment anchored to the `path/to/file.ext:123` the review reported. A finding named in chat instead is a finding the reviewer has to go looking for.
