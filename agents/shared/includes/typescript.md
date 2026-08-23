## TypeScript

### Formatting

- Single quotes for strings.
- Trailing commas everywhere (`trailingComma: 'all'`).
- 2-space indentation.
- Bracket same line for JSX (`bracketSameLine: true`).
- Preserve prose wrap in markdown - one paragraph is one line, never reflow.

### Naming

- PascalCase for type aliases, interfaces, and enums.
- No `I` or `T` prefix on types - `User` not `IUser`, `Config` not `TConfig`.

### Barrel files

Don't use barrel files (`index.ts` re-exports). Import directly from the source module. Barrel files hide dependency graphs, break tree-shaking, and cause circular import issues at scale.

### External boundary validation

Data crossing an external boundary (API responses, persisted/cached data, user input, third-party messages) must be parsed by a runtime schema. `as` type assertions are not validation - they silence the compiler without checking the data. Use a schema library (valibot, zod, etc.) or a hand-written type guard with runtime checks.

### Constants

Only extract a value into a named constant when the name adds meaning beyond the literal. `ONE_HOUR_IN_MS` is a good constant (unit conversion). `SERVERS_STALE_TIME_MS = 3 * ONE_HOUR_IN_MS` is not - it just restates the usage site. Inline domain-specific values at the call site and compose from shared unit constants (e.g. `staleTime: 3 * ONE_HOUR_IN_MS`).

### Strict tsconfig baseline

Enable these flags in new TypeScript projects:

- `strict: true`
- `noUncheckedIndexedAccess: true` - array/object index returns `T | undefined`.
- `exactOptionalPropertyTypes: true` - distinguishes `undefined` from missing.
- `noImplicitOverride: true` - requires `override` keyword on overridden methods.
- `allowJs: false` - no JavaScript files in TypeScript projects.
