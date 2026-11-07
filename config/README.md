# Release Configuration

For a **Debug public Signet BTC-only** test, use the committed, non-secret
`signet-public.debug.json` preset:

```sh
fvm flutter run --debug -d <device-id> \
  --dart-define-from-file=config/signet-public.debug.json
```

This is public Bitcoin Signet, not the separate UTEXO Dev chain. It configures
public Esplora, the RLN-compatible proxy 0.2 and dedicated Aster listener ports
`19775`/`19776`. It intentionally configures no USDT, EVM or VSS and is not a
release manifest. Aster's public Signet defaults select these public services
rather than the native `utexo` carrier's historical Dev defaults.

`ASTER_SIGNET_DEPLOYMENT` accepts `public` (the default) or `dev-signet`.
The latter is explicitly blocked before wallet/native access. Known Dev service
hosts and current/historical Dev asset IDs are also blocked if mixed into an
ordinary profile. `dev-signet.evidence.json` records quarantined deployment
evidence, including missing current contract bytes, checksum and verified
precision. It is not a Flutter defines preset or an asset registry. The
historical BFA.5 export cannot substitute for the current BFA.6 asset. RGB_L1
remains gated separately; neither profile selection nor a debug build enables
it.

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

The RGB_L1 adapter also requires the issuer-approved public genesis and exact
native metadata before it admits USDT. Supply all four fields together:
`ASTER_USDT_CONTRACT_BASE64` (canonical standard Base64),
`ASTER_USDT_CONTRACT_SHA256` (lowercase SHA-256 of the decoded bytes),
`ASTER_USDT_NATIVE_NAME` and `ASTER_USDT_NATIVE_TICKER`. These are public
contract data, never a seed or backup. Runtime and release tooling share the
bounded canonical-encoding/digest checks. The adapter then imports with the
expected asset ID and verifies BFA schema, native name, ticker and precision
before it connects or generates the first asset-bound witness invoice.
A checksum confirms reviewed bytes; issuer approval and native validation
remain separate requirements. Missing current Dev bytes must not be filled
with the historical BFA.5 export. RGB_L1 and Dev gates remain closed.

`ASTER_USDT_PRECISION` is the asset's canonical decimal precision from `0`
through `18`. Negative, signed, padded, or out-of-range values fail before any
release build starts.

BFA.7 also requires deployment-approved external-chain mint-lock bounds for each EVM
service: `ASTER_BFA_MIN_MINT_LOCK_BLOCKS` and
`ASTER_BFA_MAX_MINT_LOCK_BLOCKS`. Supply both canonical decimal counts of backing EVM blocks,
with `2 <= minimum <= maximum`. There is no default. Aster forwards the explicit
range together with the RPC and expected chain ID to the RGB_L1 native runtime.
The previous Iris candidate's test bounds do not approve the current Dev policy;
the issuer/bridge team must confirm it. RLN rejects these unused RGB_L1 fields.

`ASTER_ETH_RPC_URL` is required, credential-free HTTPS configuration for native
BFA validation. `ASTER_ETH_CHAIN_ID` is the deployment-approved EVM backing
chain ID, expressed as a positive canonical decimal uint256. The wallet checks
`eth_chainId` against this identity before native initialization or unlock,
rejecting unavailable, malformed, redirected, or wrong-chain responses. There
is no chain default: the release owner must verify it alongside the canonical
mainnet RGB asset ID, precision, BFA contract identities, and backing policy.
This check does not authenticate contracts or establish bridge payout proof.
Environment-configured BFA USDT on every network, and any public-network USDT,
fails configuration validation if either EVM setting is missing. Generic
in-memory regtest RGB fixtures need not use a BFA schema; only those explicitly
set `RgbAssetConfiguration.requiresEvmValidation: false`. It defaults to true.
`ASTER_LSP_URL` is optional for the onchain-only release and cannot enable
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
