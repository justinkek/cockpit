## React Native

- No inline styles. Use `StyleSheet.create` in a colocated `Component.styles.ts` file. Enforced by the `react-native/no-inline-styles` ESLint rule.
- Android defaults `overflow` to `hidden`. Set `overflow: 'visible'` on containers whose children render outside bounds (focus rings, shadows, scaled elements).
- Use `ImageBackground` (not `Image` + `absoluteFillObject`) for full-bleed screen backgrounds. `ImageBackground` inherits layout from the navigator and fills correctly across platforms.
- Prefer pure JS/TS solutions over native modules. Native modules require per-platform porting and maintenance; only reach for them when no JS alternative exists.
- Path aliases must be defined in every config that resolves them: `tsconfig.json` (`paths`), the test runner's mapper (Jest `moduleNameMapper`), and the bundler's resolver (Babel `module-resolver` alias). Metro resolves via babel at runtime, the test runner via its own mapper, and `tsc` via tsconfig - a missing entry in any one silently breaks that tool and no other.
