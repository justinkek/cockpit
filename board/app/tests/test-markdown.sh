#!/usr/bin/env bash

repo_root_through_symlink() {
  cd "$(dirname "$0")" && cd "$(pwd -P)/../../.." && pwd
}

REPO="$(repo_root_through_symlink)"
BOARD="$REPO/board"

pass=0
fail=0

assert_ok() {
  printf "  OK  %s\n" "$1"
  pass=$((pass + 1))
}

assert_ko() {
  printf "  KO  %s — %s\n" "$1" "$2"
  fail=$((fail + 1))
}

finish() {
  printf "\n%d passed, %d failed\n" "$pass" "$fail"
  [ "$fail" -eq 0 ]
  exit
}

printf "Test group: the renderer loads outside the app\n"

if [ -d "$BOARD/node_modules/typescript" ] && [ -d "$BOARD/node_modules/react-dom" ]; then
  assert_ok "the board's packages are installed"
else
  assert_ko "the board's packages are installed" "run npm ci in $BOARD, or nothing below can be checked"
  finish
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
ln -s "$BOARD/node_modules" "$WORK/node_modules"

cat >"$WORK/compile.cjs" <<'EOF'
const fs = require("node:fs");
const [board, work] = process.argv.slice(2);
const ts = require(`${board}/node_modules/typescript`);
const rewrites = [
	[
		"app/markdown.tsx",
		"markdown.mjs",
		[
			['from "@/app/code-block"', 'from "./code-block.mjs"'],
			['from "@/lib/blocks"', 'from "./blocks.mjs"'],
		],
	],
	["lib/blocks.ts", "blocks.mjs", []],
	[
		"app/code-block.tsx",
		"code-block.mjs",
		[
			['from "@/app/mermaid"', 'from "./mermaid.mjs"'],
			['from "@/app/keys"', 'from "./keys.mjs"'],
		],
	],
];
for (const [file, out, swaps] of rewrites) {
	let source = fs.readFileSync(`${board}/${file}`, "utf8");
	for (const [from, to] of swaps) {
		if (!source.includes(from)) {
			process.stderr.write(`${file} no longer imports ${from.slice(6)}\n`);
			process.exit(1);
		}
		source = source.replace(from, to);
	}
	const { outputText } = ts.transpileModule(source, {
		compilerOptions: { jsx: ts.JsxEmit.ReactJSX, module: ts.ModuleKind.ESNext, target: ts.ScriptTarget.ES2022 },
	});
	fs.writeFileSync(`${work}/${out}`, outputText);
}
EOF

cat >"$WORK/mermaid.mjs" <<'EOF'
export function useMermaidSvg() {
	return { svg: null, failed: false };
}
EOF

cat >"$WORK/keys.mjs" <<'EOF'
export async function copyText() {
	return true;
}
EOF

cat >"$WORK/outline.mjs" <<'EOF'
import { readFileSync } from "node:fs";
import { createElement } from "react";
import { renderToStaticMarkup } from "react-dom/server";
import { Markdown } from "./markdown.mjs";

const html = renderToStaticMarkup(createElement(Markdown, { source: readFileSync(0, "utf8") }));
if (process.argv[2] === "--html") {
	process.stdout.write(html);
	process.exit(0);
}
const decoded = (text) =>
	text
		.replace(/&lt;/g, "<")
		.replace(/&gt;/g, ">")
		.replace(/&quot;/g, '"')
		.replace(/&#x27;/g, "'")
		.replace(/&amp;/g, "&");
const kinds = { "md-item": "item", "md-p": "p", "md-code": "code", "md-heading": "heading", "md-quote": "quote" };
const out = [];
let depth = 0;
let toggleMargin;
let open = null;
const pattern = /<(\/?)([a-z0-9]+)([^>]*)>|([^<]+)/g;
let match;
while ((match = pattern.exec(html)) !== null) {
	const [, closing, tag, attributes, text] = match;
	if (text !== undefined) {
		if (open) open.text += text;
		continue;
	}
	if (open) {
		if (tag === open.tag) open.nest += closing ? -1 : 1;
		if (open.nest === 0) {
			const body = decoded(open.text).replace(/^•/, "").replace(/\n/g, "\\n").trim();
			out.push(`${"  ".repeat(open.depth)}${open.kind}${open.margin ? `@${open.margin}` : ""}: ${body}`);
			open = null;
		}
		continue;
	}
	const margin = /margin-left:\s*(\d+)px/.exec(attributes)?.[1];
	if (tag === "details") {
		depth += closing ? -1 : 1;
		toggleMargin = margin;
		continue;
	}
	if (closing) continue;
	if (tag === "summary") {
		open = { tag, kind: "toggle", margin: toggleMargin, depth: depth - 1, text: "", nest: 1 };
		continue;
	}
	const kind = kinds[/class="([^"]+)"/.exec(attributes)?.[1]];
	if (kind) open = { tag, kind, margin, depth, text: "", nest: 1 };
}
process.stdout.write(`${out.join("\n")}\n`);
EOF

if node "$WORK/compile.cjs" "$BOARD" "$WORK" 2>"$WORK/compile.err" && printf 'x' | node "$WORK/outline.mjs" >/dev/null 2>"$WORK/render.err"; then
  assert_ok "markdown.tsx compiles and renders on its own"
else
  assert_ko "markdown.tsx compiles and renders on its own" "$(cat "$WORK/compile.err" "$WORK/render.err" 2>/dev/null | head -5)"
  finish
fi

outline_of() {
  printf '%s' "$1" | node "$WORK/outline.mjs"
}

assert_outline() {
  local label="$1" source="$2" expected="$3" actual
  actual="$(outline_of "$source")"
  if [ "$actual" = "$expected" ]; then
    assert_ok "$label"
  else
    assert_ko "$label" "$(printf 'expected:\n%s\ngot:\n%s' "$expected" "$actual")"
  fi
}

printf "\nTest group: a toggle the writer forgot to close hides nothing past its section\n"

assert_outline "an unclosed toggle ends at the next section heading" \
  $'## Tech Steps\n<details>\n<summary>Layer</summary>\n\t- step\n## Context\nBackground' \
  "$(
    cat <<'EOF'
heading: Tech Steps
toggle: Layer
  item: step
heading: Context
p: Background
EOF
  )"

assert_outline "and so does a nest missing only its outermost close" \
  $'## Tech Steps\n<details>\n<summary>Board Layer **(2 points)**</summary>\n\t<details>\n\t<summary>add a thing</summary>\n\t\t- In a.ts\n\t</details>\n\n## Context\nBackground\n## Details\nNotes' \
  "$(
    cat <<'EOF'
heading: Tech Steps
toggle: Board Layer (2 points)
  toggle: add a thing
    item: In a.ts
heading: Context
p: Background
heading: Details
p: Notes
EOF
  )"

assert_outline "a subheading inside a toggle stays inside it" \
  $'<details>\n<summary>S</summary>\n### Sub\n</details>' \
  "$(
    cat <<'EOF'
toggle: S
  heading: Sub
EOF
  )"

printf "\nTest group: a toggle closes where its closing tag sits\n"

assert_outline "a toggle written on one line holds its body and nothing after it" \
  $'<details><summary>Title</summary>body</details>\nafter' \
  "$(
    cat <<'EOF'
toggle: Title
  p: body
p: after
EOF
  )"

assert_outline "a closing tag at the end of a line closes the toggle after that line" \
  $'<details>\n<summary>S</summary>\n- last</details>\nafter' \
  "$(
    cat <<'EOF'
toggle: S
  item: last
p: after
EOF
  )"

assert_outline "a stray closing tag outside any toggle is dropped" \
  $'<details><summary>Context</summary>\n</details>\nprose\n</details>\nmore' \
  "$(
    cat <<'EOF'
toggle: Context
p: prose
p: more
EOF
  )"

printf "\nTest group: a toggle keeps the nesting written inside it\n"

assert_outline "a list outside a toggle draws three levels" \
  $'- a\n  - b\n    - c' \
  "$(
    cat <<'EOF'
item: a
item@18: b
item@36: c
EOF
  )"

assert_outline "and draws the same three levels written flush left inside one" \
  $'<details>\n<summary>S</summary>\n\n- a\n  - b\n    - c\n</details>' \
  "$(
    cat <<'EOF'
toggle: S
  item: a
  item@18: b
  item@36: c
EOF
  )"

assert_outline "and the same three levels indented one step under it" \
  $'<details>\n<summary>S</summary>\n\t- a\n\t\t- b\n\t\t\t- c\n</details>' \
  "$(
    cat <<'EOF'
toggle: S
  item: a
  item@18: b
  item@36: c
EOF
  )"

assert_outline "a code block inside nested toggles loses the toggles' indentation and keeps its own" \
  $'<details>\n<summary>L</summary>\n\t<details>\n\t<summary>C</summary>\n\t\t```ts\n\t\tconst a = 1;\n\t\t  indented();\n\t\t```\n\t</details>\n</details>' \
  "$(
    cat <<'EOF'
toggle: L
  toggle: C
    code: const a = 1;\n  indented();
EOF
  )"

printf "\nTest group: a summary written another way still titles its toggle\n"

assert_outline "a summary spread over lines, after a blank line, with an attribute" \
  $'<details>\n\n<summary class="x">Spread\nover lines</summary>\nbody\n</details>' \
  "$(
    cat <<'EOF'
toggle: Spread over lines
  p: body
EOF
  )"

assert_outline "a summary whose tags sit on lines of their own" \
  $'<details>\n<summary>\nTitle\n</summary>\nbody\n</details>' \
  "$(
    cat <<'EOF'
toggle: Title
  p: body
EOF
  )"

assert_outline "a toggle with no summary is titled Details" \
  $'<details>\nbody\n</details>' \
  "$(
    cat <<'EOF'
toggle: Details
  p: body
EOF
  )"

summary_html="$(printf '%s' $'<details>\n<summary>Board Layer **(2 points)**</summary>\n</details>' | node "$WORK/outline.mjs" --html)"
case "$summary_html" in
*"<summary>Board Layer <strong>(2 points)</strong></summary>"*) assert_ok "a summary's bold text is drawn bold" ;;
*) assert_ko "a summary's bold text is drawn bold" "$summary_html" ;;
esac

printf "\nTest group: a to-do is a box that names the line of the content it came from\n"

todo_html="$(printf '%s' $'- [ ] a\n<details><summary>S</summary>\n- [x] b</details>\n```\n- [ ] not a box\n```\n  - [ ] c' | node "$WORK/outline.mjs" --html)"
todo_lines="$(printf '%s' "$todo_html" | grep -oE 'data-line="[0-9]+"' | grep -oE '[0-9]+' | paste -sd ' ' -)"
if [ "$todo_lines" = "0 2 6" ]; then
  assert_ok "each box names its own line, past a toggle and a code block"
else
  assert_ko "each box names its own line, past a toggle and a code block" "got '$todo_lines' from $todo_html"
fi
case "$todo_html" in
*'<div class="md-todo done" data-line="2"><input type="checkbox" disabled="" aria-label="Mark not done" checked=""/>'*) assert_ok "a ticked to-do is drawn ticked" ;;
*) assert_ko "a ticked to-do is drawn ticked" "$todo_html" ;;
esac
case "$todo_html" in
*'data-line="0"><input type="checkbox" disabled=""'*) assert_ok "and with nothing to save a tick, the box cannot be ticked" ;;
*) assert_ko "and with nothing to save a tick, the box cannot be ticked" "$todo_html" ;;
esac

printf "\nTest group: toggle tags that are not at the start of a block stay text\n"

assert_outline "a tag mentioned in a list item and one inside a code block" \
  $'- write a <details><summary>X</summary> toggle\n```html\n<details>\n<summary>Y</summary>\n```' \
  "$(
    cat <<'EOF'
item: write a <details><summary>X</summary> toggle
code: <details>\n<summary>Y</summary>
EOF
  )"

printf "\nTest group: a card or epic id in the text is a link to it\n"

mention_html="$(printf '%s' $'Origin: FEAT-12, unblocked by **BUG-3** and EPIC-4\nsee `TIME-5`, [FEAT-6](https://example.com/FEAT-7) and MYFEAT-8 or FEAT-9x' | node "$WORK/outline.mjs" --html)"
mentions_found="$(printf '%s' "$mention_html" | grep -oE 'class="mention"[^>]*>[A-Z]+-[0-9]+' | grep -oE '[A-Z]+-[0-9]+$' | paste -sd ' ' -)"
if [ "$mentions_found" = "FEAT-12 BUG-3 EPIC-4" ]; then
  assert_ok "a bare id, one in bold and an epic's become links, and none in code, a link, a longer word or a url"
else
  assert_ko "a bare id, one in bold and an epic's become links, and none in code, a link, a longer word or a url" "got '$mentions_found' from $mention_html"
fi
case "$mention_html" in
*'href="/card/FEAT-12"'*'href="/epics?open=EPIC-4"'*) assert_ok "a card links to its page and an epic to the epics board" ;;
*) assert_ko "a card links to its page and an epic to the epics board" "$mention_html" ;;
esac

printf "\nTest group: a link to an attachment opens it through the app\n"

attachment_html="$(printf '%s' $'[flow diagram.html](attachments/EPIC-19/1-flow%20diagram.html) and [site](https://example.com/attachments/X/y)' | node "$WORK/outline.mjs" --html)"
case "$attachment_html" in
*'href="/attachments/EPIC-19/1-flow%20diagram.html"'*) assert_ok "a link into the board's attachments points at the app's attachment route" ;;
*) assert_ko "a link into the board's attachments points at the app's attachment route" "$attachment_html" ;;
esac
case "$attachment_html" in
*'href="https://example.com/attachments/X/y"'*) assert_ok "and a link elsewhere is left as written" ;;
*) assert_ko "and a link elsewhere is left as written" "$attachment_html" ;;
esac

printf "\nTest group: a toggle written the way Notion exports it is a toggle\n"

assert_outline "a toggle tag with a toggle header holds its body" \
  $'<toggle>\n<toggle-header>Investigation</toggle-header>\n### APIs\n- one\n</toggle>\nafter' \
  "$(
    cat <<'EOF'
toggle: Investigation
  heading: APIs
  item: one
p: after
EOF
  )"

assert_outline "and one titled by a summary closes where its tag sits" \
  $'<toggle>\n<summary>Options</summary>\nbody\n</toggle>\n<toggle>\n<summary>Root cause</summary>\nwhy\n</toggle>' \
  "$(
    cat <<'EOF'
toggle: Options
  p: body
toggle: Root cause
  p: why
EOF
  )"

assert_outline "a toggle tag inside a code block stays text" \
  $'```html\n<toggle>\n```' \
  "code: <toggle>"

printf "\nTest group: a diff block marks each line by what it does\n"

diff_html="$(printf '%s' $'```diff\n=== move it ===\n  same/\n+ added\n- removed\n! changed\n```' | node "$WORK/outline.mjs" --html)"
diff_kinds="$(printf '%s' "$diff_html" | grep -oE 'diff-line [a-z]+' | sed 's/diff-line //' | paste -sd ' ' -)"
if [ "$diff_kinds" = "heading same add del mod" ]; then
  assert_ok "a heading, an unchanged line, an addition, a removal and a change each get their own mark"
else
  assert_ko "a heading, an unchanged line, an addition, a removal and a change each get their own mark" "got '$diff_kinds' from $diff_html"
fi
case "$diff_html" in
*'<span class="diff-line add">+ added</span>'*) assert_ok "and keeps the line as written" ;;
*) assert_ko "and keeps the line as written" "$diff_html" ;;
esac

printf "\nTest group: a code block carries a header naming its language\n"

code_html="$(printf '%s' $'```ts title=a\nconst a = 1;\n```\n```\nplain\n```\n```mermaid\ngraph TD\n```' | node "$WORK/outline.mjs" --html)"
code_languages="$(printf '%s' "$code_html" | grep -oE 'class="code-language">[^<]*' | sed 's/.*>//' | paste -sd '|' -)"
if [ "$code_languages" = "TypeScript|Plain text|Mermaid" ]; then
  assert_ok "a known language by its name, an unnamed one as plain text, and only the first word of the fence"
else
  assert_ko "a known language by its name, an unnamed one as plain text, and only the first word of the fence" "got '$code_languages' from $code_html"
fi
case "$code_html" in
*'<pre class="md-code">const a = 1;</pre>'*) assert_ok "the code itself is drawn as written until the highlighter loads" ;;
*) assert_ko "the code itself is drawn as written until the highlighter loads" "$code_html" ;;
esac
case "$code_html" in
*'aria-pressed="true" title="Show the diagram only"'*) assert_ok "a mermaid block shows its diagram alone by default" ;;
*) assert_ko "a mermaid block shows its diagram alone by default" "$code_html" ;;
esac

printf "\nTest group: an image is drawn, and an attachment is drawn through the app\n"

image_html="$(printf '%s' $'![image](attachments/FEAT-282/1-image.png)\nsee ![icon](https://example.com/i.png) here' | node "$WORK/outline.mjs" --html)"
case "$image_html" in
*'<a class="md-image" href="/attachments/FEAT-282/1-image.png" target="_blank" rel="noreferrer"><img src="/attachments/FEAT-282/1-image.png" alt="image" loading="lazy"/></a>'*) assert_ok "an image on a line of its own is drawn from the attachment route and opens full size" ;;
*) assert_ko "an image on a line of its own is drawn from the attachment route and opens full size" "$image_html" ;;
esac
case "$image_html" in
*'<img class="md-inline-image" src="https://example.com/i.png" alt="icon" loading="lazy"/>'*) assert_ok "and one inside a sentence is drawn where it sits" ;;
*) assert_ko "and one inside a sentence is drawn where it sits" "$image_html" ;;
esac

printf "\nTest group: a table and a numbered list read as Notion wrote them\n"

table_html="$(printf '%s' $'| API | Allowed |\n| --- | --- |\n| ----- | :-: |\n| Get | No |' | node "$WORK/outline.mjs" --html)"
table_rows="$(printf '%s' "$table_html" | grep -o '<tr>' | wc -l | tr -d ' ')"
if [ "$table_rows" = "2" ]; then
  assert_ok "an alignment row is not drawn as a row of dashes"
else
  assert_ko "an alignment row is not drawn as a row of dashes" "$table_html"
fi

numbers_of() {
  printf '%s' "$1" | node "$WORK/outline.mjs" --html | grep -oE 'aria-hidden="true">[^<]+' | sed 's/.*>//' | paste -sd ' ' -
}
numbers="$(numbers_of $'1. a\n1. b\n\n1. c\n\t- d\n1. e\n## H\n3. f\n3. g')"
if [ "$numbers" = "1. 2. 3. • 4. 3. 4." ]; then
  assert_ok "a numbered list counts on past a blank line and a nested bullet, and starts again after a heading or from its first number"
else
  assert_ko "a numbered list counts on past a blank line and a nested bullet, and starts again after a heading or from its first number" "got '$numbers'"
fi

finish
