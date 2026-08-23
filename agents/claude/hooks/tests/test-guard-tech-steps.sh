#!/usr/bin/env bash

HOOKS_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CLAUDE_DIR="$(cd "$HOOKS_DIR/.." && pwd)"
REPO_DIR="$(cd "$CLAUDE_DIR/../.." && pwd)"
GUARD="$HOOKS_DIR/guard-tech-steps.sh"
TR="$CLAUDE_DIR/skills/cockpit:ticket:2:tr/SKILL.md"
CONVENTIONS="$REPO_DIR/CLAUDE.md"

pass=0
fail=0

verdict() {
  jq --null-input --arg content "$1" \
    '{tool_input:{command:"insert_content",content:$content}}' |
    bash "$GUARD"
}

assert_refuses() {
  local label="$1" content="$2"
  if verdict "$content" | grep --quiet --fixed-strings '"deny"'; then
    printf "  OK  %s\n" "$label"
    pass=$((pass + 1))
  else
    printf "  KO  %s — the guard let it through\n" "$label"
    fail=$((fail + 1))
  fi
}

assert_allows() {
  local label="$1" content="$2"
  if verdict "$content" | grep --quiet --fixed-strings '"deny"'; then
    printf "  KO  %s — the guard refused it\n" "$label"
    fail=$((fail + 1))
  else
    printf "  OK  %s\n" "$label"
    pass=$((pass + 1))
  fi
}

squash() {
  awk '{ $1 = $1; printf "%s ", $0 }' "$1"
}

assert_names() {
  local label="$1" file="$2" needle="$3"
  if squash "$file" | grep --quiet --fixed-strings "$needle"; then
    printf "  OK  %s\n" "$label"
    pass=$((pass + 1))
  else
    printf "  KO  %s — no '%s' in %s\n" "$label" "$needle" "$file"
    fail=$((fail + 1))
  fi
}

HEADING_120='========================================= add a visualisation of the tech steps ========================================'

TREE_ALIGNED="$HEADING_120
  dotfiles/
! ├── CLAUDE.md                                add a section for the drawings that open the tech steps
  └── agents/claude/
      └── hooks/tests/
+         └── test-tech-step-drawings.sh       add tests for the markers and the shading"

TREE_NESTED="$HEADING_120
  dotfiles/
! ├── CLAUDE.md                                add a section for the drawings that open the tech steps
  └── agents/claude/
      ├── skills/
!     │   └── cockpit:ticket:2:tr/SKILL.md     add instructions for a file tree then a sequence flow
      └── hooks/tests/
+         └── test-tech-step-drawings.sh       add tests for the markers and the shading"

TREE_RAGGED="$HEADING_120
  dotfiles/
! ├── CLAUDE.md                                add a section for the drawings that open the tech steps
+ ├── AGENTS.md                                  add the same section one column further out"

TREE_DUPLICATE="$HEADING_120
  dotfiles/
! ├── CLAUDE.md                                add a section for the drawings that open the tech steps
! ├── CLAUDE.md                                add a second section under the same path"

TREE_UNJOINED="$HEADING_120
  dotfiles/
    agents/claude/hooks/
!     guard-tech-steps.sh                       refuse a file line joined to no folder above it"

FLOW_COMPLETE='```mermaid
sequenceDiagram
    title add a guard holding a tech steps write to what the skill says
    autonumber
    participant TR as cockpit:ticket:2:tr
    rect rgb(220, 245, 220)
    TR->>Page: writes the tech steps to
    end
```'

FLOW_UNTITLED='<summary>Agent Layer **(5 points)**</summary>
```mermaid
sequenceDiagram
    autonumber
    participant TR as cockpit:ticket:2:tr
```'

FLOW_UNNUMBERED='<summary>Agent Layer **(5 points)**</summary>
```mermaid
sequenceDiagram
    title add a guard holding a tech steps write to what the skill says
    participant TR as cockpit:ticket:2:tr
```'

FLOW_STRANGE_SHADE='<summary>Agent Layer **(5 points)**</summary>
```mermaid
sequenceDiagram
    title add a guard holding a tech steps write to what the skill says
    autonumber
    rect rgb(255, 245, 215)
    TR->>Page: writes the tech steps to
    end
```'

LAYER='<summary>Agent Layer **(5 points)**</summary>'

printf "Test group: the verb a tech step summary opens on\n"

for verb in add replace remove rename move; do
  assert_allows "$verb opens a summary" "$LAYER
<summary>$verb the thing it acts on</summary>"
done

assert_refuses "a verb outside those five" "$LAYER
<summary>keep the key for the life of the app process</summary>"
assert_refuses "a summary carrying a reason clause" "$LAYER
<summary>add the guard so the summaries stay readable</summary>"

printf "\nTest group: the summaries the guard leaves alone\n"

assert_allows "an In path summary" "$LAYER
<summary>In agents/claude/hooks/guard-tech-steps.sh - new</summary>"
assert_allows "a concern summary" "$LAYER
<summary>[skills]</summary>"
assert_allows "a layer summary carrying its points" "$LAYER"
assert_allows "a write with no tech steps in it" \
  'Some prose that names no summary, tree or flow.'
assert_allows "a Details toggle in a write carrying no tech steps" \
  '<summary>Preventions</summary>
<summary>Complexity Breakdown: 5 = Agent 5</summary>'

CONTEXT_HEADING='## Context'

printf "\nTest group: the heading a summary sits under\n"

assert_allows "a toggle under a heading that is not the tech steps" \
  "## Tech Steps
$LAYER
<summary>add the thing it acts on</summary>
## Context
<summary>Handoff from Every test in the repo runs from one local command</summary>
## Details
<summary>Complexity Breakdown: 5 = Agent 5</summary>
<summary>Back from TR #1</summary>"
assert_refuses "a summary under the tech steps heading, with no tree beside it" \
  '## Tech Steps
<summary>keep the key for the life of the app process</summary>'
assert_refuses "a heading inside a code block, which switches no section off" \
  "## Tech Steps
$LAYER
\`\`\`diff
$CONTEXT_HEADING
\`\`\`
<summary>keep the key for the life of the app process</summary>"

printf "\nTest group: the tree\n"

assert_allows "a tree whose sentences share a column" "$TREE_ALIGNED"
assert_allows "a nested tree, whose lines carry different numbers of glyphs" "$TREE_NESTED"
assert_refuses "a tree line opening on no marker" \
  "$HEADING_120
dotfiles/"
assert_refuses "a heading shorter than 120 characters" \
  '==== add a visualisation of the tech steps ===='
assert_allows "a 120 character heading whose label is not all ASCII" \
  '========================================== add a visualisation of a café ==============================================='
assert_refuses "a sentence out of column" "$TREE_RAGGED"
assert_refuses "a path its tree already carries" "$TREE_DUPLICATE"
assert_refuses "a file line joined to no folder above it" "$TREE_UNJOINED"

printf "\nTest group: the sequence flow\n"

assert_allows "a flow with a title, autonumber and an allowed shade" "$FLOW_COMPLETE"
assert_refuses "a flow carrying no title" "$FLOW_UNTITLED"
assert_refuses "a flow carrying no autonumber" "$FLOW_UNNUMBERED"
assert_refuses "a shading colour outside the two" "$FLOW_STRANGE_SHADE"
assert_allows "a mermaid block on a page carrying no tech steps" '```mermaid
graph TD
  A[a diagram someone drew somewhere else] --> B[no title, no autonumber]
```'

printf "\nTest group: the guard states none of the rules itself\n"

assert_names "the tr skill lists the verbs" \
  "$TR" '`add`, `replace`, `remove`, `rename`, `move`'
assert_names "the guard points a refusal back at that skill" \
  "$GUARD" 'cockpit:ticket:2:tr skill states'

printf "\n%d passed, %d failed\n" "$pass" "$fail"
[ "$fail" -eq 0 ]
