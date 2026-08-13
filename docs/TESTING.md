# Testing And Release Evidence

Tests prove contracts; they do not make an unconfigured dependency or missing
product decision disappear.

## Host Gates

```sh
make lint
make test
```

The lint gate checks formatting, regenerates ignored generated sources, runs
fatal analysis, generates fresh API docs with link validation, validates barrel
boundaries, and verifies the file tracker. The test suite covers domain math,
repository failures, runtime ordering, retry policy, ViewModels, widgets,
routing, accessibility semantics, layout bounds, reduced motion, and goldens.

Coverage is a diagnostic. New assertions must target behavior and failure
boundaries; assertion-free tests or tests added only to raise a percentage are
not accepted.

## Native And Platform Gates

An exact release candidate additionally requires:

- iOS XCTest and storage integration tests
- Android bridge/storage tests
- clean iOS Simulator and Android release builds
- install/launch smokes for the same source commit and architecture
- configured-wallet create/import, restart, lifecycle, send/receive, and
  funded/unfunded regtest evidence where deployment services exist
- VoiceOver and TalkBack traversal on physical devices
- physical-device haptic, camera, gallery, and secure-screen behavior
- profile-mode launch/frame/memory/leak measurements

Simulator and host tests cannot qualify physical haptics, camera hardware,
screen readers, signing, or a funds-bearing native supply chain.

Run the app-owned iOS storage/file-policy integration contract with:

```sh
make ios-storage-test IOS_SIMULATOR_ID=<simulator-udid>
```

Use this target instead of invoking the iOS integration test directly. Flutter
temporarily points ignored iOS build settings at a disposable test listener;
the owned wrapper preserves the test result and restores the ordinary
`lib/main.dart` simulator target on every exit so later Xcode builds remain
reproducible.

## Profile Performance Gate

Run the repeatable presentation workload on an otherwise idle app-owned
Android emulator:

```sh
fvm flutter drive --no-dds \
  --driver=test_driver/integration_test.dart \
  --target=integration_test/presentation_performance_test.dart \
  -d <device-id> \
  --profile
```

`--no-dds` is required by Flutter's `watchPerformance` VM-service contract.
The test warms image, shader, route, and BIP39 caches before measuring. It then
separately measures six onboarding route push/pop cycles and one normal
recovery-word PageView cycle, requires at least 60 frames per measured
workload, and rejects more than 5% of build or raster frames over Flutter's
16 ms budget. Four additional PageView cycles run outside the frame sample to
stress retained memory; the gate rejects more than 32 MiB retained RSS growth
across the full warm route/page workload. Raw results are written to ignored
`build/integration_response_data.json`.

Before accepting a result, record host load and memory pressure. A sample
contaminated by OS indexing, thermal pressure, emulator startup, or unrelated
process load is invalid evidence and must be rerun. Emulator numbers are
regression baselines only; physical-device profile and leak evidence remains a
separate release gate.

## Test Data

Production code has no fake balances, transactions, success delays, sample
destinations, or mock wallet behavior. Test-only fakes live under `test/` or
`integration_test/`, use synthetic non-funds-bearing values, and enter the app
through provider or app-owned interface overrides.

## Exact-Candidate Rule

Evidence records the full commit, toolchain, command, device/OS/ABI, artifact
size and digest, result, and constraints. Any source change makes prior runtime
or performance evidence historical. The current ledger is
`docs/PRODUCTION_REFACTOR_TRACKER.md`; the closeout procedure is
`docs/release/RELEASE_CHECKLIST.md`.
