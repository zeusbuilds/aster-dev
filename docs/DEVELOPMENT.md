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
   make run
   # or
   flutter run   # after FVM is set up, inside `make shell`
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
Dart API documentation and barrel boundaries, and verifies the production
tracker inventory.

### Manual commands

- `make format` - Format Dart code
- `make format-check` - Verify formatting without changing files
- `make analyze` - Run static analysis with warnings and infos fatal
- `make docs` - Generate fresh API docs and fail on warnings or broken links
- `make verify-generated` - Regenerate ignored generated Dart sources
- `make verify` - Verify barrel policy and tracker inventory
- `make verify-barrels` - Verify barrel boundaries directly
- `make lint` - Run all non-mutating pre-commit quality gates

### CI (GitHub Actions)

On push to `main` and on pull requests, the **Dart** workflow runs:

- `dart format --output=none --set-exit-if-changed .`
- `dart run build_runner build`
- `flutter analyze --fatal-warnings --fatal-infos`
- `flutter test`
- `dart run tool/verify_dartdoc.dart`
- `dart run tool/verify_barrel_exports.dart`
- `dart run tool/verify_production_tracker.dart`

Fix failures locally with `make format`, `make lint`, and `make test`, then
commit and push again.

## Available Commands

- `make shell`      - Enter Nix development environment
- `make fvm-setup`  - Install/use Flutter via FVM for this project (uses version from `.fvmrc`)
- `make bootstrap`  - Initial project setup (clean, pub get, build_runner)
- `make clean`      - Clean Flutter build artifacts
- `make build`      - Run build_runner to generate code
- `make watch`      - Run build_runner in watch mode
- `make run`        - Run Flutter app
- `make test`       - Run Flutter tests
- `make format`     - Format Dart code
- `make format-check` - Verify formatting without changing files
- `make analyze`    - Run static analysis with all diagnostics fatal
- `make docs`       - Generate and validate fresh Dart API docs
- `make verify-generated` - Regenerate ignored generated Dart sources
- `make verify`     - Verify repository invariants
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

- Android SDK platform/build/platform tools 36
- Java JDK 21
- CocoaPods (macOS only)

The flake deliberately does not install Flutter or Dart. It places the
project-local `.fvm/flutter_sdk/bin` on `PATH`; FVM remains the sole source of
truth for Flutter 3.44.9 and Dart 3.12.2. Run `make fvm-setup` before entering
the shell, and do not use a separately installed Dart SDK for app generation,
analysis, tests, or documentation.

Flutter itself is managed via [FVM](https://fvm.app/) and pinned per project
using `.fvmrc` (`flutterSdkVersion: 3.44.9`). This keeps the Flutter version
consistent across developers without relying on the Nix store.

## Local SDK Development

The committed dependency always points to the immutable public UTEXO SDK
commit. For temporary SDK development only, see
`docs/architecture/SDK_INTEGRATION.md`. Never commit a path dependency or a
`dependency_overrides` entry.

## Wallet Service Configuration

The default build is regtest and cannot become mainnet accidentally. Optional
non-secret endpoint overrides are documented in
`docs/architecture/SDK_INTEGRATION.md`. Never pass LSP, VSS, Bitcoin RPC, or
other credentials with `--dart-define`, because compile-time values are part of
the application binary.

RGB USDT requires both `UTEXO_USDT_ASSET_ID` and
`UTEXO_USDT_PRECISION` for the selected environment. These are non-secret
deployment identity values and must be supplied together. When either is
missing, the app keeps both USDT rails visible but unavailable; it never infers
an asset contract or decimal precision from the `USDT` ticker.

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
single-label intranet hosts, and reserved non-public suffixes are rejected.
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
