---
name: general:problem-solving
description: Guide a structured Daily Problem Solving (DPS) to turn a quality or delivery problem into a missing knowledge point and concrete countermeasures. Use when the user describes a problem they want to analyse.
argument-hint: "[problem description]"
---

# Problem Solving

Guide the user through a structured Daily Problem Solving (DPS) following the Daily Problem Solving standard. The goal is to use small everyday problems to strengthen team knowledge on the conditions that enable better quality and faster delivery.

## Workflow

### 1. Extract the problem

If a problem description was provided as an argument, use it as the starting point. Otherwise ask: "What problem did you encounter? Describe what happened on a specific piece of work."

**Validate** the problem statement against the three control points:

1. **Local and specific** - tied to a concrete piece of work, not a vague general concern.
2. **Gap from an ideal situation** - expressed as "X happened, but ideally Y" (not as the lack of a solution).
3. **Impact on quality or delivery** - the problem caused a delay, a defect, or a risk to the client.

If any control point fails, name which one and coach the user to rephrase:

- Too vague → "Which specific piece of work was affected?"
- Too big → "Can you narrow this to one concrete task or moment?"
- Phrased as a missing solution → "That describes what you wish you had, not what went wrong. What was the gap between what happened and the ideal?"
- No clear impact → "What was the consequence for quality or delivery?"

Do not proceed until all three control points pass.

### 2. Probable cause

Ask: "Why did this happen? What is the probable cause?"

Run 5 Whys down to a **missing knowledge point** - someone who needed to know something and didn't. Sort the candidates with an Ishikawa diagram cut to four bones: Man, Material, Method, Machine.

The steering question is: **"Who needs to learn what for this kind of issue to not happen again?"**

Reject any cause matching a row of Cause anti-patterns below, and ask that row's question instead.

When the cause points to a specific person's knowledge gap, prompt: **"Can you go and talk to them to confirm this is what happened?"** The cause should be confirmed on the gemba (where the work happens), not assumed from a distance.

Do not proceed until the cause identifies a concrete missing knowledge point.

### 3. Countermeasures

Ask for two things:

1. **Short-term action** - a concrete action to protect the client right now. Must have an **owner** (who will do it) and a **date** (by when).
2. **Prevention idea** - an action or change to prevent recurrence. This can be an idea to explore or a concrete step.

**Reject** countermeasures that:

- Are phrased as "make sure that..." or "ensure that..." - not actionable. Ask: "What specific action will be taken, by whom, and by when?"
- Name "the team" or use passive voice instead of a specific person. Ask: "Who exactly will do this? Give me a name."

### 4. Result

Ask: "What was the result of the short-term action? Did it work?"

Prompt the user to record:

- The direct consequences of the short-term action.
- Any unintended side effects (the fix may have created new problems elsewhere).

If the short-term action hasn't been executed yet, note it as pending and move to the summary.

### 5. Summary

**Consolidation pass** - before outputting, scan all countermeasures and proposals. If two share the same owner and overlapping action (e.g. "spec cross-reference" and "reference codebase check" are both "check the spec"), keep both and name the overlap in the output, so the reader can merge them. When the session has a registered ticket, raise it there too, following `~/.claude-shared/templates/raise-a-decision.md`. Merging two proposals loses one of them; keeping both loses nothing.

Output the completed DPS in this format:

```
**Problem:** [the validated problem statement]
**Cause:** [the missing knowledge point]
**Countermeasures:**
- Short-term: [action] — owner: [who], by: [date]
- Prevention: [action or idea]
**Result:** [outcome or "pending"]
```

## Common errors reference

### Problem anti-patterns

| Anti-pattern                          | Example                      | Why it's KO                                |
| ------------------------------------- | ---------------------------- | ------------------------------------------ |
| Too big or vague                      | "The team is late"           | Too many causes, never gets solved         |
| Missing solution disguised as problem | "We don't have a tool for X" | Skips root cause, risks adding bureaucracy |
| Linked to a lagging indicator         | "Sprint velocity dropped"    | Reacting too late, which specific piece?   |

### Cause anti-patterns

| Anti-pattern                  | Example                       | Why it's KO                                        | What to ask instead                                                                                                             |
| ----------------------------- | ----------------------------- | -------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------- |
| Uncontrollable external blame | "The client changed the spec" | Team learns nothing, feels helpless                | What could the team have done differently despite it?                                                                           |
| Stopping at inattention       | "It was a careless mistake"   | Tolerates non-quality, misses the real gap         | What conditions led to the mistake - a missing checklist, unfamiliarity with the domain, a repetitive task needing a poka-yoke? |
| Adding process as a fix       | "We need a QA review step"    | Correction layers don't scale, solve at source     | Which missing knowledge would remove the need for the layer?                                                                    |
| Naming a symptom, not a cause | "There was a bug in the code" | A bug is a symptom - what knowledge gap caused it? | What knowledge was missing when the bug went in?                                                                                |

### Countermeasure anti-patterns

| Anti-pattern     | Example                      | Why it's KO                       |
| ---------------- | ---------------------------- | --------------------------------- |
| Vague directive  | "Make sure we test better"   | No owner, no date, no one does it |
| No owner or date | "We should improve the docs" | Falls through the cracks          |

## Client-facing output rules

All DPS output (summary, generate-web-diagram rendering, and any shared artifact) must be client-ready without manual rewriting. Apply these rules throughout:

### Named owners

Every countermeasure, proposal, and action must name a specific person - never "the team", never passive voice. If the owner is not obvious from context, ask: "Who owns this action? Give me a name."

### Simple sentences

Root cause titles and proposal titles must be plain direct statements, not abstract category labels. Write as if explaining to someone outside the team.

| KO (abstract)                         | OK (direct)                                                    |
| ------------------------------------- | -------------------------------------------------------------- |
| "Refinement gap on critical flow"     | "We challenged the auth flow too late in refinement"           |
| "Knowledge transfer deficiency"       | "James didn't know the payments API requires idempotency keys" |
| "Insufficient specification coverage" | "The spec didn't cover the error states for card decline"      |

### Consolidate related proposals

Before outputting, check for proposals that share the same owner and overlapping action. If found, keep both cards and name the overlap in the output, following the consolidation pass above. Fewer cards with more substance beats more cards with thin content, and which two collapse into one is the reader's call.

### Active voice

Use active voice throughout. Every sentence should name who did or will do the thing.

| KO (passive)                               | OK (active)                                        |
| ------------------------------------------ | -------------------------------------------------- |
| "This wasn't challenged during refinement" | "We did not get Bastien to challenge our plan"     |
| "The tech steps should be reviewed"        | "James will review the tech steps by Friday"       |
| "Testing was insufficient"                 | "We did not test the decline flow before shipping" |

### Client-facing tone

Use collaborative "we" throughout. No blame, no internal jargon. Be specific about what happened and who is doing what next - vague reassurance is worse than honest specifics.
