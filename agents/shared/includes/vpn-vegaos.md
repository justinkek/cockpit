## VPN on VegaOS

What a VPN app adds to the platform rules in `~/.agents-shared/includes/vegaos.md`. Read that file too - everything there applies here.

### Privileges

- All three privileges are required, not just `net-vpn-ctrl`:
  - `network-access` gates event subscription (every lifecycle call waits on an event).
  - `net-info` gates interface enumeration (needed for leftover interface detection).
  - `net-vpn-ctrl` gates tunnel creation.
- Without a runtime request the platform rejects `createVpn` with a security error that persists across reinstall.

### Native module

- Nothing JS-reachable creates a tunnel interface or installs routes. Native code is unavoidable - keep it confined to tunnel lifecycle and key handling.
- The private key lives in native process memory and does not survive a restart. A fresh key pair is generated per launch and re-registered. Acceptable only while certificates are requested on every connect.
- **The private key never crosses the bridge.** `generateKeyPair` derives and stores the X25519 key natively and returns only the public key; the native config setter accepts no private key. JS cannot read, persist, or log it. Preserve this invariant in any refactor.

### Crypto

- No crypto package is available to the Vega build. TweetNaCl is vendored under the native turbo module's own `vendor/tweetnacl` (public domain, provenance in its `NOTICE.md`). libsodium or `go-vpn-lib` remain possible swaps.
