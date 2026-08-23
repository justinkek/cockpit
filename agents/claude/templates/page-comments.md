# Open comments on a cockpit page

Drafting from the page body alone misses feedback a reviewer left as a comment. Read the comments first, so the draft answers them instead of the chat re-asking what the page already answers.

## Reading them

One read sees everything open: `notion-get-comments` with the `page_id` and `include_all_blocks: true`. It enumerates page-level threads and block-anchored ones alike, an anchor on a line inside a code block among them. Its default is page-level only, so that flag goes in every time, and resolved threads stay out - a resolved comment is feedback already acted on.

The `include_discussions: true` summary on a `notion-fetch` is not a second read. It returns a labelled sample under `example-discussions` whose counts are its own, not the page's, so nothing is reconciled against it.

A `total-count` of zero means there are none. Say so in the report and draft as normal.

When a comment contradicts the page body, the comment wins - it is the later statement.

## An image left on a comment

The read above does not return the file itself. A comment whose whole content is a screenshot comes back with nothing to read.

    "$HOME/.claude-shared/ticket-comment-images" "<page-id>"

prints one line per attachment - comment id, category, and a path on disk - and nothing at all when the page carries none. Open each path with the Read tool.

| Exit | What it means                                    | What to do                                    |
| ---- | ------------------------------------------------ | --------------------------------------------- |
| 0    | Every attachment is on disk.                     | Read each path it printed.                    |
| 2    | The argument holds no page id.                   | Pass the ticket's url or its 32 character id. |
| 3    | No credential on this machine.                   | Report the gap and name the page.             |
| 4    | The credential cannot read this page's comments. | Report the gap and name the page.             |
| 5, 6 | The read failed, or was rate limited.            | Say so and carry on without the image.        |

Asking the person to paste the image into the chat is not the fallback for any of these.

## Leave no comment behind

A comment the draft has answered must not still be sitting on the page - the reviewer would have to re-read it to find out it is dead. The agent cannot resolve one: the API has no resolve endpoint, and delete only works on comments the integration itself wrote. What it can do is take away the block the comment is anchored to.

So when the read above returned any comment, write the page back with `replace_content` and the full new body rather than patching sections with `update_content`. Every block is recreated, and an anchored comment does not survive the block it was anchored to.

- Fetch the page immediately before the call - not the read you started drafting from - and rebuild the body from that fetch, section by section: your redrafted section, and every other section reproduced verbatim. Anything you drop here is gone.
- A line on your earlier read and absent from this one was deleted by a person while you drafted. Leave it out and say it went; never put it back.
- Do this once, at the end, not per section.
- No open comments means no rebuild - patch as normal, and leave the rest of the page's blocks alone.

`update_content` could not do this job anyway: a commented line is stored wrapped in a discussion span, so an `old_str` built from its plain text matches nothing and the edit silently does not happen.
