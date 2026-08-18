# Development Setup

This guide explains how to set up the UTEXO wallet development environment.

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
verifies the production tracker inventory.

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

Use only the owned targets:

```bash
make android-release-bundle
make android-release-apks
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

### CI (GitHub Actions)

On push to `main` and on pull requests, the **Dart** workflow runs:

- `dart format --output=none --set-exit-if-changed .`
- `dart run build_runner build`
- `flutter analyze --fatal-warnings --fatal-infos`
- `flutter test`
- `dart run tool/verify_dartdoc.dart`
- `dart run tool/verify_barrel_exports.dart`
- `dart run tool/verify_architecture.dart`
- `dart run tool/verify_design_system.dart`
- `dart run tool/verify_production_tracker.dart`

Fix failures locally with `make format`, `make lint`, and `make test`, then
commit and push again.

## Available Commands

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

- Android SDK platform 36, build tools 36.0.0, and platform tools 36.0.0
- Android NDK 28.2.13676358, matching Flutter 3.47.0
- Gradle 9.3.1, Android Gradle Plugin 9.1.0, and Kotlin 2.4.0
- Java JDK 21
- CocoaPods 1.16.2 through Bundler 4.0.10 (macOS only)

The flake deliberately does not install Flutter or Dart. It places the
project-local `.fvm/flutter_sdk/bin` on `PATH`; FVM remains the sole source of
truth for Flutter 3.47.0 and Dart 3.13.0. Run `make fvm-setup` before entering
the shell, and do not use a separately installed Dart SDK for app generation,
analysis, tests, or documentation.

Flutter itself is managed via [FVM](https://fvm.app/) and pinned per project
using `.fvmrc` (`flutter: 3.47.0`). This keeps the Flutter version
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
checksum before committing it.

## Local SDK Development

The committed dependency always points to the immutable public UTEXO SDK
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

The default build is regtest and cannot become mainnet accidentally. Optional
non-secret endpoint overrides are documented in
`docs/architecture/SDK_INTEGRATION.md`. Never pass LSP, VSS, Bitcoin RPC, or
other credentials with `--dart-define`, because compile-time values are part of
the application binary.

The immutable SDK's default regtest indexer uses local plain HTTP. That default
is accepted only by Debug and Profile builds. Release builds reject HTTP,
unencrypted Electrum (`tcp`), and unencrypted RGB transport (`rpc`) before
native wallet creation, including on loopback and `10.0.2.2`. A Release build
for regtest therefore requires explicit TLS-protected service endpoints; an
unconfigured Release build fails closed instead of silently relying on a
transport Android packaging already forbids.

RGB USDT requires both `UTEXO_USDT_ASSET_ID` and
`UTEXO_USDT_PRECISION` for the selected environment. These are non-secret
deployment identity values and must be supplied together. When either is
missing, the app keeps both USDT rails visible but unavailable; it never infers
an asset contract or decimal precision from the `USDT` ticker.

## Market Data Configuration

Debug and profile builds use CoinGecko's keyless public API when no market
endpoint is supplied. That pool is intended for testing and prototyping, is
dynamically rate-limited, and is not a production reliability contract. The UI
retains the required `Powered by CoinGecko` attribution. See CoinGecko's
[keyless API policy](https://docs.coingecko.com/docs/keyless-public-api) and
[API terms](https://www.coingecko.com/en/api_terms).

Release builds fail closed unless `UTEXO_MARKET_API_BASE_URL` identifies a
deployment-owned public HTTPS proxy that preserves the required CoinGecko API
paths. The proxy owner must hold the appropriate data/API rights, keep provider
credentials server-side, enforce its own abuse and availability policy, and
return no user-specific or secret data. Direct CoinGecko hosts, insecure or
private hosts, credentials, query strings, and fragments are rejected. Never
place a CoinGecko or proxy API key in `--dart-define`; mobile binaries cannot
protect it.

Example non-secret release identity:

```sh
--dart-define=UTEXO_MARKET_API_BASE_URL=https://market.utexo.example/api/v3
```

The `.example` hostname above is documentation only and is deliberately
rejected at runtime. A release owner must substitute the real approved public
host.

Settings support, legal, and social destinations are optional deployment
configuration. Omitted values render as disabled actions; the app never ships
a guessed URL or enabled no-op command.

| Define | Settings action |
| --- | --- |
| `UTEXO_SUPPORT_URL` | Contact Support |
| `UTEXO_TERMS_URL` | Terms of Service |
| `UTEXO_PRIVACY_URL` | Privacy Policy |
| `UTEXO_TWITTER_URL` | Twitter |
| `UTEXO_TELEGRAM_URL` | Telegram |
| `UTEXO_INSTAGRAM_URL` | Instagram |

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
