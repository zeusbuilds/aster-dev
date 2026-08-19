# Aster Wallet

Aster is a Flutter wallet for Bitcoin, RGB USDT, and Lightning. It is powered
by the UTEXO protocol through the public `rgb_sdk_flutter` API, pinned to
immutable commit `3dd82e23d80bb4bb6a2d2526c6c6741ac1ea1236`, and uses Riverpod MVVM.

## Release Status

This repository is undergoing release-candidate hardening. It is not currently
eligible for a funds-bearing mainnet release.

- The SDK's accepted PKG-006 native-artifact provenance constraint permits
  development and internal beta, not a mainnet production claim.
- Final application identifiers, signing ownership, authentication for secret
  disclosure, screen-capture policy, and store privacy/export declarations
  remain product, security, or release-owner decisions.
- The pinned SDK's Android native library is still 4 KiB ELF-aligned. Android
  16 KiB page-size qualification and a compatible SDK artifact remain blocked.
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

The wallet models asset, payment rail, and chain environment separately:

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

Flutter `3.47.0` and Dart `3.13.0` are pinned. Flutter 3.47.0 was the latest
stable release in Flutter's official archive when verified on 2026-08-13.

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
