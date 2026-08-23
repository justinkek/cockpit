---
name: figma-to-component
description: >
  Convert a Figma component into a component in this project's UI framework, with two-stage validation: agent-driven static UI check, then human-driven UX check. Use when asked to implement a component from Figma, convert a design to code, or build a new UI component from the design file. Also use when another skill needs to produce a component from a Figma node.
---

Convert a Figma component section into a production component through two validation stages: the agent validates **static UI** (layout, colors, typography) by comparing screenshots of the running app against Figma exports, then hands off to the human for **UX validation** (scrolling, focus traversal, animation) that requires interaction with the device.

The split is the point. Static fidelity is checkable from a screenshot, so the agent owns it and iterates without asking. Interaction is not, so it goes to a human once - with a checklist - rather than in a guessing loop.

## Project inputs

This skill is project-agnostic. Read these from the project's `./AGENTS.md` before starting; if any is missing, ask rather than guess.

| Input                | What it is                                            |
| -------------------- | ----------------------------------------------------- |
| Figma file key       | the file the designs live in                          |
| Styles/Tokens node   | the canonical token page - never read tokens from     |
|                      | component instances                                   |
| Components node      | the page holding the component sets                   |
| Component inventory  | the doc listing sections, component sets and variants |
| Theme token location | where colors, spacing, radii, shadows, motion live    |
| Component location   | where components go, and the closest existing one     |
| Run recipe           | how to build, launch and screenshot the app (below)   |

### Run recipe

Static validation needs a screenshot of the component rendering in the real app. How to get one is per-project - a simulator, an emulator, a browser, a device. The project supplies the commands; this skill only requires that a screenshot lands somewhere readable, by convention `.artifacts/`.

If the project has a `run` skill or documented launch steps, use those. If nothing is documented, ask once and record the answer in the project's `AGENTS.md` so the next run does not ask again.

## Component shape

Follow the project's existing components rather than the shape below - this is the fallback when there is no precedent to copy:

```
<ComponentLocation>/<Name>/
  <Name>.<ext>          - the component
  <Name>.styles.<ext>   - colocated styles, importing theme tokens
```

Read one existing component closest in structure to the target before writing anything. Precedent beats this template every time.

## Steps

### 1. Load context

Read:

- the component inventory - the target's section, node ids, variants.
- the full theme token set.
- one existing component closest in structure to the target.
- the project's `AGENTS.md` - conventions and the project inputs above.

Completion: all four groups read.

### 2. Fetch design context from Figma

Call `get_design_context` on the component set node id. For components with many variants, also call on individual variant nodes.

Check for Figma comments using `get_metadata`. Behavioral comments (animation, scroll behavior, interaction) become `// Figma note:` comments in the component and feed into UX validation items (step 9).

Completion: design context and behavioral comments captured.

### 3. Extract and reconcile tokens

Map every Figma design value to an existing theme token. Flag missing tokens - add them to the theme, never inline.

Completion: every value mapped or new token added.

### 4. Generate the component

Create the component and its styles in the project's component location, following the shape of the existing component read in step 1. Run the project's typecheck.

Completion: files created, typecheck clean.

### 5. Download and convert assets

Skip if no icons or images. Otherwise export from Figma via `download_assets`, save and convert them through whatever asset pipeline the project documents, then import the results in the component.

Completion: all assets importable.

### 6. Add to the showcase screen

If the showcase screen does not exist, create it from [SHOWCASE.md](SHOWCASE.md). Add a section rendering every variant side by side, and make the showcase the initial route so the app opens directly to it.

Completion: app builds; showcase renders all variants.

### 7. Static UI validation (agent)

This stage validates visual fidelity - the agent compares screenshots against Figma, no human needed.

1. Export Figma reference images using `get_screenshot` on the component set and key variant nodes.
2. Build, launch and screenshot the app using the project's run recipe.
3. Compare against the Figma exports across: layout dimensions, colors, typography, border radius, shadows, focus or hover state changes.
4. Fix discrepancies and re-capture until the screenshot matches.

Completion: the agent has confirmed the screenshot matches Figma for all static variants; comparison saved to `.artifacts/`.

### 8. Clean up static validation

- Revert the initial-route override so the app starts normally.
- Run the project's typecheck and lint.

Completion: app compiles and lints clean on its normal initial route.

### 9. UX validation (human)

This stage validates interactive behavior the agent cannot self-check: scroll, focus traversal, animation timing, transitions. The agent implements the behavior, then asks the human to verify.

1. Collect UX items from the Figma behavioral comments (step 2) and from variants that imply interaction (overflow scroll variants, motion specs).
2. Implement each UX item using the project's own scrolling and animation primitives and its motion tokens.
3. Present a checklist to the human with `AskUserQuestion`:
   - One item per UX behavior to verify.
   - Each item describes what to do on the device and what the expected result is.
   - Example: "Focus the context menu and press Down past the last visible item. Expected: the menu scrolls smoothly to reveal more items."
4. Apply fixes based on human feedback. Re-ask until all items pass.

Completion: the human has confirmed all UX behaviors pass.
