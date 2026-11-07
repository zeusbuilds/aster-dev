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

The `public-distribution` audience requires `ASTER_NETWORK=mainnet`. Use
`internal-beta` for other networks. Public distribution also
requires release-owned market, support, terms, and privacy destinations and a
qualified backup and restore process that preserves the wallet's durable
payment state. The validator accepts no
unknown keys and no credentials, tokens, API keys, mnemonics, passwords, or
other secrets. Compile-time values are recoverable from a mobile binary.

`ASTER_WALLET_BACKEND` identifies the on-disk wallet format. Existing
manifests default to `rln`. The validator rejects `rgb-l1` until Aster can
recover an interrupted BTC or RGB send using durable, authoritative transaction
identity on that backend. An RLN wallet directory cannot be opened as RGB_L1.

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

`ASTER_ETH_RPC_URL` is required, credential-free HTTPS configuration for native
BFA validation. `ASTER_ETH_CHAIN_ID` is the deployment-approved EVM backing
chain ID, expressed as a positive canonical decimal uint256. The wallet checks
`eth_chainId` against this identity before native initialization or unlock,
rejecting unavailable, malformed, redirected, or wrong-chain responses. There
is no chain default: the release owner must verify it alongside the canonical
mainnet RGB asset ID, precision, BFA contract identities, and backing policy.
This check does not authenticate contracts or establish bridge payout proof.
The mainnet USDT route fails configuration validation if either EVM setting is
missing. `ASTER_LSP_URL` is optional for the onchain-only release and cannot enable
Lightning payment actions. `ASTER_VSS_URL` remains required by the RLN release
configuration contract. Current RLN VSS does not back up the durable on-chain
outbox, so enabling it prevents recoverable BTC and RGB sends. Public
distribution fails validation until the backup and send-recovery requirements
can be qualified together. None of these endpoints may contain credentials or
API keys.

`ASTER_DAEMON_PORT` and `ASTER_LDK_PEER_PORT` are optional native listener
ports, defaulting to `9735` and `9736`. They must be distinct canonical decimal
integers from `1` through `65535`; invalid text never falls back silently.
These configure app-process listeners, not the indexer or LSP endpoint. Local
simulator builds use separate Aster ports to avoid other wallets; see
[local regtest](../docs/REGTEST.md). That ignored Debug/Profile configuration
is not a release manifest and does not weaken the TLS release policy.
