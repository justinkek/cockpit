# Naming a session

Read this before naming a session, whether the name is the first one or a replacement. It is the only statement of the convention: nothing else - no hook message, no skill step - carries a second one.

One shape, whatever the session holds: a bracketed scope, then a lowercase description of the work.

    [scope] description

## Filling the bracket

| The session holds | Bracket                                 | Description        |
| ----------------- | --------------------------------------- | ------------------ |
| a ticket          | its epic                                | the ticket name    |
| an epic           | its project, or `epic` when it has none | the epic name      |
| neither yet       | the area being worked                   | what is being done |

Lowercase both parts.

A bracket over ~25 characters is shortened to the phrase that identifies it at a glance - typically its key action or object. One of 25 characters or fewer is left as it is.

| Full bracket                                                                     | Session name                                              |
| -------------------------------------------------------------------------------- | --------------------------------------------------------- |
| `aauser, when i open the app for the first time, i can sign in via qr code`      | `[sign in via qr code] ticket name`                       |
| `aaoperator, given the team has grown, when i open settings, i can manage roles` | `[manage roles] ticket name`                              |
| `claude setup`                                                                   | `[claude setup] ticket name` (unchanged - under 25 chars) |

A session holding neither a ticket nor an epic names the area the way the two above name theirs: `[claude] permissions`, `[cve] scanning`, `[notion] cockpit`.

## Setting it

    "$HOME/.cockpit/scripts/auto-rename" "<the name>"

`require-rename.sh` intercepts the call, records the name, and unlocks the session. Naming is self-serve; ask the user only when nothing in the session gives a basis for a name.

## Naming twice

A session named before its card was known is renamed once the card is: the bracket becomes the epic, the description the ticket name. One named with the card already in hand matches what registration would have built, and registration leaves it.

A ticket retitled during refinement takes the new title as the description, and the bracket stays as it is.
