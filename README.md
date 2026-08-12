# UTEXO Wallet

UTEXO is a Flutter wallet for Bitcoin, RGB USDT, and Lightning. The app uses
Riverpod MVVM and the public `rgb_sdk_flutter` API pinned to immutable commit
`3dd82e23d80bb4bb6a2d2526c6c6741ac1ea1236`.

## Release Status

This repository is undergoing release-candidate hardening. It is not currently
eligible for a funds-bearing mainnet release.

- The SDK's accepted PKG-006 native-artifact provenance constraint permits
  development and internal beta, not a mainnet production claim.
- Final application identifiers, signing ownership, authentication for secret
  disclosure, legacy-wallet recovery, and screen-capture policy remain product
  or security decisions.
- RGB USDT stays unavailable unless a deployment supplies a validated asset ID
  and precision for the selected environment.
- Swap has no execution backend and never simulates a quote or success.

The complete, evidence-backed status is maintained in
[PRODUCTION_REFACTOR_TRACKER.md](https://github.com/zeusbuilds/aster-dev/blob/main/docs/PRODUCTION_REFACTOR_TRACKER.md).

## Product Model

The wallet models asset, payment rail, and chain environment separately:

- Bitcoin on-chain
- Bitcoin Lightning
- RGB USDT on-chain
- RGB USDT Lightning

Amounts are integers in sats, millisats, or RGB smallest units. Ticker strings
and floating-point values are never monetary authority. Presentation combines
supported rails for portfolio and activity views while repositories preserve
their source identity.

## Architecture

The dependency direction is:

```text
View -> ViewModel -> Repository -> SDK/service/storage/network
```

`WalletRuntime` is the single app-owned native lifecycle owner.
`RgbWalletEngine` is the only adapter that holds `UtexoWallet`; SDK DTOs do not
cross that boundary. Repositories and ViewModels use one typed `AppResult` /
`AppFailure` contract, and feature UI does not call plugins or infrastructure
directly.

See [ARCHITECTURE.md](https://github.com/zeusbuilds/aster-dev/blob/main/docs/architecture/ARCHITECTURE.md)
and [SDK_INTEGRATION.md](https://github.com/zeusbuilds/aster-dev/blob/main/docs/architecture/SDK_INTEGRATION.md).

## Setup

Prerequisites:

- FVM
- Xcode and CocoaPods for iOS
- Android SDK and Java 21 for Android
- Nix and direnv are optional development-shell helpers

```sh
make fvm-setup
make bootstrap
make run
```

Flutter `3.44.9` and Dart `3.12.2` are pinned. Flutter 3.44.9 was the latest
stable patch when this release-candidate pass began on 2026-08-12.

For complete setup, build defines, the optional uncommitted local SDK override,
and protected-regtest isolation, read
[DEVELOPMENT.md](https://github.com/zeusbuilds/aster-dev/blob/main/docs/DEVELOPMENT.md).

## Quality Gates

```sh
make lint
make test
```

`make lint` checks formatting, regenerates generated sources, runs analysis with
all diagnostics fatal, creates clean isolated Dart API docs, validates barrel
boundaries, and checks tracker inventory. iOS/Android builds, native tests,
runtime smokes, and profile measurements remain exact-candidate release gates;
a host-only green CI job is not platform qualification.

See [TESTING.md](https://github.com/zeusbuilds/aster-dev/blob/main/docs/TESTING.md)
and [RELEASE_CHECKLIST.md](https://github.com/zeusbuilds/aster-dev/blob/main/docs/release/RELEASE_CHECKLIST.md).

## Security

Never place mnemonics, database passwords, credentials, tokens, invoices, or
live wallet paths in issues, logs, screenshots, build defines, or test fixtures.
Read [SECURITY.md](https://github.com/zeusbuilds/aster-dev/blob/main/docs/SECURITY.md)
before changing storage, lifecycle, networking, onboarding, disclosure, or
logging behavior.

## Documentation

- [Development setup](https://github.com/zeusbuilds/aster-dev/blob/main/docs/DEVELOPMENT.md)
- [Architecture](https://github.com/zeusbuilds/aster-dev/blob/main/docs/architecture/ARCHITECTURE.md)
- [SDK integration](https://github.com/zeusbuilds/aster-dev/blob/main/docs/architecture/SDK_INTEGRATION.md)
- [Network reliability](https://github.com/zeusbuilds/aster-dev/blob/main/docs/architecture/NETWORK_RELIABILITY.md)
- [Barrel exports](https://github.com/zeusbuilds/aster-dev/blob/main/docs/architecture/BARREL_EXPORTS.md)
- [Presentation systems](https://github.com/zeusbuilds/aster-dev/blob/main/docs/design/PRESENTATION_SYSTEMS.md)
- [Typography and tokens](https://github.com/zeusbuilds/aster-dev/blob/main/docs/design/TYPOGRAPHY_USAGE.md)
- [Security](https://github.com/zeusbuilds/aster-dev/blob/main/docs/SECURITY.md)
- [Testing](https://github.com/zeusbuilds/aster-dev/blob/main/docs/TESTING.md)
- [Regtest isolation](https://github.com/zeusbuilds/aster-dev/blob/main/docs/REGTEST.md)
