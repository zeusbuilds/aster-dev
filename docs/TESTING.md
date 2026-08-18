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
- built iOS root privacy-manifest inspection and approved-reason validation
- install/launch smokes for the same source commit and architecture
- configured-wallet create/import, restart, lifecycle, send/receive, and
  funded/unfunded regtest evidence where deployment services exist
- VoiceOver and TalkBack traversal on physical devices
- physical-device haptic, camera, gallery, and secure-screen behavior
- profile-mode launch/frame/memory/leak measurements

Simulator and host tests cannot qualify physical haptics, camera hardware,
screen readers, signing, or a funds-bearing native supply chain.

Run the app-host native suites before their Flutter integration contracts:

```sh
make ios-native-test IOS_SIMULATOR_ID=<simulator-udid>
make android-native-test
```

The iOS target performs an Xcode clean before XCTest so a prior Flutter
integration listener cannot leave stale products in candidate evidence. Both
native targets first run Flutter's `--config-only` platform bootstrap, so they
also work from a source-only checkout where Riverpod outputs, the Gradle
wrapper, CocoaPods, and Flutter host files are correctly ignored. Locked Pub
resolution and deterministic code generation happen before native compilation.
The iOS targets also require Bundler 4.0.10 and execute every Flutter/CocoaPods
path through the checksummed CocoaPods 1.16.2 graph in `Gemfile.lock`. Android
builds verify both the Gradle distribution digest and every resolved external
artifact against committed dependency-verification metadata.
The iOS suite executes the filesystem policy directly, including insecure
ancestors, hard-link aliases, bounds, collisions, byte preservation, and
channel-session invalidation. Android unit tests stress concurrent admission,
exactly-once session state, invalidation, and the same `st_nlink == 1` identity
predicate used by production. The Android integration contract additionally
accepts only an explicit platform `Permission denied`/`Operation not permitted`
when API-level sandbox policy prevents constructing a hard link; any other
construction failure fails the test.

Android release APK and AAB verification rejects every signed candidate unless
`UTEXO_RELEASE_CERT_SHA256` identifies the one approved certificate. With no
approved fingerprint configured, only unsigned candidate artifacts pass; they
are build evidence and cannot be distributed. An AAB is signed only when every
non-signature payload entry verifies against exactly one common certificate.
Partially signed, modified, duplicate-entry, or multi-signer bundles fail even
when an inspectable certificate matches the configured fingerprint.
Both JAR-signature and native-library inspection use structured ZIP APIs with
entry-name, duplicate, entry-count, compressed-size, per-entry, and aggregate
expansion limits. They do not make security decisions from `unzip -Z1` output.

Build Android Release artifacts only through `make android-release-bundle` or
`make android-release-apks`. Their guarded preparation step works around
Flutter issue 169336 while proving the committed lockfile and normalized
package graph remain unchanged and that the generated registrant contains
exactly production method-channel plugins. A direct no-Pub Release build after
development tooling can fail or compile the wrong plugin surface and is not
release evidence. Preparation begins with `flutter clean`, then exact locked
resolution, so prior build-mode output cannot become candidate evidence.

Every release package verifier also compares packaged application ID, version
name, and version code with committed source. Split APK codes include Flutter's
ABI prefix (`1xxx` armeabi-v7a, `2xxx` arm64-v8a, `4xxx` x86_64); the AAB uses
the base code from `pubspec.yaml`. The executable toolchain policy verifies
that mapping against the pinned Flutter Gradle plugin before accepting it.

Directly distributed signed APKs must also use APK Signature Scheme v2 or v3.
JAR/v1-only signing is rejected even when its certificate fingerprint matches.
The local fault matrix uses only the disposable Android debug key and never
produces a release artifact:

```sh
make verify-android-apk-signature-policy
```

The same release verifiers inspect every packaged ELF LOAD segment and the APK
ZIP alignment. The AAB gate also parses `BundleConfig.pb` with the exact
Bundletool/protobuf versions resolved by AGP, re-hashes those JARs against the
committed Gradle catalog with bounded streaming reads at point of use, and
requires `PAGE_ALIGNMENT_16K`.
A passing package gate therefore requires a power-of-two ELF alignment,
congruent LOAD file/virtual addresses, 16 KiB alignment in both packaging and
every 64-bit native dependency, plus GNU RELRO where dynamic relocations exist.
Before ELF inspection, the native archive boundary proves the exact expected
ABI set, requires `libapp.so`, `libflutter.so`, and
`librgb_lightning_node.so` in every ABI, rejects unsafe or nested paths, and
transactionally extracts only validated `.so` basenames beneath an owned empty
directory. Additional plugin libraries are allowed only in that same exact
`<native-root>/<abi>/<basename>.so` shape.
The current pinned wallet SDK fails this gate at `librgb_lightning_node.so`;
see `SDK-004`. After an immutable compatible SDK revision is approved, rerun
both artifact gates and a real 16 KiB emulator or device smoke before
qualification.

Run the app-owned iOS storage/file-policy integration contract with:

```sh
make ios-storage-test IOS_SIMULATOR_ID=<simulator-udid>
```

Run the equivalent Android contract with the release-preserving wrapper:

```sh
make android-storage-test ANDROID_DEVICE_ID=<emulator-or-device-id>
```

Do not invoke raw `flutter drive` for Android integration. Flutter 3.47 does
not account for the build-type application-ID suffix when stopping the app and
can target the unsuffixed release package. The wrapper keeps Flutter from
stopping the app, force-stops only `com.example.asterdev.debug`, verifies the
actual APK identity, and proves any pre-existing release package is unchanged.
On every post-launch exit it force-stops only that debug identity, rechecks the
release path, and preserves the original drive failure ahead of cleanup or
artifact diagnostics. It never uninstalls either package or erases developer
state.

Use this target instead of invoking the iOS integration test directly. Flutter
temporarily points ignored iOS build settings at a disposable test listener;
the owned wrapper preserves the test result, proves the unsuffixed candidate
bundle path is unchanged, requires the expected `.debug` application container
after a successful run, and restores the ordinary `lib/main.dart` simulator
target and installed Debug app on every exit so later development builds remain
reproducible. The in-process integration assertion, built-plist inspection, and
simulator-container check jointly prove the transient test used the isolated
debug identity without leaving the test-listener binary installed.

## Profile Performance Gate

Run the repeatable presentation workload on an otherwise idle app-owned
Android emulator:

```sh
make android-presentation-performance-test ANDROID_DEVICE_ID=<device-id>
```

This command treats `com.example.asterdev.profile` as disposable test state:
it clears that profile-only application before and after the run so an existing
wallet cannot redirect the benchmark away from onboarding. It never clears or
reinstalls the release or debug identities, verifies both remain installed at
the same package paths, verifies the built APK has the profile identity, and
rejects SwiftShader and other known software renderers. Start an app-owned
emulator with host graphics or use a hardware device; software-rendered frame
timings are not release evidence.
Do not replace the wrapper with a direct `flutter drive` command when recording
release evidence.

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
