# Writing code

Read this before writing or changing code.

## Auto-generated files

When you create or modify a file that is auto-generated, mark it in `.gitattributes` with `linguist-generated`. Add the pattern in the same commit as the generated file.

```
# .gitattributes
path/to/generated-file linguist-generated
```

Common patterns to mark:

- Lock files (`package-lock.json`, `yarn.lock`, `pnpm-lock.yaml`, `Gemfile.lock`, `poetry.lock`, `composer.lock`, `Cargo.lock`)
- Migration snapshots (`**/Migrations/*Snapshot.cs`, `**/migrations/*.py`)
- Compiled/bundled output (`dist/`, `build/`, `*.min.js`, `*.min.css`)
- Generated types or clients (GraphQL codegen, OpenAPI, Prisma client)
- Vendor directories (`vendor/`)
- Visual artifacts (HTML reports, generated SVGs, generated diagrams)

Use glob patterns when a directory holds only generated files. If `.gitattributes` does not exist, create it at the repo root.

## Imports

Prefer absolute imports over relative imports. When a project has absolute import paths configured (tsconfig paths, vite resolve.alias, webpack aliases, etc.), use them by default. When a project has no absolute import configuration, suggest adding it before writing new imports.

## Collection transforms

Prefer functional transforms over imperative loops for collection operations: `.map`, `.filter`, `.reduce`, `.find`, `.some`, `.every`, `.flatMap` over `for`, `for...of`, `while`, `.forEach`.

Use an imperative loop only when it is clearly better: early exit on a condition, complex stateful iteration where `.reduce` would be less readable, or a measured performance-critical hot path.

## Error handling (TypeScript)

In new TypeScript repos, express fallible operations as union return types instead of throwing exceptions:

```typescript
function getUser(id: string): NotFoundError | User {
  const user = db.find(id);
  if (!user) return new NotFoundError(id);
  return user;
}
```

Callers narrow with `instanceof` and early return - flat, not nested:

```typescript
const user = getUser(id);
if (user instanceof Error) return user;
// TypeScript narrows to User here
```

Rules:

- Return `ErrorType | SuccessType` from functions that can fail.
- Define custom errors as classes extending `Error` with a descriptive name.
- Narrow with `instanceof` checks, not try-catch.
- At third-party boundaries (libraries that throw), wrap once with try-catch and convert to a union return.
- Don't retrofit this pattern onto existing code that uses try-catch. Apply only in new repos or new modules that opt in.

## Asset naming

Name image and icon constants by subject then type: `homeIcon`, `searchIcon` - not `icHome`, `iconHome`, or `home_icon`.

## Security

- Never log key material, tokens, or credentials - not truncated, not at debug level, in any language or layer. Log a property instead: its length, its presence, or a non-secret identifier. "Private key is 31 bytes, expected 32" debugs the bug without leaking the key.
- Pin the audit threshold in CI deliberately, and say why in the config.
- Use dependency overrides to pin a transitive dependency when a vulnerability has a fix but the direct dependency has not shipped it.

## Dependencies

- Before adding a dependency, check its licence is compatible with the project's own. `npm view <pkg> license` answers it in one command.
- Wire a licence check into CI so the whole tree is validated, not only the package someone remembered to check.
- Native (C/C++) dependencies are not covered by the JS licence check - check them by hand and record them where the next person will look.

## Tool versions (mise)

Use `mise` for runtime/tool version management. Project-local `.mise.toml` or `.tool-versions` files pin versions per-repo.

- Run tools through mise when available: `mise exec -- <command>` or rely on mise shims (activated in the shell via `mise activate`).
- Don't set `JAVA_HOME`, `PYTHON_HOME`, or similar env vars by hand. If the wrong version is active, fix the mise config (`.mise.toml` / `.tool-versions`), not the command.
- When a project needs a runtime not yet in mise, add it to the project's `.mise.toml` rather than installing globally.
