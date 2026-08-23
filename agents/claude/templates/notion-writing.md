# Writing to a Notion page

Read this before writing content to a Notion page.

## Toggles and tables

Use `<details><summary>` for collapsible sections (not `>` blockquotes) and `<table>` XML for tables (not markdown pipes). Both are Notion-flavored markdown; the standard markdown equivalents render poorly.

Toggle syntax - each tag on its own line, children tab-indented:

    <details>
    <summary>Section title</summary>
    	Child content here
    	- Bulleted child
    	More content
    </details>

Never put a line that looks like HTML inside a fenced code block in a toggle. Notion parses `<summary>` or `</details>` as markup even inside the fence, which closes the toggle early and scatters the rest of the block across the page. Elide those lines out of the sample, or describe them instead of showing them.

## An edit that silently does not happen

`update_content` reports success when `old_str` matched nothing, so an edit can silently not happen.

- Build `old_str` from a fresh fetch, never from the text you sent earlier.
- Keep it to a single plain-text line. A code-block interior is stored de-indented and a commented line is stored wrapped in a discussion span, so neither can be matched.
- After the call, confirm each `new_str` is on the page and report only the edits that are. Confirm your own text is present, never that the page is otherwise unchanged - the user may be editing it at the same time.

`replace_content` is for one case only: clearing comments whose blocks you are rewriting anyway (see `~/.claude-shared/templates/page-comments.md`). It takes the whole body, so anything you leave out is deleted. Never reach for it to save yourself assembling an `old_str`.
