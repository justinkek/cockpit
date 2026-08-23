## VegaOS

Constraints and workarounds discovered on device. Violating these causes silent failures or security regressions.

### Privileges

- Declaring privileges in `manifest.toml` is necessary but not sufficient. Without a runtime request the platform rejects the privileged call with a security error that persists across reinstall.
- `PermissionsKepler` is the wrong API - it fails silently (returns denied, never prompts). It only covers user-facing permissions, not system privileges.
- Use `SecurityManager` from `@amazon-devices/security-manager-lib`: `getPrivilegeState` then `requestPrivilege`. This is what produces the OS consent prompt.

### Native module

- Codegen runs, but only for an interface extending `KeplerTurboModule` from `@amazon-devices/keplerscript-turbomodule-api` - it silently finds no module in one extending `TurboModule`. Type numbers with that package's `Int32`/`Double`/`Float`; a plain `number` becomes `double` in C++.
- The generated spec is committed and nothing in the build regenerates it, so an uncommitted spec breaks the build. Codegen reads parameter _names_, not just types - rerun it after any signature edit or CI fails.
- Never edit anything under `generated/`. A C++ change is unverified until the debug build passes: typecheck, lint, tests, formatter and codegen all pass on C++ that does not compile.

### Library compatibility

- **react-native-screens:** only `fade` stack animation works. Gestures, status bar props, and header components (`ScreenStackHeaderConfig`, `ScreenStackHeaderCenterView`, etc.) are not supported.
- **react-native-svg:** `Polygon`, `Polyline`, `TextPath`, `Symbol`, `Pattern`, `Marker`, and `ForeignObject` are not available. Touch events (`onPress`, `onPressIn`, `onLongPress`) do not work on SVG elements.
- **react-native-fast-image:** versions <=2.x crash on VegaOS 0.12+ with `FastImageTurboModule could not be found`. Use `^3.0.0`. The `defaultSource`, `tintColor`, and `onFastImageProgress` props are not supported.
- **react-native-reanimated:** `withRepeat` stops repeating and animated styles stop updating after fast refresh. Dev workflow only - production is unaffected.

### Platform architecture

- React Native for Vega is dynamically linked from the OS, not statically bundled per-app. The RN version is an OS-level decision. Use `isPresentOnOS` to check whether a dependency is available on the device before calling it.
- JSI only - no legacy bridge. All native modules must be turbo modules; Fabric is the only rendering path.
- Google Play Services are not available. Use Amazon alternatives for location, billing, authentication, and messaging.
