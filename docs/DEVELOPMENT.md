# Development Setup

This guide explains how to set up the Aster wallet development environment.

## First-Time Setup

### 1. Install Nix (if not already installed)

**macOS:**
```bash
sh <(curl -L https://nixos.org/nix/install) --daemon
```

Or using Homebrew:
```bash
brew install nix
```

**Linux:**
```bash
sh <(curl -L https://nixos.org/nix/install) --daemon
```

After installation, restart your terminal.

### 2. Install FVM

Install [FVM](https://fvm.app/) globally (once per machine), for example on macOS:

```bash
brew install fvm
```

On other platforms, follow the installation instructions in the FVM docs.

### 3. Setup Project

```bash
make shell
make fvm-setup
make bootstrap
```

## Platform launch without wallet services

For an isolated platform smoke check, use a fresh app-owned iOS 27 simulator or
Android 17 emulator and launch with reserved endpoints:

```sh
fvm flutter run -d <device-id> \
  --dart-define=ASTER_INDEXER_URL=https://indexer.aster.invalid \
  --dart-define=ASTER_RGB_PROXY_URL=https://proxy.aster.invalid
```

On macOS, use the locked CocoaPods bundle as described below. The app explicitly
uses CocoaPods for all native plugins while the RGB SDK lacks SwiftPM support.
When the active Xcode selection is Command Line Tools, scope
`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` to the build command.
Dart native build hooks can strip that variable. In that case, create this
ignored command wrapper and prefix the build command's `PATH` with its directory:

```sh
mkdir -p .dart_tool/xcode-bin
cat > .dart_tool/xcode-bin/xcrun <<'SH'
#!/bin/sh
DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
export DEVELOPER_DIR
exec /usr/bin/xcrun "$@"
SH
chmod 700 .dart_tool/xcode-bin/xcrun
PATH="$PWD/.dart_tool/xcode-bin:$PATH" \
  DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  BUNDLE_FROZEN=true BUNDLE_PATH="$PWD/.bundle" \
  bundle exec fvm flutter build ios --simulator --debug --no-pub \
  --dart-define=ASTER_INDEXER_URL=https://indexer.aster.invalid \
  --dart-define=ASTER_RGB_PROXY_URL=https://proxy.aster.invalid
```

Install Bundler into a path without spaces if using a private gem installation;
its `RUBYOPT` bootstrap path must survive subprocess parsing. This wrapper and
command environment leave the system Xcode selection unchanged.
Stay at the welcome screen; wallet creation/import and existing wallet restore
are separate service qualification. These reserved endpoints prevent a fallback
to the SDK's default indexer/proxy. No local stack is needed for this check.

## Development Workflow

1. **Ensure FVM Flutter is installed (first time on a machine):**
   ```bash
   make fvm-setup
   ```
   This installs the Flutter version pinned in `.fvmrc` and wires it into the
   project before the Nix shell adds that path to `PATH`.

2. **Enter the development environment:**
   - **Without direnv (manual):**
     ```bash
     make shell
     ```
   - **With direnv (recommended):**
     1. Install direnv (once per machine), for example on macOS:
        ```bash
        brew install direnv
        ```
     2. Add the direnv hook to your shell config:
        - **If you use zsh** (default on recent macOS, add to `~/.zshrc`):
          ```zsh
          eval "$(direnv hook zsh)"
          ```
        - **If you use bash** (add to `~/.bashrc` or `~/.bash_profile`):
          ```bash
          eval "$(direnv hook bash)"
          ```
     3. Open a **new terminal**, then in the project root (only once):
        ```bash
        direnv allow
        ```

     After this, simply `cd` into the project directory and direnv will automatically load the Nix dev environment (equivalent to `make shell`), so IDE shortcuts and terminals launched from the project will use the correct toolchain and FVM Flutter.

3. **Run the app:**
   ```bash
   make run-ios IOS_SIMULATOR_ID=<simulator-udid>
   # Or: make run-android ANDROID_DEVICE_ID=<emulator-or-device-id>
   ```

### Wallet lifecycle while debugging

Use Flutter hot reload (`r`) for normal UI iteration. The pinned native wallet
SDK does not yet support Flutter hot restart (`R`): hot restart replaces Dart
without detaching the native plugin, so the previous process-owned RLN node
cannot be adopted by the new isolate through the SDK's public API. If an
isolate restart is needed, quit the current run with `q` and run the same
explicit `make run-ios` or `make run-android` command again. This preserves the
wallet store and verifies the real cold-open path.

Never work around this by clearing app data, deleting the wallet directory,
guessing native node IDs, or adding an app-private platform channel. Those
actions either destroy useful recovery evidence or break the SDK ownership
boundary. The release app is not affected by Flutter's development-only hot
restart command; ordinary process relaunch is covered by the persisted-wallet
restore path.

## Linting and Code Style

Formatting and static analysis run **on every commit** (via a git hook) and **on every push/PR** (via CI).

### One-time: install git hooks

From the project root:

```bash
./scripts/install-git-hooks.sh
```

After this, each `git commit` verifies formatting, regenerates ignored
generated sources, runs analysis with every diagnostic fatal, validates fresh
Dart API documentation, architecture, design-system and barrel boundaries, and
verifies the production tracker inventory. The hook rejects unstaged tracked
changes and untracked non-ignored files before lint, then proves neither the
staged tree nor those inputs changed during the gate. This prevents a passing
working tree from masking different bytes in the commit. Commit or otherwise
separate unrelated work before invoking `git commit`; ignored local overrides
and generated/build outputs do not violate this check.

Repository-owned shell entrypoints execute external commands through
`scripts/bounded-command.sh`. The helper prefers the checkout's
`.fvm/flutter_sdk` Dart VM. On a source-only CI checkout, it accepts only an
absolute `FLUTTER_ROOT` whose canonical `bin/cache/flutter.version.json`
contains exactly one `frameworkVersion` matching `.fvmrc`; missing, duplicate,
malformed, or differently versioned metadata fails closed. Ambient `PATH`
discovery is deliberately unsupported. The selected trusted VM delegates to
the sole process-tree owner in `tool/bounded_process.dart`; do not invoke the
helper directly or add raw `git`, `fvm`, Android, Java, Bundler, or simulator
subprocesses to a script. Quick operations use a 120-second/8 MiB-per-stream
profile, artifact inspection uses 10 minutes/16 MiB, and builds or platform
tests use one hour/64 MiB. A limit, malformed UTF-8 response, launch failure, or
deadline fails the owning command and terminates its remaining descendants.
Choose the narrowest existing profile that covers the operation; changing a
limit is a reviewed tool-policy change with fault tests, not an inline escape.

### Manual commands

- `make format` - Format Dart code
- `make format-check` - Verify formatting without changing files
- `make analyze` - Run static analysis with warnings and infos fatal
- `make docs` - Generate fresh API docs and fail on warnings or broken links
- `make verify-generated` - Regenerate ignored generated Dart sources
- `make verify` - Verify architecture, design-system, barrel, and tracker policy
- `make verify-architecture` - Verify dependency and adapter boundaries directly
- `make verify-design-system` - Verify semantic UI token boundaries directly
- `make verify-barrels` - Verify barrel boundaries directly
- `make lint` - Run all pre-commit gates; ignored generated sources may refresh

### Android Release Builds

Release artifacts require one ignored, reviewed, non-secret JSON manifest. See
`config/README.md`, copy `config/release.example.json`, replace every
placeholder, and use only the owned targets:

```bash
make android-release-bundle \
  RELEASE_CONFIG=config/release.internal.local.json \
  RELEASE_AUDIENCE=internal-beta
make android-release-apks \
  RELEASE_CONFIG=config/release.internal.local.json \
  RELEASE_AUDIENCE=internal-beta
```

Flutter issue [169336](https://github.com/flutter/flutter/issues/169336)
causes a no-Pub Release build to reuse the development plugin registrant. The
owned `prepare-android-release` prerequisite removes inherited Flutter/Gradle
output, resolves only the committed lock, runs Flutter's config-only
workaround, then rejects any `pubspec.lock` or normalized package-graph drift,
any development plugin in the Release registrant, and any missing production
registration. Artifact compilation resumes with `--no-pub`.

The package verifiers compare the APK/AAB application ID, version name, and
version code with `android/gradle.properties` and `pubspec.yaml`. Flutter
intentionally encodes the ABI in split APK version codes (`1000 + base` for
armeabi-v7a, `2000 + base` for arm64-v8a, and `4000 + base` for x86_64); the
AAB retains the base code. The toolchain gate verifies this mapping against the
executing pinned Flutter source. Do not replace this sequence with a direct
`flutter build` command or interpret a valid split code as the source build
number.

Each AAB and split APK must also remain below its reviewed regression budget.
Verification prints the exact artifact byte count and streamed SHA-256 digest.
The current SDK `0.2.0-beta.2` Git pin reuses the derived 16 KiB RLN
artifact published in `0.2.0-beta.1`. The published RLN 0.17 AAR passes
SDK-level ELF, APK ZIP alignment and native signer checks.
Aster's Debug APK now passes all 25 native ELF checks and 16 KiB ZIP alignment,
and launches on Android 17 with 16 KiB pages and compatibility fallback disabled.
A direct load/health check of the RLN library extracted from that same APK also
passes. SDK-004's exact release AAB/split-APK qualification and PKG-006
provenance remain open; local funded results are recorded in
`SHARED_WALLET_QUALIFICATION.md`. The historical beta.1 pin restores with an
empty Git cache and an unchanged lockfile; a separate empty Gradle dependency cache
downloads the published AAR over HTTPS and verifies its pinned size and SHA-256.
See the [beta release](https://github.com/UTEXO-Protocol/flutter-sdk/releases/tag/v0.2.0-beta.1).
Dependency restoration and a size/digest pass do not satisfy these separate
release gates.

### iOS Release Archives

Build unsigned archive evidence through the same manifest contract:

```bash
make ios-release-archive \
  RELEASE_CONFIG=config/release.internal.local.json \
  RELEASE_AUDIENCE=internal-beta
```

For a release-owned signed export, keep ExportOptions outside Git and run:

```bash
make ios-release-ipa \
  RELEASE_CONFIG=config/release.public.local.json \
  RELEASE_AUDIENCE=public-distribution \
  IOS_EXPORT_OPTIONS_PLIST=ios/ExportOptions.public.local.plist
```

Before Xcode runs, the signed target rejects symlinked or unreviewed export
options and requires an explicit team, bundle identity, distribution method,
and source-owned version/build policy. The archive gate compares bundle/version
identity with committed source, requires the iPhone-only Aster metadata, the
exact approved privacy declarations, and the exact local-network-only App
Transport Security policy, measures installed size, and hashes the app
executable. The signed path preflights the actual IPA
for traversal, links, special nodes, path collisions, ambiguous Payloads, and
expansion limits before extraction. It then re-verifies identity, privacy,
installed size, executable digest, embedded provisioning, and the code
signature from the exported package itself. It cannot approve final
identifiers, certificate ownership, provisioning ownership, or export
classification; those remain release-owner inputs.

### CI (GitHub Actions)

On push to `main` and on pull requests, the **Quality** workflow runs on the
pinned Ubuntu 24.04 runner image:

- `dart format --output=none --set-exit-if-changed .`
- `dart run build_runner build`
- `flutter analyze --fatal-warnings --fatal-infos`
- `flutter test`
- `dart run tool/verify_dartdoc.dart`
- `dart run tool/verify_barrel_exports.dart`
- `dart run tool/verify_architecture.dart`
- `dart run tool/verify_design_system.dart`
- `dart run tool/verify_repository_governance.dart`
- `dart run tool/verify_release_configuration_contract.dart`
- `dart run tool/verify_production_tracker.dart`

The separate **Platform compile** workflow uses immutable action commits,
Java 21, Flutter 3.47.7, Ruby 3.4.10, Bundler 4.0.10, and the locked dependency
graphs to compile Android Debug plus iOS Simulator Debug and run Android host
tests. It consumes no release configuration, signing secret, or network stack,
so it proves host integration only. Physical/runtime and signed-candidate gates
remain local release evidence. After the Android compile and host tests, an
always-run root `flutter clean` releases transient build outputs before action
post-steps archive the reviewed Flutter and Gradle caches. Governance policy
enforces that ordering so cache maintenance cannot replace or precede the test.

Fix failures locally with `make format`, `make lint`, and `make test`, then
commit and push again.

## Available Commands

Targets that compile, analyze, document, test, or inspect application Dart code
depend on `verify-generated`. From a clean checkout they first resolve the exact
committed Pub lockfile and regenerate ignored Riverpod/build-runner sources.
Within one aggregate Make invocation, dependency resolution and generation each
run once. Do not bypass this graph with raw `--no-pub` Flutter commands.

- `make shell`      - Enter Nix development environment
- `make fvm-setup`  - Install/use Flutter via FVM for this project (uses version from `.fvmrc`)
- `make bootstrap`  - Initial project setup (clean, pub get, build_runner)
- `make clean`      - Clean Flutter build artifacts
- `make dependencies` - Resolve exactly the committed Pub dependency graph
- `make build`      - Run build_runner to generate code
- `make watch`      - Run build_runner in watch mode
- `make run-ios IOS_SIMULATOR_ID=<id>` - Run iOS through locked CocoaPods
- `make run-android ANDROID_DEVICE_ID=<id>` - Run Android on an explicit device
- `make test`       - Run Flutter tests
- `make format`     - Format Dart code
- `make format-check` - Verify formatting without changing files
- `make analyze`    - Run static analysis with all diagnostics fatal
- `make docs`       - Generate and validate fresh Dart API docs
- `make verify-generated` - Regenerate ignored generated Dart sources
- `make verify`     - Verify repository invariants
- `make verify-architecture` - Verify dependency and adapter boundaries
- `make verify-design-system` - Verify semantic UI token boundaries
- `make verify-barrels` - Verify barrel boundaries
- `make lint`       - Run all pre-commit quality gates
- `make help`       - Show all available commands

## Troubleshooting

**Flutter Doctor:**
Check your setup:
```bash
flutter doctor   # after FVM is set up
```

**Clean Build:**
If you encounter build issues:
```bash
make clean
make bootstrap
```

## Development Environment

This project uses [Nix Flakes](https://nixos.wiki/wiki/Flakes) to pin the native
development prerequisites. The environment includes:

- Android SDK platform 37.0, build tools 36.0.0, and platform tools 36.0.0
- Android NDK 28.2.13676358, matching Flutter 3.47.7
- Gradle 9.3.1, Android Gradle Plugin 9.1.1, and Kotlin 2.4.0
- Java JDK 21
- CocoaPods 1.16.2 through Bundler 4.0.10 (macOS only)

The Aster app module applies AGP 9.1's built-in Kotlin plugin directly. The
global `android.builtInKotlin=false` and `android.newDsl=false` flags remain a
temporary dependency compatibility boundary: hosted Flutter plugins and the
immutable UTEXO SDK still apply legacy KGP. Do not restore `kotlin-android` in
`android/app`; remove the global opt-outs only after every dependency module
has migrated and the native and platform matrices pass.

The flake deliberately does not install Flutter or Dart. It places the
project-local `.fvm/flutter_sdk/bin` on `PATH`; FVM remains the sole source of
truth for Flutter 3.47.7 and Dart 3.13.5. Run `make fvm-setup` before entering
the shell, and do not use a separately installed Dart SDK for app generation,
analysis, tests, or documentation.

Flutter itself is managed via [FVM](https://fvm.app/) and pinned per project
using `.fvmrc` (`flutter: 3.47.7`). This keeps the Flutter version
consistent across developers without relying on the Nix store.

### Locked iOS toolchain

Do not run a host-global `pod install` for repository evidence. `Gemfile.lock`
pins CocoaPods and its complete Ruby dependency graph, including gem checksums.
Install it into the ignored checkout-local `.bundle/` directory before iOS
work:

```sh
make ios-dependencies
```

The target requires Bundler 4.0.10, enables frozen lockfile mode, and fails
instead of changing the committed resolution. Repository-owned iOS build and
integration commands execute Flutter through `bundle exec`, so Flutter's
implicit CocoaPods invocation uses CocoaPods 1.16.2 from this lock. Use the
owned Make targets for release evidence rather than invoking `pod`, `flutter
build ios`, or iOS integration tests directly.

### Verified Android dependencies

The Gradle wrapper validates the Gradle 9.3.1 distribution against its reviewed
upstream SHA-256 digest. Gradle also enforces the committed
`android/gradle/verification-metadata.xml` checksums for the complete owned
Debug, Profile, Release, bundle, and native-test dependency graph. A new or
changed Maven artifact must fail first; update verification metadata only in a
dedicated dependency-review change and inspect every added component and
checksum before committing it. Release artifact inspection also re-hashes the
exact cached AGP module metadata, AAPT schema, Bundletool, and protobuf JARs
against that catalog through bounded streaming reads immediately before parsing
or executing them. Exact names and versions alone are not accepted as
release-verifier provenance, and an oversized cache entry fails before hashing.

Because Gradle plugin graphs can differ by host, `make android-native-test`
builds the complete Debug APK before JVM tests and the Ubuntu platform workflow
repeats that build. A checksum discovered only on another host must be verified
against independent canonical repositories before it is added; no trust
exception or generated bulk acceptance is permitted.

Android archive policy is owned by Java `ZipFile` boundaries, not shell parsing
of line-oriented ZIP listings or wildcard extraction. Native verification
rejects duplicate, absolute, control-character, backslash, dot-segment, nested,
or otherwise malformed native paths; proves the exact expected ABI set and
required runtime libraries; bounds compressed, expanded, per-entry, and native
payload sizes; and extracts only validated basenames into an empty owned
temporary directory before ELF inspection.

## Local SDK Development

The committed dependency always points to the immutable public UTEXO protocol SDK
commit. For temporary SDK development only, see
`docs/architecture/SDK_INTEGRATION.md`. Never commit a path dependency or a
`dependency_overrides` entry.

## Local Application Identity

Non-release builds are intentionally separate installed applications and own
separate sandbox, preferences, secure-storage, and wallet-directory state:

| Mode | Android application ID / iOS bundle ID |
| --- | --- |
| Debug | `com.example.asterdev.debug` |
| Profile | `com.example.asterdev.profile` |
| Release candidate | `com.example.asterdev` |

The base release identifier is still provisional under DEC-006. Preserve the
suffix contract when the release owner supplies its final identifier. Never
remove a release candidate to work around `INSTALL_FAILED_VERSION_DOWNGRADE`;
use the isolated Debug or Profile package instead.

## Wallet Service Configuration

The default development build is regtest and cannot become mainnet
accidentally. Release builds consume exactly one validated file through
`--dart-define-from-file`; see `config/README.md`. The validator requires every
technical service and RGB identity key, sorted keys, visible ASCII, and
TLS-protected public DNS endpoints. Unknown keys and placeholders fail closed.
Never place LSP, VSS, Bitcoin RPC, provider, or other credentials in that file:
compile-time values are recoverable from the application binary.

The immutable SDK's default regtest indexer uses local plain HTTP. That default
is accepted only by Debug and Profile builds. Release builds reject HTTP,
unencrypted Electrum (`tcp`), and unencrypted RGB transport (`rpc`) before
native wallet creation, including on loopback and `10.0.2.2`. A Release build
for regtest therefore requires explicit TLS-protected service endpoints; an
unconfigured Release build fails closed instead of silently relying on a
transport Android packaging already forbids.

RGB USDT requires both `ASTER_USDT_ASSET_ID` and
`ASTER_USDT_PRECISION` for the selected environment. These are non-secret
deployment identity values and must be supplied together. When either is
missing, the app keeps both USDT rails visible but unavailable; it never infers
an asset contract or decimal precision from the `USDT` ticker.

## Market Data Configuration

Debug and profile builds use CoinGecko's keyless public API when no market
endpoint is supplied. That pool is intended for testing and prototyping, is
dynamically rate-limited, and is not a production reliability contract. Home's
provider credit was removed following the author's visual review. This does not
waive attribution obligations: an approved placement or contractual exception
must be resolved before distribution under the existing FIAT-002 release gate.
See CoinGecko's
[keyless API policy](https://docs.coingecko.com/docs/keyless-public-api) and
[API terms](https://www.coingecko.com/en/api_terms).

Release builds fail closed unless `ASTER_MARKET_API_BASE_URL` identifies a
deployment-owned public HTTPS proxy that preserves the required CoinGecko API
paths. The proxy owner must hold the appropriate data/API rights, keep provider
credentials server-side, enforce its own abuse and availability policy, and
return no user-specific or secret data. Direct CoinGecko hosts, insecure or
private hosts, credentials, query strings, and fragments are rejected. Never
place a CoinGecko or proxy API key in `--dart-define`; mobile binaries cannot
protect it.

Public-distribution manifest validation requires the approved market proxy in
addition to technical wallet services. Reserved example/invalid hosts and
direct CoinGecko API hosts are deliberately rejected; a release owner must
supply the real approved public host.

Settings support, legal, and social destinations are optional deployment
configuration. Omitted values render as disabled actions; the app never ships
a guessed URL or enabled no-op command.

| Define | Settings action |
| --- | --- |
| `ASTER_SUPPORT_URL` | Contact Support |
| `ASTER_TERMS_URL` | Terms of Service |
| `ASTER_PRIVACY_URL` | Privacy Policy |
| `ASTER_TWITTER_URL` | Twitter |
| `ASTER_TELEGRAM_URL` | Telegram |
| `ASTER_INSTAGRAM_URL` | Instagram |

Each configured destination must be a bounded public HTTPS URL without
embedded credentials, a query, or a fragment. Literal IPs, localhost,
single-label intranet hosts, legacy numeric address aliases such as `127.1`,
and reserved non-public suffixes are rejected.
These values are compiled into the application and must never contain secrets.
Settings obtains the installed version and build number from platform package
metadata; release code must not hardcode that display value.

An unrelated Compose project named `rgb-lightning-node-perf-lab` owns host
ports `18443`, `50001`, and `3000` and persistent external data. App development
must not stop, reset, recreate, inspect, or reuse that project or its data. Any
app-owned regtest environment must use a distinct Compose project, distinct
bind mounts, and different published ports. Do not run that project's
`regtest.sh`.

## Resources

- [Flutter Documentation](https://docs.flutter.dev/)
- [Nix Flakes Documentation](https://nixos.wiki/wiki/Flakes)
- [Direnv Documentation](https://direnv.net/)
