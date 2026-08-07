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

When developing the SDK and app together, add this temporary block to the local
`pubspec.yaml`:

```yaml
dependency_overrides:
  rgb_sdk_flutter:
    path: ../rgb-sdk-flutter
```

Run `fvm flutter pub get` after adding or removing the override. Before any
commit, remove the block, resolve dependencies again, and confirm that
`pubspec.lock` contains the immutable Git `resolved-ref` above. The local
override is never committed and is not supported for release evidence.

## Ownership Boundary

Exactly one app-owned runtime will own `UtexoWallet` creation, initialization,
unlocking, synchronization, shutdown, reinitialization, and destruction. UI
and ViewModels depend on app repositories and typed app models; they never call
the SDK, native bridge, storage, or platform plugins directly.

The SDK's accepted PKG-006 artifact-provenance constraint remains visible in
the app release report. Until that constraint is resolved upstream, this app
cannot make a truthful funds-bearing mainnet production claim.
