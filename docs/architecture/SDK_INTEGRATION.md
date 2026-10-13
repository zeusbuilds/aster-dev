# RGB SDK Integration

The app consumes `rgb_sdk_flutter` through its stable public Dart API. Native
wire DTOs, Pigeon messages, platform channels, and SDK-owned storage are not app
architecture boundaries.

## Reproducible Dependency

The checked-in `pubspec.yaml` and `pubspec.lock` resolve the public UTEXO
protocol SDK repository to immutable commit
`7c44506fdfe1dae6f3a6fe884f849c7ca2ad028b`. Do not replace the commit with a
branch, tag, moving reference, or local path in a committed change.

After changing the SDK pin intentionally, run:

```sh
fvm flutter pub get
fvm dart run build_runner build
fvm flutter analyze --fatal-warnings --fatal-infos
fvm flutter test
```

Both iOS and Android builds are required before accepting a new SDK commit.

The pinned revision targets RN `1.0.0-beta.37` (commit
`e38329eba11cce16e3bea75b8a4e7becd52c0036`), core `1.0.0-beta.9`, WebRGB
`0.1.2`, and RLN `0.16.0-beta.3`. The app's Flutter 3.47.0 / Dart 3.13.0, iOS 18.5 minimum,
Android compile SDK 36 and Java 17 already satisfy its requirements. Native
artifacts follow the SDK's checked-in baseline and checksum-verifying hooks;
never reuse binaries from a previous Pub checkout by copying them manually.

## Upgrade Contract And Feature Coverage

| App path | Stable SDK contract | Upgrade handling |
| --- | --- | --- |
| Create/import | generateKeys, validateBip39Mnemonic, init, unlock | App owns secrets and commit/rollback; no new-store init on persisted data. |
| Restore/switch/resume/dispose | reinit, shutdown, destroy | One serialized app owner; native deadlines and quarantines remain authoritative. |
| Home/balances | getBtcBalance, getAssetBalance, getNodeInfo, listChannels | RGB read values are BigInt. Narrow only after non-negative signed-64 range checks; sum exactly, never via double. |
| Activity/details | listTransactions, listTransfers(assetId), listPayments | WaitingBroadcast has a dedicated app status. An unallocated pending/failed receive has unknown amount, never its requestedAssignment amount. Settled fungible records still require actual positive allocations. |
| Send/receive | getAddress, decodeRgbInvoice, decodeLnInvoice, onchainReceive, onchainSend, sendBtc, createLightningInvoice, payLightningInvoice | Identity, network, expiry, amount and mutation-outcome checks are retained. RGB decoded amounts use checked BigInt conversion; non-fungible instructions are rejected. |
| Fees/settings | estimateFeeRate, getNetworkInfo, getNodeInfo | Fees remain sat/vbyte; network metadata and account xpubs stay behind the adapter. |
| Network policy | getNetworkDefaults | SDK owns indexer/proxy defaults. The LSP resolver is not exported, so the reviewed UTEXO signet LSP URL remains explicit app deployment policy, validated and shown in Settings. |
| Errors | Typed SDK exceptions | Quote/proof verification failures and LNURL business rejections are not connectivity failures and are not automatically retryable. Raw reasons, response bodies and credentials never cross to UI. |

Aster intentionally supports the configured USDT contract ID, including BFA
inventory, not arbitrary ticker-based or linked-asset substitution. Lightning
send/receive choices stay visible but disabled as Coming later on every network.
Direct repository requests also fail before any native work. Non-mainnet
existing Lightning balances/history remain visible; mainnet skips those APIs
because RLN 0.16 has no Lightning runtime there. Other errors are never converted
into empty balances/history. Outgoing RGB Send/Burn/Inflation uses the SDK's
exact recipient amount rather than change allocations; absent amounts remain
unknown. The upgrade does not
add Lightning Addresses, APay proofs, LSP relay/bridge/channel provisioning,
linked/canonical asset selection, inflation, PSBTs or native VSS backup UI.
These require explicit app models, product flows and funded integration proof;
the presence of methods in the dependency is not evidence they work in Aster.
Detailed refresh, UTXO existence and linked-IFA metadata are SDK capabilities,
not newly exposed app APIs. Existing sync uses syncWallet; fee-aware Send Max
and Swap remain unavailable rather than approximated or simulated.

The optional SDK WebRGB provider supports witness receiving and approved native
message signing. Its WalletConnect router is not a complete connection flow:
Aster has no live WalletKit pairing/consent integration or configured Reown
project ID. These remain explicitly tracked; no Connect or burn success is
simulated. BFA/Ethereum and VSS service qualification and PKG-006 still prevent
a mainnet-ready claim.

The SDK reads the full UInt64 RGB range; Aster's supported amounts and sums
remain `0..9223372036854775807` smallest units. Values outside that domain fail
closed. This is an app limitation, not a claim that the SDK cannot represent
them. Bitcoin Lightning values remain millisatoshis; node.localBalanceMsat is
derived from whole localBalanceSat, not a new source of sub-satoshi precision.
Unbound no-asset receive requests cannot appear in an asset-specific feed until
native identifies their asset; they are never guessed to be USDT.

## Optional Local Override

When developing the SDK and app together, create an ignored
`pubspec_overrides.yaml` in the repository root:

```yaml
dependency_overrides:
  rgb_sdk_flutter:
    path: ../rgb-sdk-flutter
```

Run `fvm flutter pub get` after adding or removing the file. Compilation,
analysis, documentation, test, and repository-verification Make targets enforce
the committed lockfile and regenerate ignored sources before consuming that
graph. Before lint, integration, or release evidence, remove the override, run
`make dependencies`, and confirm that `pubspec.lock` contains the immutable Git
`resolved-ref` above. The override is ignored by Git and is never supported for
candidate evidence.

## Ownership Boundary

`WalletRuntime` is the only app-owned native runtime. `RgbWalletEngine` is the
only adapter that holds a `UtexoWallet`; all SDK DTOs are converted to app-owned
models at that boundary, with private balance, activity and scalar-mapping
collaborators. The only stable SDK import outside that adapter family is the
redacted error mapper. UI and ViewModels depend on repositories and app models and never call
the SDK, native bridge, storage, HTTP, or platform plugins directly.

The runtime serializes all native access with provision, open, sync, suspend,
resume, switch, and destroy. Provisioning a new store maps to the SDK's
one-time `init` followed by `unlock`; opening any existing store maps to
`reinit`. Restore, wallet switching, switch rollback, foreground resume, and
fresh-engine recovery must never send a persisted store through `init`.

A wallet switch destroys the old native owner, opens the target, and restores
the previous wallet when target activation fails. Creation first persists a
`provisioning` profile, then commits it as `ready` only after native activation
succeeds. Bootstrap rolls back interrupted transactions before opening the
selected ready wallet. App pause, resume, and detach transitions enter through
the repository mutation queue so they cannot split native provisioning from
its metadata commit. Resume may reopen a suspended owner or recover a
known-safe retryable lifecycle failure against the durable active profile. It
cannot clear a reconciliation-required failure: `WalletRuntime` preserves the
first such failure and blocks normal queued work until a successful rollback
for the owning wallet or successful disposal completes. An unknown native
outcome is the strongest subset of this contract, not the only reason
reconciliation can be required.

### Debug hot restart

Hot reload is supported. A Flutter hot restart replaces the Dart isolate but
does not detach the iOS or Android plugin from the still-running Flutter
engine. The pinned SDK retains its engine-owned native RLN node, while the new
isolate has no public API with which to adopt or release that orphaned handle.
Creating another node for the same storage directory therefore fails closed.

Do not bypass the SDK with a private platform channel, guess native node IDs,
or delete wallet storage. Quit the current `flutter run` session and start a
new one when an isolate restart is required. A process restart releases the
plugin store and then exercises the same persisted-wallet `reinit` path used by
a normal app launch. Full hot-restart support requires a future immutable SDK
revision with a public, ownership-safe isolate-reattach contract.

## Runtime Configuration

The app reads non-secret service settings from compile-time defines. Debug and
Profile developers may pass individual values while investigating one local
environment. Every Release artifact instead requires the single reviewed JSON
manifest documented in `config/README.md` and consumes it through
`--dart-define-from-file`:

| Define | Purpose |
| --- | --- |
| `ASTER_NETWORK` | `regtest` (default), `signet`, or `mainnet` |
| `ASTER_INDEXER_URL` | Optional Electrum/Esplora override |
| `ASTER_RGB_PROXY_URL` | Optional RGB transport proxy override |
| `ASTER_LSP_URL` | Optional LSP base URL |
| `ASTER_VSS_URL` | Optional VSS base URL |
| `ASTER_ETH_RPC_URL` | Optional credential-free Ethereum validation RPC, not an Ethereum wallet or payout verifier |
| `ASTER_EXPLORER_URL` | Optional public transaction explorer base |

Credentials and bearer tokens must never be supplied through either individual
defines or the manifest; those values are recoverable from the application
binary. Release validation rejects unknown keys, placeholders, and non-TLS
service endpoints before packaging. At composition,
`RgbWalletServiceConfigurationResolver` fills missing indexer and RGB transport
values from the immutable SDK's public network-default contract and fills the
same UTEXO protocol signet LSP default used by that pinned SDK. The resolved
object is then validated once and shared unchanged by the runtime and the
read-only Network Configuration screen. Settings therefore reports the complete
public endpoint, including a meaningful path, that the wallet will actually
contact. An explicit define always wins. Advancing the SDK pin requires
rerunning the exact default-resolution tests and reviewing this endpoint
inventory.

Each resolved endpoint is bounded to 2,048 visible-ASCII characters and must
use a canonical DNS, IPv4, or IPv6 host. Malformed DNS labels, encoded control
text, and resolver-dependent numeric aliases such as `127.1` fail before any
native wallet is created. Plain HTTP is accepted only for canonical loopback
development endpoints in Debug and Profile builds. Release validation rejects
HTTP, unencrypted Electrum (`tcp`), and unencrypted RGB transport (`rpc`) even
on loopback, so the SDK's local HTTP regtest indexer default deliberately makes
an unconfigured Release build fail closed. A Release regtest deployment must
supply explicit TLS-protected endpoints. Regtest validation recognizes
expanded and IPv4-mapped IPv6 loopback and rejects host ports `18443`, `50001`,
and `3000`, which belong to the protected external performance-lab stack
documented in `docs/DEVELOPMENT.md`.

The product-facing network is `mainnet`, `signet`, or `regtest`. The SDK's
`utexo` service profile is an implementation detail used for UTEXO protocol
signet services and is never treated as a fourth blockchain.

## Credential Ownership

Each wallet receives a random 128-bit opaque ID, an independent 128-bit storage
ownership token, and a random 256-bit native database password from
`Random.secure()`. The password and recovery mnemonic are stored together in
one schema-tagged encrypted record keyed by the opaque ID. They are never
stored in SharedPreferences or presentation state.

The non-secret ownership token is written to both the encrypted envelope and a
marker inside the native directory. Rollback deletes a resource only when its
token matches; collisions and resources with mismatched ownership are preserved
and reported. This prevents crash recovery from deleting data it cannot prove
the current provisioning transaction created.

Aster has not shipped, so storage has one current schema and no compatibility
reader for previous development formats. Older development installs must be
cleared and wallets restored from their recovery phrase.

- iOS uses a non-synchronizing, this-device-only Keychain accessibility class.
- Android pins RSA-OAEP key wrapping and AES-GCM data encryption in a dedicated
  Aster namespace. The pinned plugin's algorithm-change switch remains enabled
  only because version 10.3.1 uses it to initialize modern cipher markers in a
  fresh namespace; its backup compatibility path remains disabled. This does
  not read another namespace or app schema. `resetOnError` is false, app backup
  and device transfer are disabled, and optimized releases remove dependency
  Android log calls.
- Corruption is surfaced and retained for recovery analysis. It is never
  silently reset.
- Dart strings cannot be reliably zeroized. Callers therefore keep credential
  objects inside the narrowest asynchronous scope and never cache or log them.

The app does not yet define a PIN or biometric unlock product contract. Adding
user-presence protection is a future security decision, not an implicit plugin
default.

## Domain Boundary

Bitcoin and RGB are asset protocols; on-chain and Lightning are payment rails;
mainnet, signet, and regtest are chain environments. These are separate types.
RGB USDT identity is its immutable contract ID, never the `USDT` ticker.
Amounts use integer sats, millisats, or RGB smallest units. Fiat market data is
converted to the selected ISO currency's integer minor units at the repository
boundary. Bitcoin and Tether prices are independently validated so one partial
provider value cannot manufacture or erase the other. Market service and
attribution policy are app-owned and do not cross the SDK boundary.

The app reads the environment-specific USDT contract through
`ASTER_USDT_ASSET_ID` and its integer precision through
`ASTER_USDT_PRECISION`. Both must be present and valid or both USDT payment
routes fail closed as unavailable. Stable navigation carries only the product
target (`usdt-onchain` or `usdt-lightning`); the repository resolves that
untrusted identifier back to deployment-owned contract metadata before any SDK
operation.

The SDK's accepted PKG-006 artifact-provenance constraint remains visible in
the app release report. Until that constraint is resolved upstream, this app
cannot make a truthful funds-bearing mainnet production claim.
