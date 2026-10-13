# Release Configuration

Aster release artifacts consume one non-secret JSON manifest through Flutter's
`--dart-define-from-file` option. Copy `release.example.json` to an ignored
local file, replace every placeholder, keep keys sorted, and validate it before
building:

```sh
make verify-release-configuration \
  RELEASE_CONFIG=config/release.internal.local.json \
  RELEASE_AUDIENCE=internal-beta
```

Use `public-distribution` only after release ownership has supplied the market
proxy, support, terms, and privacy destinations. The validator accepts no
unknown keys and no credentials, tokens, API keys, mnemonics, passwords, or
other secrets. Compile-time values are recoverable from a mobile binary.

The example deliberately fails validation until all `REPLACE_ME` values are
replaced with deployment-owned values. Local manifests and iOS export options
must never be committed.

The owned iOS export target also validates its ignored ExportOptions plist. It
requires an explicit Apple team, the committed bundle identifier, an export
destination, and `manageAppVersionAndBuildNumber=false`. Public distribution
accepts only an App Store Connect method. Manual signing must name the app's
single provisioning profile; automatic signing must not carry a manual profile
map, and new plist keys require a source-policy review.

`ASTER_USDT_PRECISION` is the asset's canonical decimal precision from `0`
through `18`. Negative, signed, padded, or out-of-range values fail before any
release build starts.

`ASTER_ETH_RPC_URL` is optional, credential-free HTTPS configuration for native
BFA validation. It does not add an Ethereum wallet or establish bridge payout
proof. `ASTER_LSP_URL` is optional for the onchain-only release and cannot enable
Lightning payment actions. Both are validated when supplied; `ASTER_VSS_URL`
remains required by the existing release deployment contract. None of these
endpoints may contain credentials or API keys.

`ASTER_DAEMON_PORT` and `ASTER_LDK_PEER_PORT` are optional native listener
ports, defaulting to `9735` and `9736`. They must be distinct canonical decimal
integers from `1` through `65535`; invalid text never falls back silently.
These configure app-process listeners, not the indexer or LSP endpoint. Local
simulator builds use separate Aster ports to avoid other wallets; see
[local regtest](../docs/REGTEST.md). That ignored Debug/Profile configuration
is not a release manifest and does not weaken the TLS release policy.
