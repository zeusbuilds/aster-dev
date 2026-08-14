# RGB SDK Integration

The app consumes `rgb_sdk_flutter` through its stable public Dart API. Native
wire DTOs, Pigeon messages, platform channels, and SDK-owned storage are not app
architecture boundaries.

## Reproducible Dependency

The checked-in `pubspec.yaml` and `pubspec.lock` resolve the public UTEXO Git
repository to immutable commit
`3dd82e23d80bb4bb6a2d2526c6c6741ac1ea1236`. Do not replace the commit with a
branch, tag, moving reference, or local path in a committed change.

After changing the SDK pin intentionally, run:

```sh
fvm flutter pub get
fvm dart run build_runner build
fvm flutter analyze --fatal-warnings --fatal-infos
fvm flutter test
```

Both iOS and Android builds are required before accepting a new SDK commit.

## Optional Local Override

When developing the SDK and app together, create an ignored
`pubspec_overrides.yaml` in the repository root:

```yaml
dependency_overrides:
  rgb_sdk_flutter:
    path: ../rgb-sdk-flutter
```

Run `fvm flutter pub get` after adding or removing the file. Before release
evidence, remove it, resolve dependencies again, and confirm that
`pubspec.lock` contains the immutable Git `resolved-ref` above. The override is
ignored by Git and is never supported for candidate evidence.

## Ownership Boundary

`WalletRuntime` is the only app-owned native runtime. `RgbWalletEngine` is the
only adapter that holds a `UtexoWallet`; all SDK DTOs are converted to app-owned
models at that boundary. The only other stable SDK import is the redacted error
mapper. UI and ViewModels depend on repositories and app models and never call
the SDK, native bridge, storage, HTTP, or platform plugins directly.

The runtime serializes all native access with init, unlock, sync, suspend,
reinit, switch, and destroy. A wallet switch destroys the old native owner,
opens the target, and restores the previous wallet when target activation
fails. Creation first persists a `provisioning` profile, then commits it as
`ready` only after native activation succeeds. Bootstrap rolls back interrupted
transactions before opening the selected ready wallet. App pause, resume, and
detach transitions enter through the repository mutation queue so they cannot
split native provisioning from its metadata commit. Resume reconciles a failed
in-memory transition against the durable active profile.

## Runtime Configuration

The app reads non-secret service settings from compile-time defines:

| Define | Purpose |
| --- | --- |
| `UTEXO_NETWORK` | `regtest` (default), `signet`, or `mainnet` |
| `UTEXO_INDEXER_URL` | Optional Electrum/Esplora override |
| `UTEXO_RGB_PROXY_URL` | Optional RGB transport proxy override |
| `UTEXO_LSP_URL` | Optional LSP base URL |
| `UTEXO_VSS_URL` | Optional VSS base URL |
| `UTEXO_EXPLORER_URL` | Optional public transaction explorer base |

Credentials and bearer tokens must never be supplied with `--dart-define`;
those values are recoverable from the application binary. At composition,
`RgbWalletServiceConfigurationResolver` fills missing indexer and RGB transport
values from the immutable SDK's public network-default contract and fills the
same UTEXO signet LSP default used by that pinned SDK. The resolved object is
then validated once and shared unchanged by the runtime and the read-only
Network Configuration screen. Settings therefore reports the complete public
endpoint, including a meaningful path, that the wallet will actually contact.
An explicit define always wins. Advancing the SDK pin requires rerunning the
exact default-resolution tests and reviewing this endpoint inventory.

Plain HTTP is accepted only for loopback development endpoints. Regtest
validation rejects host ports `18443`, `50001`, and `3000`, which belong to the
protected external performance-lab stack documented in
`docs/DEVELOPMENT.md`.

The product-facing network is `mainnet`, `signet`, or `regtest`. The SDK's
`utexo` service profile is an implementation detail used for UTEXO-hosted
signet services and is never treated as a fourth blockchain.

## Credential Ownership

Each wallet receives a random 128-bit opaque ID, an independent 128-bit storage
ownership token, and a random 256-bit native database password from
`Random.secure()`. The password and recovery mnemonic are stored together in
one versioned encrypted record keyed by the opaque ID. They are never stored in
SharedPreferences or presentation state.

The non-secret ownership token is written to both the encrypted envelope and a
marker inside the native directory. Rollback deletes a resource only when its
token matches; collisions and ambiguous legacy resources are preserved and
reported. This prevents crash recovery from deleting data it cannot prove the
current provisioning transaction created.

The previous committed app's `wallet_registry_v1` contained display metadata
but no matching native credential or ownership contract. It is detected and
left untouched. The app returns a recovery-required failure instead of silently
showing an empty wallet or fabricating a migration; the user must restore from
their recovery phrase through the real import flow.

- iOS uses a non-synchronizing, this-device-only Keychain accessibility class.
- Android pins RSA-OAEP key wrapping and AES-GCM data encryption in a dedicated
  namespace, keeps crash-safe algorithm migration enabled, and uses
  `resetOnError: false`; app backup and device transfer are disabled. Plugin
  10.3.1 requires the migration path to establish algorithm markers on a clean
  first install. Optimized releases remove dependency Android log calls, while
  debug/profile builds retain local migration diagnostics.
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
`UTEXO_USDT_ASSET_ID` and its integer precision through
`UTEXO_USDT_PRECISION`. Both must be present and valid or both USDT payment
routes fail closed as unavailable. Stable navigation carries only the product
target (`usdt-onchain` or `usdt-lightning`); the repository resolves that
untrusted identifier back to deployment-owned contract metadata before any SDK
operation.

The SDK's accepted PKG-006 artifact-provenance constraint remains visible in
the app release report. Until that constraint is resolved upstream, this app
cannot make a truthful funds-bearing mainnet production claim.
