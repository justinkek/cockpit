# Readability

Read the diff as someone meeting this code for the first time. Report what makes them stop and work out something the code could have said.

## What to look for

- **A name that does not state its value** - `d`, `tmp`, `data2`, or a boolean named for the branch it takes rather than the condition it holds.
- **A function that does not read top to bottom** - the main path buried under guards written after it, or a return value assembled in three places.
- **Nesting past two levels.** An early return, a guard clause or a lookup table usually flattens it.
- **A comment standing in for a name.** The comment is the finding; the name below it is what changes.
- **A positioning value whose name omits its reference frame** - a number assigned to `top`, `left`, `bottom` or `right` is measured from somewhere, and the name has to say where. `inset` counts inward from the container's own edges, `offset` from a named ancestor or a scroll origin, `rect`, `bounds` and `frame` carry all four edges at once, and `origin` and `position` carry a point. A single computed number spells out four parts and infers none - subject, frame, the word `Offset`, edge - as in `focusedRowViewportOffsetTop`. A name with no frame reads alike whether the number is measured from the viewport or from the whole scrollable content, and those two differ by however far it is scrolled.
- **Two branches that do the same thing**, and a condition whose negation reads more plainly than itself.
- **A test in an `if` that states a domain fact the operator cannot.** `if [ ! -f "$boards" ]` says a file is absent; `if no_boards_recorded_yet` says what the absence means, and the operator moves into the one-line function behind the name. Only where the condition carries a rule - a bare `file_exists() { [ -f "$1" ]; }` renames the operator and teaches the reader nothing, and an idiom that already reads plainly stays inline.
- **A shape the reader has to hold in their head** - a tuple of four, a positional argument list past three, a flag argument that splits the body in two.

## What is not a finding here

Correctness, performance and duplication belong to the pass that ran before this one.

A rewrite that changes behaviour is out of scope. Every finding is answerable by renaming, splitting, flattening or deleting.

Anything a formatter already settles.

## Reporting

One finding per line, each opening with the `path/to/file.ext:123` it is about. A finding with no single line to point at names the file instead.
