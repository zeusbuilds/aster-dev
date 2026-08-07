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

1. **Enter the development environment:**
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

2. **Ensure FVM Flutter is installed (first time on a machine):**
   ```bash
   make fvm-setup
   ```
   This installs the Flutter version pinned in `.fvmrc` and wires it into the project.

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

After this, each `git commit` regenerates ignored generated sources, verifies
formatting without mutating files, runs analysis with every diagnostic fatal,
and verifies the production tracker inventory.

### Manual commands

- `make format` - Format Dart code
- `make format-check` - Verify formatting without changing files
- `make analyze` - Run static analysis with warnings and infos fatal
- `make verify-generated` - Regenerate ignored generated Dart sources
- `make verify` - Verify repository invariants and tracker inventory
- `make lint` - Run all non-mutating pre-commit quality gates

### CI (GitHub Actions)

On push to `main` and on pull requests, the **Dart** workflow runs:

- `dart format --output=none --set-exit-if-changed .`
- `dart run build_runner build`
- `flutter analyze --fatal-warnings --fatal-infos`
- `flutter test`
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
- `make verify-generated` - Regenerate ignored generated Dart sources
- `make verify`     - Verify repository invariants
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

This project uses [Nix Flakes](https://nixos.wiki/wiki/Flakes) to provide a reproducible development environment for core tooling. The environment includes:

- Flutter 3.44.9
- Dart SDK 3.12.2
- Android SDK with build tools
- Java JDK 21
- CocoaPods (macOS only)

Flutter itself is managed via [FVM](https://fvm.app/) and pinned per project
using `.fvmrc` (`flutterSdkVersion: 3.44.9`). This keeps the Flutter version
consistent across developers without relying on the Nix store.

## Local SDK Development

The committed dependency always points to the immutable public UTEXO SDK
commit. For temporary SDK development only, see
`docs/architecture/SDK_INTEGRATION.md`. Never commit a path dependency or a
`dependency_overrides` entry.

## Resources

- [Flutter Documentation](https://docs.flutter.dev/)
- [Nix Flakes Documentation](https://nixos.wiki/wiki/Flakes)
- [Direnv Documentation](https://direnv.net/)
