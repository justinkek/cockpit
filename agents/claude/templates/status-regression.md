# Walking a ticket backward

Read this when the target column is behind the ticket's current one.

A backward target is a **regression**. It is only legal when the current column has a matching counter - never from a column without one. Move and report inline like any other advance.

**Regression source → counter mapping:**

| Current column         | Counter property       |
| ---------------------- | ---------------------- |
| `In BR by AI`          | `Back from BR`         |
| `Ready for BR`         | `Back from BR`         |
| `In BR`                | `Back from BR`         |
| `In TR by AI`          | `Back from TR`         |
| `Ready for TR`         | `Back from TR`         |
| `In TR`                | `Back from TR`         |
| `In Dev`               | `Back from Dev`        |
| `In CR by AI`          | `Back from CR`         |
| `In CR`                | `Back from CR`         |
| `In FR`                | `Back from FR`         |
| `Ready for Validation` | `Back from Validation` |

**Regression procedure:** delegate to the `cockpit:ticket:x:back-from-column` skill. It owns the full regression flow: infer structured summary from session context, increment counter, write nested toggle to ticket page under `## Details`, post short comment, and set status directly (no intermediate walk). Invoke `/cockpit:ticket:x:back-from-column` with the source column, target column, and inferred reason. Do not duplicate any of these steps inline.
