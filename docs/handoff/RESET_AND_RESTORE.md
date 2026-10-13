# System Reset and Restore Runbook

Checkpoint: 13 October 2026. Read [System Context](SYSTEM_CONTEXT.md) for the
engineering state and [Resume Prompt](RESUME_PROMPT.md) to restart work.

## Do Not Erase the Machine Yet

This handoff preserves knowledge, **not the underlying databases or secrets**.
A copy on this machine's Desktop will be erased with the machine. Store the
handoff and the separate sensitive backup on an encrypted external disk or
another independently recoverable encrypted destination, then verify a restore.

Reset readiness is currently **not verified**. In particular:

- Iris `utexo-app` has modified and untracked source/tests/docs.
- Both repositories under `utexo-lightweight` have modified/untracked work;
  root documents and the shared Rust signer have no top-level Git protection.
- `utexo-app/.devstack/bridge-retest-20261013` contains ignored source edits,
  test wallets, proofs, keys, chain/service state and native artifacts.
- Codex transcripts contain past credentials and potentially sensitive wallet
  material. They belong only in an encrypted private backup, never a Git repo.
- Docker service status could not be confirmed during this handoff. Do not
  assume databases are quiescent or that a live file copy is consistent.

## Four Backup Layers

| Layer | Preserve | What a Git clone misses |
| --- | --- | --- |
| Committed source | Aster/SDK remotes and exact commits; all sibling refs/worktrees | Local-only commits, stashes, reflogs, worktree metadata |
| Uncommitted work and context | Working files, ignored local source/docs, evidence, screenshots, custom skills | Every byte not committed, including root-level lightweight handoffs |
| Sensitive operational state | Wallet stores + secure credentials + registries + journals, chain/index/proxy/VSS/bridge state, certificates | Seeds alone do not reconstruct all RGB/service state |
| Codex desktop continuity | Complete quiescent Codex local state and app support; account access | Conversation history, attachments, local project/task associations |

Git bundles are useful additional insurance for refs, but **do not** capture
uncommitted or ignored files. `git diff --binary` also misses untracked files.
Neither is a replacement for an encrypted filesystem backup.

## Backup Inventory

Original home is `/Users/hardik`. Use `$HOME` after restoration; do not rename
Git authors to match a macOS account name. Check existence before copying.

| Path | Preserve or rebuild | Notes |
| --- | --- | --- |
| `~/Projects/aster-dev` including `.git` and `.local` | Preserve | App source, local Aster stack, local defines, reports and ignored state |
| `~/Projects/rgb-sdk-flutter` including `.git` and `tool/regtest/data` | Preserve | SDK source, auth profile metadata, local SDK chain state and reports |
| `~/Projects/utexo-app` including `.devstack` | Preserve | Dirty Iris source and the newer ignored bridge retest, not just node_modules |
| `~/Projects/utexo-trial` and `~/Projects/pr-series` | Preserve with their Git parent repos | WDK/IRIS/upstream linked worktrees can point outside their own folder |
| `~/Projects/rgb-lightning-node-bare`, `rgb-lightning-node-nodejs` | Preserve | Long-lived binding worktrees; newer artifacts may live elsewhere |
| `~/Projects/utexo-lightweight` entire workspace | Preserve | Native SDK edits, non-Git signer/root docs, local gateway fixtures |
| `~/Projects/rln-lightning` | Preserve | Upstream mainnet work, local investigations, evidence and repro state |
| `~/Projects/rgb-lightning-node-perf-lab`, `rgb-ops-perf-lab`, `rgb-protocol-perf-lab` | Owner-coordinated preservation | Protected separate task; do not stop or reset it from Aster |
| `~/Projects/wdk-rgb-demo` | Preserve if still needed | Older demo, not authoritative current release checkout |
| `~/.codex` or custom `$CODEX_HOME` | Preserve encrypted after quitting all Codex clients | Sessions, multiple rollout segments, attachments, DBs, rules, skills, config and secrets |
| `~/Library/Application Support/Codex` | Preserve encrypted after app exits | Observed app state; not a supported portable export guarantee |
| `~/Library/Application Support/com.openai.codex` and `~/Library/Preferences/com.openai.codex.plist` | Preserve encrypted | Both paths exist on this machine |
| `~/Library/Developer/CoreSimulator/Devices` | Optional complete encrypted development-state backup | Not independently sufficient for transferable Keychain credentials; simulator IDs can change |
| `~/.android/avd` and bridge retest `android.avd` | Optional coherent encrypted emulator backup | AVD metadata can point to missing external paths; recreate if necessary |
| OS Keychain, signing keys/profiles, password manager and MFA recovery | Approved secure recovery process | File copies and ordinary app backup do not guarantee this-device-only material transfers |
| Docker bind mounts and named volumes | Coordinated consistent backup/export | Source folders do not contain Docker Desktop-managed named volumes |
| Desktop visual references and verified output | Preserve selected folders | Only `Aster-iOS-Screenshots-2026-08-25-iPhone-Air` was observed now; old September gallery paths may be gone |
| `/private/tmp/aster-rgb-upstream-20261013` and upgrade logs | Preserve selected evidence privately | Temporary source/artifacts/logs are not durable; sanitize before publishing |

The workspace snapshot identifies additional Git repositories nested inside the
above folders. Its clean/dirty status is dated; inspect again immediately before
backup because other tasks may keep working. No sibling work was committed,
stashed, reverted or pushed by this documentation task.

### Safe Capture Procedure

1. Choose an encrypted destination with enough capacity and separately held
   recovery credentials. Do not put the only decryption key on the disk being
   erased. Pause all contributing work and note the final timestamps/commits.
2. Have each stack owner stop or checkpoint its own writers and export its
   databases. Preserve Bitcoin chain/wallets, RGB stores/consignments, indexer
   state, proxy data, VSS, bridge SQL and EVM chain state consistently. Do not
   copy live PostgreSQL/SQLite/WAL files as if they were a verified snapshot.
3. Preserve full working directories including hidden files, parent Git common
   directories and ignored data. Use an encrypted system backup when possible.
   Copying only `git ls-files` is insufficient.
4. Finish this handoff, then quit Codex desktop, CLI and other Codex clients.
   Back up local Codex state only after writers have exited. SQLite WAL/SHM
   files and all rollout segments belong with their databases; do not select
   a single oldest JSONL and assume it is the whole conversation.
5. Copy the handoff to the same off-machine destination plus a second durable
   location. Verify a restore into a separate directory without overwriting
   the originals; compare source trees, refs, sample ignored files and hashes.
6. Confirm that private GitHub access, OpenAI account access and the password
   manager/MFA recovery work independently of the old machine.

Illustrative copy commands, **run only after the quiescence and encryption
steps**, with a real mounted backup destination:

```sh
export BACKUP_ROOT="/Volumes/YOUR_ENCRYPTED_DISK/Aster-reset-2026-10-13"
mkdir -p "$BACKUP_ROOT"

# Full Projects is the simplest way to retain linked worktrees and sibling
# non-Git files when capacity allows. It also includes unrelated/private data.
ditto "$HOME/Projects" "$BACKUP_ROOT/Projects"

# Run these after quitting Codex, not from an active Codex task.
ditto "${CODEX_HOME:-$HOME/.codex}" "$BACKUP_ROOT/CodexHome"
ditto "$HOME/Library/Application Support/Codex" "$BACKUP_ROOT/CodexAppSupport"
ditto "$HOME/Library/Application Support/com.openai.codex" "$BACKUP_ROOT/CodexBundleSupport"
ditto "$HOME/Library/Preferences/com.openai.codex.plist" "$BACKUP_ROOT/com.openai.codex.plist"
```

These examples do not export Docker volumes, OS Keychain or simulator state.
Use the approved system/owner-specific backup for those. Do not prune caches
until you have distinguished rebuildable outputs from ignored sources/state.

### Sensitive Material Handling

No tokens, mnemonic words, wallet passwords, raw invoices or private journals
belong in these documents. Historical GitHub/GitLab tokens were pasted in this
conversation; revoke/rotate any still-valid exposed credentials independently.
Do not copy them from the old transcript into shell commands. New GitHub auth
should use an interactive credential flow scoped to these projects.

Development wallets must contain only test funds. If any real funds exist in a
device whose storage is this-device-only, stop and perform a separately reviewed
recovery/migration exercise before resetting. The SDK's unsupported backup API
and lack of complete RGB recovery proof are real limitations; this runbook does
not invent a wallet backup mechanism.

## Restoring Codex Context

Official documentation locates Codex state under `CODEX_HOME`, normally
`~/.codex`; auth can also live in the OS credential store. This explains why
reinstalling the app alone is not a complete restoration plan.
[Official state locations](https://learn.chatgpt.com/docs/config-file/config-advanced).

Session transcripts and archived transcripts have separate directories; the
official troubleshooting guide warns that shared logs need secret review.
[Official local transcript locations](https://learn.chatgpt.com/docs/reference/troubleshooting).

Observed task identities:

| Exact task title | ID | Working directory |
| --- | --- | --- |
| Package & App | `019e4624-fd92-7a41-b98b-3790c02da3e1` | `Projects/aster-dev` |
| Dev | `019efd58-9c10-72d3-9b79-f29b33871537` | `Projects/utexo-app` |
| Lightweight SDKs | `01a09f2a-0322-7ea3-94e5-a6a64121613b` | `Projects/utexo-lightweight` |
| Restrict mainnet Lightning APIs | `01a0ccd1-be4a-7ad1-938e-cefcdb239158` | `Projects/rln-lightning` |

Several tasks have multiple dated rollout segments. Back up the complete
Codex home rather than naming just one transcript. The current app also has
`state_5.sqlite`, `thread_history_1.sqlite`, `session_index.jsonl`, `attachments`,
`archived_sessions`, `memories`, custom skills, plugins and configuration.
Do not hand-edit the databases to relocate a task.

After reinstalling, sign into the same account. With all Codex clients closed,
restore the quiescent backup using the platform backup mechanism or cautiously
restore its directories to an empty target, keeping a copy of the new install's
state first. Absolute project paths should match where practical; otherwise
re-add projects at the new paths and use the handoff in a new task.

Try opening **Package & App** in the desktop app. The CLI also supports resuming
saved sessions; inspect `codex resume --help` on the installed version and use:

```sh
cd "$HOME/Projects/aster-dev"
codex resume 019e4624-fd92-7a41-b98b-3790c02da3e1
```

[Official resume command reference](https://learn.chatgpt.com/docs/developer-commands?surface=cli).
The exact desktop task's automatic restoration across OS resets/version/path
changes has **not** been tested here. Do not promise cloud sync will reconstruct
everything. The reliable engineering fallback is a new task opened on the
restored repository with `RESUME_PROMPT.md` attached. Background processes,
tool-session IDs, emulator IDs, pending approvals and live in-memory context
must be re-established even when a transcript is restored.

## Git Identity and Access After Reset

Project commits use `zeusbuilds <zeusbuilds113@gmail.com>`. The system-wide
Git/GitHub user must stay unchanged. Git author metadata and push authentication
are separate settings; verify both.

The old project-scoped GH configuration lives in
`Projects/rgb-sdk-flutter/.git/gh-zeus`. A fresh clone will not recreate it.
Reauthenticate rather than printing or embedding its credential contents:

```sh
export PROJECTS="$HOME/Projects"
export ZEUS_GH_CONFIG="$PROJECTS/rgb-sdk-flutter/.git/gh-zeus"
GH_CONFIG_DIR="$ZEUS_GH_CONFIG" gh auth login --hostname github.com --git-protocol https --web
GH_CONFIG_DIR="$ZEUS_GH_CONFIG" gh api user --jq .login

git -C "$PROJECTS/aster-dev" config --local user.name zeusbuilds
git -C "$PROJECTS/aster-dev" config --local user.email zeusbuilds113@gmail.com
git -C "$PROJECTS/rgb-sdk-flutter" config --local user.name zeusbuilds
git -C "$PROJECTS/rgb-sdk-flutter" config --local user.email zeusbuilds113@gmail.com
```

If both private clones are absent, authenticate first in a dedicated temporary
**private** `GH_CONFIG_DIR` outside Git, clone the two private repos, then choose
one permanent project-scoped auth directory and use it consistently. Do not
switch the global account as a shortcut. Check `gh api user` says `zeusbuilds`
before any push. Organization SSO/repository permissions may need renewal.

Normal push pattern, only when there is an approved commit to push:

```sh
GH_CONFIG_DIR="$ZEUS_GH_CONFIG" GIT_TERMINAL_PROMPT=0 \
  git -C "$PROJECTS/aster-dev" -c credential.helper= \
  -c 'credential.helper=!gh auth git-credential' push origin main

GH_CONFIG_DIR="$ZEUS_GH_CONFIG" GIT_TERMINAL_PROMPT=0 \
  git -C "$PROJECTS/rgb-sdk-flutter" -c credential.helper= \
  -c 'credential.helper=!gh auth git-credential' push origin main

GH_CONFIG_DIR="$ZEUS_GH_CONFIG" GIT_TERMINAL_PROMPT=0 \
  git -C "$PROJECTS/rgb-sdk-flutter" -c credential.helper= \
  -c 'credential.helper=!gh auth git-credential' \
  push https://github.com/UTEXO-Protocol/flutter-sdk.git main:main
```

No force pushes, history rewrites, visibility changes or origin replacement.
Do not apply Zeus identity indiscriminately to other tasks' upstream work.

## Toolchain Reconstruction

Recover the pinned candidate before attempting another upgrade:

| Component | Recorded working baseline |
| --- | --- |
| Aster | Flutter 3.47.0 / Dart 3.13.0 through FVM; app version 1.0.0+1 provisional |
| Flutter SDK minimum | Flutter >=3.41.0 / Dart >=3.11.0; use the validated app toolchain initially |
| Apple | Xcode 27, iOS26.5 runtime in prior checks; deployment floor 18.5; CocoaPods fallback |
| Ruby | Homebrew Ruby, Bundler 4.0.10, locked CocoaPods 1.16.2; repository-local `.bundle` |
| Android app | Java21; Gradle9.3.1, AGP9.1, Kotlin2.4, compileSDK36, NDK28.2 baseline |
| Iris | Node22, repository package lock and native WDK install/generation scripts; not Expo Go |
| Bridge/Bare builds | Consult exact candidate manifests; newer native report uses Rust1.94 and separate Node/Bare target dirs; bridge prerequisites include Go1.26+ |
| Local infrastructure | Docker Desktop/Compose/Buildx; exact image digests/locks in each owner repo |

Install tools from their official distribution, validate Xcode/Android licenses
and available disk, then from Aster:

```sh
make fvm-setup
make dependencies
make verify-generated
make ios-dependencies
./scripts/install-git-hooks.sh
make lint
make test
```

Use the Makefile and `docs/DEVELOPMENT.md` as the executable authority. Generated
Riverpod/Freezed/Flutter/Gradle/Pod files are regenerated, not copied from a
different version. Ensure Java and Homebrew Ruby resolve correctly. No local
SDK path override may remain in candidate evidence; the app must resolve public
SDK commit `7c44506fdfe1dae6f3a6fe884f849c7ca2ad028b` in both manifest and lock.

SDK host baseline commands (run from SDK root with the pinned Flutter on PATH):

```sh
flutter pub get --enforce-lockfile
./tool/generate_pigeon.sh
dart format --output=none --set-exit-if-changed lib test tool
flutter analyze --fatal-warnings --fatal-infos
flutter test --coverage
dart doc --validate-links
RGB_SDK_RN_PATH=/path/to/exact-rn-checkout dart run tool/validate_rn_parity.dart
```

Read current README/tool scripts for release-gate inputs before running
`RUN_CONSUMER_ARCHIVES=1 RUN_PLATFORM=1 ./tool/test_release_candidate.sh`.
Supply owned iOS/Android device IDs and isolated services. That command can
build, launch tests and mutate its test fixtures; it is not a read-only restore
check. A missing device/service or required skipped scenario is not a pass.

## Stack Ownership and Port Map

Ports below describe separate configurations, not proof they can all run at
once. Recheck actual listeners and Compose ownership before starting anything.

| Owner/project | Important host ports | Durable state | Authority |
| --- | --- | --- | --- |
| Protected `rgb-lightning-node-perf-lab` | 18443 Bitcoin, 50001 Electrum, 3000 proxy | `Projects/rgb-lightning-node-perf-lab/datacore`, `dataindex`, other owner-declared mounts | Its owner only; never its regtest.sh from this task |
| Aster `aster-app-regtest` | 19443 Bitcoin, 51001 Electrum, 3100 proxy | `aster-dev/.local/aster-regtest/` | `aster-dev/ops/regtest/compose.yaml` |
| Flutter SDK `rgb-sdk-flutter-regtest` | 18444 Bitcoin, 50002 Electrum, 3013 proxy | `rgb-sdk-flutter/tool/regtest/data/` plus any actual Docker-owned writable state | SDK `tool/regtest/compose.yaml`, `config.sh`, `regtest.sh` |
| Historical Iris `utexo-wallet-devstack` | Defaults include 18443/50001/3000, 3002 issuer, 9736 peer, 3003 Esplora, 18081 VSS, 8080 LSP | Iris `.devstack/` and declared volumes | Iris `ops/devstack.lock.json`; defaults collide with protected perf-lab |
| New Iris bridge `iris_bridge_20261013` | Gateway18088, Postgres26432, Anvil18555, RGB forwarder28090; frontend3000 and Mailpit18025 separate | `utexo-app/.devstack/bridge-retest-20261013/stand-data` | Private generated topology plus RETEST.md |

Aster embedded node listeners are 19735/19736 in its local configuration.
These are inside the app process, not Docker LSP nodes or funded channels.
The new Iris bridge network is `iris_bridge_20261013_stand`, security profile
`mtls`; these non-secret fields were read selectively, without dumping envs.
Its reported frontend port3000 conflicts with another project's proxy default;
do not start everything indiscriminately or stop the current owner to free it.

The SDK Compose proxy declares no persistent volume in its source. If existing
consignment transport bytes matter, have the SDK stack owner preserve the actual
container writable state or retrieve required wallet proof data before deleting
containers. `tool/regtest/data` alone is not proof of a complete proxy backup.

### Aster Restore or Fresh Isolated Setup

For **restored** `.local` state and config, do not rerun the initializer. Check
paths, permissions, ownership, network/asset generation and free ports, then:

```sh
cd "$HOME/Projects/aster-dev"
docker compose --env-file .local/aster-regtest/compose.env \
  -f ops/regtest/compose.yaml up -d --wait --wait-timeout 180
docker compose --env-file .local/aster-regtest/compose.env \
  -f ops/regtest/compose.yaml ps
```

For a deliberately **new test-only generation** with no state to restore:

```sh
fvm dart run tool/initialize_local_regtest.dart
```

The initializer refuses existing/partial state rather than overwriting it. Read
`docs/REGTEST.md`; do not delete files to defeat that guard. `up` includes a
miner that bootstraps 101 blocks and mines every ten seconds. If mining is to
wait for explicit user instruction, omit/stop only this owned miner service.
Never mine the protected or Iris chain from Aster.

This basic stack has Bitcoin, Electrum and RGB proxy only. It does not issue
USDT/BFA, deploy an Ethereum bridge, provide LSP liquidity or run VSS. Do not
assume healthy containers unlock those features. Recover/provision each extra
service and exact asset fixture through its owner and acceptance tests.

### SDK and Iris Restore

SDK `tool/regtest/regtest.sh start` bootstraps/advances the SDK chain to at least
103 blocks and may mine to leave initial-block-download state. Read its `info`,
`mine`, `stop` and destructive `reset` implementations before invoking. Do not
run it against another project via environment overrides.

Historical Iris `npm run devstack:up` builds/provisions its own locked sources,
issuer, canonical/linked assets and generated environment. Its reset command
destroys a generation. Do not run it for the newer bridge retest or Aster.

For the new bridge retest, restore the entire workspace and its private
`stand-data/config/compose.env`, then inspect the current `deploy/local`
bootstrap/status/preflight and Compose wrapper. Preserve chain checkpoints,
Anvil state, issuer/receiver stores, journals, SQL, certificates, source
manifest and pending operations together. Do not blindly run a default
bootstrap: its upstream guide can invoke real Signet faucet/contract setup,
whereas this retest deliberately uses local chains and local overrides.

Do not print `docker compose config`, complete env files, process command lines
or raw `docker inspect` payloads in chat. For ordinary inspection use narrow
container names/status/port/owner labels. Terminate a stuck CLI query with a
deadline; do not restart Docker or kill every container to make it return.

## Devices and Launch

Use Aster-owned simulators/emulators only. Do not target Iris Onchain, WDK or a
device owned by another task. Old Aster simulator:
`8486A729-823E-4962-9B18-74749B92C889`, name
`Aster Onboarding - iPhone 17 Pro`. Recreate/select an explicitly owned device
after reset; old UUIDs, AVD paths and Codex run-session IDs may be invalid.

For configured iOS development after restoring/initializing the Aster stack:

```sh
make verify-generated ios-dependencies
BUNDLE_FROZEN=true BUNDLE_PATH="$PWD/.bundle" \
  bundle exec fvm flutter run --no-pub -d <ASTER_SIMULATOR_ID> \
  --dart-define-from-file=config/regtest.ios.local.json
```

For Android create an ignored Android local JSON from the validated configuration
with `10.0.2.2` instead of `127.0.0.1` for host-facing services, retaining Aster
ports. Pass that file to `flutter run`. Do not use the iOS endpoint file as
Android runtime qualification merely because it compiles. Keep the dev run in
an interactive terminal: `r` hot reload, `q` stop, then rerun for full restart.

Do not reset an installed wallet to hide an open/mismatch error. First distinguish
wrong stack generation, files without their secure-storage record, endpoint
failure, native ownership left by hot restart, and an actual runtime defect.

## Evidence to Retain

The October13 app/SDK logs are under `/private/tmp/aster-rgb-upgrade-*`; key files:

- `app-committed-tests.log`: 975 exact-clean implementation tests.
- `app-closeout-commit.log`: normal hooks for documentation closeout.
- `app-ios-final.log`: source-equivalent iOS Debug compile.
- `app-android-arm64.log`, `app-android-host-tests.log`: compile/host evidence.
- `sdk-final-coverage.log`, `android-native.log`, `sdk-ios-build.log`.
- `clean-consumers.log`: incomplete run and failure boundary, not a pass.

Preserve SDK `build/test-reports`, coverage evidence, current app coverage,
native baseline/provenance manifests and any reviewed screenshot sets. Raw logs
can contain sensitive diagnostics; retain privately, sanitize copies for release.
Existing build products are not all present after disk cleanup.

Known app output hashes from the prior verification:

| Output | SHA-256 |
| --- | --- |
| Exact clean app LCOV | `d35a3a16cbfc8aaf3461c60fc7d29798f8b38ffc416dd0a8e05fd47f40eab037` |
| iOS Runner executable (build later deleted) | `9e11108c7e2f1eeccc898c6b0a6fa90a8332cf7c2b81e2c07c4554f77c625221` |
| Android ARM64 Debug APK | `f84608b0a1d3e7711c94b950281e2ba40aacde7bc617e0a5c17335e7ec2ae57c` |

Native iOS archive and Maven AAR hashes belong to SDK
`tool/release_baseline.json`. Redownload pinned bytes and verify rather than
copying another version's generated frameworks or relaxing checksums.

## Restoration Acceptance Checklist

- [ ] Handoff readable from an off-machine destination; archive integrity checked.
- [ ] Codex account accessible, local history restored or new task primed.
- [ ] Aster and Flutter SDK exact baseline commits available; no source edits lost.
- [ ] Every dirty/ignored/non-Git sibling path in the snapshot restored or explicitly retired by its owner.
- [ ] Git identity/auth verified project-locally; repository privacy unchanged.
- [ ] Secrets recovered through approved secure process, never pasted into chat.
- [ ] Wallet store, credentials, registry, proofs and journals are a coherent set.
- [ ] Each required stack restored as one generation; named volumes accounted for.
- [ ] Port ownership verified; protected stacks and devices untouched.
- [ ] Pinned toolchains, dependency locks and generated sources validated.
- [ ] App and SDK host gates pass again; failures are recorded rather than hidden.
- [ ] Dedicated app launch and known-safe test wallet flow verified.
- [ ] Exact device/funded/release evidence collected separately before promotion.

Do not mark boxes just because this document exists. Recovery of a development
environment and qualification of a financial wallet release are separate jobs.
