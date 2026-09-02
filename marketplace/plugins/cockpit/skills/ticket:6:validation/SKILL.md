---
name: ticket:6:validation
description: Move the session's cockpit ticket to Ready for Validation.
---

# ready-for-validation

Move the registered cockpit ticket to the `Ready for Validation` column. This is a user-triggered action - never invoke it automatically.

Invoke the `cockpit:ticket:x:status` skill with target `Ready for Validation`. The skill handles the ordered walk, date-stamp polling, usage recording, and source ticket sync.
