## React Native TV

- TV apps use a fixed logical viewport (e.g. 1920x1080). Use pixel values from design specs directly - no responsive scaling or percentage-based layouts.
- No touch events - all interaction is D-pad/remote. Every interactive element must be wrapped in a spatial-navigation focusable view.
- Focus rings, glow effects, and scaled-on-focus elements must not be clipped. Set `overflow: 'visible'` on their containers.
- When translating Figma designs to RN layout:
  - Check whether a Figma frame uses Auto Layout before choosing the strategy.
  - Auto Layout frames → flex + gap.
  - Absolute-positioned frames → fixed offsets (`paddingTop`, `height`, `bottom`), not `justifyContent: 'center'` with compensating padding.
- Spatial navigation roots (e.g. `SpatialNavigationRoot`) all subscribe to the same `TVEventHandler`. Background screens receive key events and trigger navigation. Gate each root's `isActive` with `useIsFocused()` so only the focused screen processes remote input.
- Every screen with focusable elements needs a default-focus wrapper. Without it, focus is lost on navigation and no element responds to the remote.
- Native stack keeps background screens mounted - it does not unmount on navigate. Timers, subscriptions, and callbacks on background screens keep firing. Guard navigation callbacks and side effects with `navigation.isFocused()` or `useFocusEffect`.
- `popToTop` + `push` triggers sequential animations through intermediate screens, causing a visible delay. Use `navigation.reset()` for atomic stack replacement with an instant transition.
