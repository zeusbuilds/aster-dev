# Aster Wallet

Aster is a Flutter wallet for Bitcoin, RGB USDT, and Lightning. It is powered
by the UTEXO protocol through the public `rgb_sdk_flutter` API, with SDK
`0.2.0-beta.3` pinned to immutable public Git commit
`518a056dbe4a525762322686ac90bed080b03e78`, and uses Riverpod MVVM.

## Release Status

This repository is undergoing release-candidate hardening. It is not currently
eligible for a funds-bearing mainnet release. The initial release scope is
password signing with mainnet Bitcoin and RGB on-chain operations. Lightning
and mainnet external signing are disabled at their release boundaries.

- The SDK's accepted PKG-006 native-artifact provenance constraint permits
  development and internal beta, not a mainnet production claim.
- Final application identifiers, signing ownership, authentication for secret
  disclosure, screen-capture policy, and store privacy/export declarations
  remain product, security, or release-owner decisions.
- The SDK candidate includes a derived 16 KiB RLN 0.17 artifact with passing
  native signer checks on both platforms. Aster's Debug APK passes all 25
  native ELF checks, 16 KiB ZIP alignment and startup on Android 17 with
  compatibility fallback disabled. SDK-004's exact release AAB/split-APK
  qualification remains open. Local funded wallet evidence is tracked in
  `docs/SHARED_WALLET_QUALIFICATION.md`.
- SDK [v0.2.0-beta.1](https://github.com/UTEXO-Protocol/flutter-sdk/releases/tag/v0.2.0-beta.1)
  and its derived Android AAR are published. The current beta.3 Git pin retains
  those native bytes. Historical empty-Git-cache evidence restores beta.1;
  an empty Gradle dependency cache
  downloads and verifies the release AAR over HTTPS.
- `1.0.0+1` is a provisional app version until release ownership defines the
  public version/build-number and upgrade policy.
- RGB USDT stays unavailable unless a deployment supplies a validated asset ID
  and precision for the selected environment.
- Release market estimates stay unavailable unless a deployment supplies an
  approved Aster-owned market proxy. CoinGecko's keyless pool is development
  only and no third-party API secret is embedded in the mobile binary.
- Swap has no execution backend and never simulates a quote or success.

The complete, evidence-backed status is maintained in
`docs/PRODUCTION_REFACTOR_TRACKER.md`.

## Product Model

The library and application domain model asset, payment rail, and chain
environment separately. The model includes the following rails; only on-chain
rails are in the initial mainnet release scope:

- Bitcoin on-chain
- Bitcoin Lightning
- RGB USDT on-chain
- RGB USDT Lightning

Amounts are integers in sats, millisats, or RGB smallest units. Ticker strings
and floating-point values are never monetary authority. Presentation combines
supported rails for portfolio and activity views while repositories preserve
their source identity. Fiat estimates use the selected ISO currency's integer
minor units and display their currency code to avoid ambiguous symbols.

## Architecture

The dependency direction is:

```text
View -> ViewModel -> Repository -> SDK/service/storage/network
```

`WalletRuntime` is the single app-owned native lifecycle owner.
`RgbWalletEngine` is the only adapter that holds the UTEXO SDK's
`UtexoWallet`; SDK DTOs do not cross that boundary. Repositories and ViewModels
use one typed `AppResult` / `AppFailure` contract, and feature UI does not call
plugins or infrastructure directly.

See `docs/architecture/ARCHITECTURE.md` and
`docs/architecture/SDK_INTEGRATION.md`.

## Setup

Prerequisites:

- FVM
- Python 3.9 or newer (`python3`) for bounded POSIX process supervision
- Xcode plus Bundler 4.0.10 for the locked CocoaPods 1.16.2 toolchain
- Android SDK and Java 21 for Android
- Nix and direnv are optional development-shell helpers

```sh
make fvm-setup
make bootstrap
make ios-dependencies # macOS only; installs the locked bundle under .bundle/
make run-ios IOS_SIMULATOR_ID=<simulator-udid>
# Or: make run-android ANDROID_DEVICE_ID=<emulator-or-device-id>
```

Flutter `3.47.7` and Dart `3.13.5` are pinned. Android builds compile and target
API 37 (Android 17). iOS builds use the installed Xcode 27 SDK and retain the
iOS 18.5 deployment minimum.

For complete setup, the reviewed release-manifest workflow, the optional
uncommitted local SDK override, and protected-regtest isolation, read
`docs/DEVELOPMENT.md`.

## Quality Gates

```sh
make lint
make test
```

`make lint` checks formatting, regenerates generated sources, runs analysis with
all diagnostics fatal, creates clean isolated Dart API docs, and validates
architecture, design, barrel, release-configuration, governance, and tracker
policy. GitHub also compiles unsigned Debug Android and iOS host integrations.
Native runtime, signing, configured services, physical devices, Android package
and 16 KiB checks, and profile measurements remain exact-candidate release
gates; green compile CI is not platform qualification.

See `docs/TESTING.md` and `docs/release/RELEASE_CHECKLIST.md`.

## Security

Never place mnemonics, database passwords, credentials, tokens, invoices, or
live wallet paths in issues, logs, screenshots, build defines, or test fixtures.
Read `docs/SECURITY.md` before changing storage, lifecycle, networking,
onboarding, disclosure, or logging behavior.

## Documentation

- System reset and cross-project handoff: `docs/handoff/SYSTEM_CONTEXT.md`
- Backup/restore checklist: `docs/handoff/RESET_AND_RESTORE.md`
- New Codex task context: `docs/handoff/RESUME_PROMPT.md`
- Development setup: `docs/DEVELOPMENT.md`
- Architecture: `docs/architecture/ARCHITECTURE.md`
- SDK integration: `docs/architecture/SDK_INTEGRATION.md`
- Network reliability: `docs/architecture/NETWORK_RELIABILITY.md`
- Barrel exports: `docs/architecture/BARREL_EXPORTS.md`
- Presentation systems: `docs/design/PRESENTATION_SYSTEMS.md`
- Typography and tokens: `docs/design/TYPOGRAPHY_USAGE.md`
- Security: `docs/SECURITY.md`
- Testing: `docs/TESTING.md`
- Release configuration: `config/README.md`
- Regtest isolation: `docs/REGTEST.md`
