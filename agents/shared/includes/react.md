## React

- Type components with `FC<Props>` - e.g. `export const Button: FC<ButtonProps> = (...) => {`.
- Don't use `useCallback` or `useMemo` unless profiling proves a performance problem. Inline handlers by default.
- Keep child components dumber than the parent that renders them. Push state, logic, and data-fetching up to the parent; children receive props and render.
- Colocate styles in a separate file - `Component.styles.ts` next to `Component.tsx`.
- Store `useRef` return value, access `.current` at usage sites - don't destructure `.current` at creation (e.g. `const ref = useRef(x)` then `ref.current`, not `const val = useRef(x).current`).
- Custom hooks that wrap a query library must rename `data` to a domain-specific name at the destructure site (e.g. `const { data: approval } = useQuery(...)`) and return only the fields consumers use via an explicit interface - not a full result spread.
- Before adding inline color, spacing, shadow, or radius values, check the project's theme tokens. Use theme tokens over raw values - inline literals drift when the design system changes.
- Extract all business logic from screen components into a colocated `useFooScreen` hook (e.g. `useSignInScreen`). The screen component should be purely presentational - destructure the hook's return value and render.
- Reach for `useEffect` last. A value that follows from props or state is worked out while the screen draws; a value that follows from something the user did is worked out in that handler; server data is read through the query layer. An effect is for driving something outside the screen - a timer, a subscription, an imperative animation - and it always cleans up.
- No inline `useEffect` - extract every effect into a named custom hook (e.g. `useCountdownTimer`, `useInterceptBackNavigation`). The hook name documents what the effect does, making the call site self-describing and the effect independently testable. Prefer generic, reusable hooks over single-use domain-specific extractions - don't hardcode domain types into hooks that wrap platform behavior. Use `enabled` for boolean toggle parameters. Use an explicit variable for event listener cleanup (`const unsubscribe = addListener(...)`) - never return the registration call directly.
- Values derived from `Date.now()` recompute on every parent re-render, restarting animations from a new position each time. Capture the initial value with `useRef` at mount so the animation runs uninterrupted.
- `gcTime: 0` in React Query does not clear synchronously. After a navigation reset, stale cached data can render before cleanup finishes. Clear the cache manually (`queryClient.clear()`) before resetting the stack to force a clean loading state.
