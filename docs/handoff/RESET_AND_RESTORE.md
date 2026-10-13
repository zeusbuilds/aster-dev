# System Reset and Restore Runbook

Checkpoint: 13 October 2026. Read [System Context](SYSTEM_CONTEXT.md) for the
engineering state and [Resume Prompt](RESUME_PROMPT.md) to restart work.

## Location-Independent References

Use the [Git repository map](SYSTEM_CONTEXT.md#repository-authority-and-version-pins)
to identify source. `owner/repo @ commit : file` always means a file relative
to that repository, regardless of where it is cloned. Neither the old macOS
username nor a `Projects` folder is required, and the app and SDK need not be
siblings. Relative Markdown links within this pack remain portable.

Before running any command, set roots for **your chosen locations**. These are
examples only; edit each independently, and do not overwrite an existing tree:

```sh
export ASTER_ROOT="$HOME/Developer/aster"
export SDK_ROOT="$HOME/Developer/flutter-sdk"
export RN_ROOT="$HOME/References/rgb-sdk-rn"
export RLN_ROOT="$HOME/References/rgb-lightning-node"
export ZEUS_GH_CONFIG="$HOME/.config/aster-zeus-gh"
```

`ASTER_ROOT` maps to `zeusbuilds/aster-dev`; `SDK_ROOT` maps to
`zeusbuilds/rgb-sdk-flutter`, not its public mirror. `RN_ROOT` and `RLN_ROOT`
are optional, separate reference clones. `ZEUS_GH_CONFIG` is a private,
project-specific credential directory, not the global GitHub CLI profile.
Set `BRIDGE_RETEST_ROOT`, `EVIDENCE_ROOT`, `SOURCE_ROOT` and `BACKUP_ROOT`
separately when restoring private state or making a backup; Git cannot supply
their contents. Never treat a missing variable as a default source directory.

The snapshot's `snapshotCheckoutKey` and `snapshotCommonGitDirectory` are
relative labels inside the **old backup collection**. They help pair dirty
overlays/worktrees with `origin` and `head`; they are not paths to recreate.
File paths in `workingTreeStatus` are relative to their own checkout. A local
commit may require a Git bundle or preserved object database if no remote ref
contains it. A recorded Git URL is not proof that every captured ref was pushed.

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

The following workspace names are **historical backup labels**, resolved via
the snapshot's Git origins and the selected roots above. They do not prescribe
the new directory layout. OS paths using `$HOME` refer to the account on the
machine being backed up/restored; do not rename Git authors to match that account.

| Path | Preserve or rebuild | Notes |
| --- | --- | --- |
| Aster checkout: `.git`, `.local`, ignored local config | Preserve | Locate by `zeusbuilds/aster-dev`; committed code is recoverable from Git, local state is not |
| Flutter SDK checkout: `.git`, `tool/regtest/data`, reports | Preserve | Locate by `zeusbuilds/rgb-sdk-flutter`; retain local-only refs/auth/state separately |
| Iris backup label `utexo-app`, including `.devstack` | Preserve | Locate source by `UTEXO-Protocol/iriswallet-mobile`; dirty work and ignored retest require backup |
| Collections `utexo-trial` and `pr-series` | Preserve with their Git parent repos | Match each snapshot origin/commit; linked worktrees can point outside their folder |
| Node/Bare binding checkouts | Preserve | Locate by `UTEXO-Protocol/rgb-lightning-node-nodejs` and `rgb-lightning-node-bare`; retain distinct retest revisions |
| Collection `utexo-lightweight` | Preserve | Git supplies Swift/Kotlin SDK baselines only; root notes and shared signer need backup |
| Collection `rln-lightning` | Preserve | Multiple upstream/fork origins in snapshot; retain local investigations/evidence |
| Protected performance collections named `rgb-lightning-node-perf-lab`, `rgb-ops-perf-lab`, `rgb-protocol-perf-lab` | Owner-coordinated preservation | Match snapshot origins/commits; do not stop or reset them from Aster |
| Demo collection `wdk-rgb-demo` | Preserve if still needed | Source `UTEXO-Protocol/utexo-rgb-wdk-demo`; not current release authority |
| `~/.codex` or custom `$CODEX_HOME` | Preserve encrypted after quitting all Codex clients | Sessions, multiple rollout segments, attachments, DBs, rules, skills, config and secrets |
| `~/Library/Application Support/Codex` | Preserve encrypted after app exits | Observed app state; not a supported portable export guarantee |
| `~/Library/Application Support/com.openai.codex` and `~/Library/Preferences/com.openai.codex.plist` | Preserve encrypted | Both paths exist on this machine |
| `~/Library/Developer/CoreSimulator/Devices` | Optional complete encrypted development-state backup | Not independently sufficient for transferable Keychain credentials; simulator IDs can change |
| `~/.android/avd` and bridge retest `android.avd` | Optional coherent encrypted emulator backup | AVD metadata can point to missing external paths; recreate if necessary |
| OS Keychain, signing keys/profiles, password manager and MFA recovery | Approved secure recovery process | File copies and ordinary app backup do not guarantee this-device-only material transfers |
| Docker bind mounts and named volumes | Coordinated consistent backup/export | Source folders do not contain Docker Desktop-managed named volumes |
| Desktop visual references and verified output | Preserve selected folders | Only `Aster-iOS-Screenshots-2026-08-25-iPhone-Air` was observed now; old September gallery paths may be gone |
| Temporary comparison checkout collection `aster-rgb-upstream-20261013` and logs prefixed `aster-rgb-upgrade-` | Preserve selected evidence privately | Re-clone source from the recorded RN/RLN commits; logs/artifacts require backup or rerun, not Git |

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
: "${SOURCE_ROOT:?Set the existing collection root you intend to back up}"
: "${BACKUP_ROOT:?Set a new directory on a mounted encrypted backup destination}"
mkdir -p "$BACKUP_ROOT"

# Copy the chosen collection, not an assumed home-directory layout. Capture
# every separate root and linked-worktree common directory in your inventory.
# BACKUP_ROOT must be outside SOURCE_ROOT; this includes private data.
ditto "$SOURCE_ROOT" "$BACKUP_ROOT/SourceCollection"

# Run these after quitting Codex, not from an active Codex task.
ditto "${CODEX_HOME:-$HOME/.codex}" "$BACKUP_ROOT/CodexHome"
ditto "$HOME/Library/Application Support/Codex" "$BACKUP_ROOT/CodexAppSupport"
ditto "$HOME/Library/Application Support/com.openai.codex" "$BACKUP_ROOT/CodexBundleSupport"
ditto "$HOME/Library/Preferences/com.openai.codex.plist" "$BACKUP_ROOT/com.openai.codex.plist"
```

For multiple source collections, use a distinct destination child for each;
do not merge unrelated roots into the same `SourceCollection` directory.
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

| Exact task title | ID | Map to restored repository/collection |
| --- | --- | --- |
| Package & App | `019e4624-fd92-7a41-b98b-3790c02da3e1` | `zeusbuilds/aster-dev` at `ASTER_ROOT` |
| Dev | `019efd58-9c10-72d3-9b79-f29b33871537` | Iris source and its separate retest backup, mapped by Git identity |
| Lightweight SDKs | `01a09f2a-0322-7ea3-94e5-a6a64121613b` | Swift/Kotlin SDK origins plus backup-only workspace notes/signer |
| Restrict mainnet Lightning APIs | `01a0ccd1-be4a-7ad1-938e-cefcdb239158` | RLN fork/worktrees at the recorded origins/commits plus private notes |

Several tasks have multiple dated rollout segments. Back up the complete
Codex home rather than naming just one transcript. The current app also has
`state_5.sqlite`, `thread_history_1.sqlite`, `session_index.jsonl`, `attachments`,
`archived_sessions`, `memories`, custom skills, plugins and configuration.
Do not hand-edit the databases to relocate a task.

After reinstalling, sign into the same account. With all Codex clients closed,
restore the quiescent backup using the platform backup mechanism or cautiously
restore its directories to an empty target, keeping a copy of the new install's
state first. Re-add projects at their new locations. Do not recreate the old
username/path or add symlinks merely to satisfy saved task metadata. Review
restored project-trust, local environment, MCP and automation path settings
before enabling them; they may still reference old paths. Do not edit session
databases by hand.

Try opening **Package & App** in the desktop app. The CLI also supports resuming
saved sessions; inspect `codex resume --help` on the installed version and use:

```sh
: "${ASTER_ROOT:?Set the new Aster checkout location}"
codex resume --cd "$ASTER_ROOT" 019e4624-fd92-7a41-b98b-3790c02da3e1
```

[Official resume and working-directory reference](https://learn.chatgpt.com/docs/cli/reference).
An explicit `--cd` selects the new working directory for the CLI; it does not
rewrite paths in old transcript messages or guarantee desktop task migration.
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

The historical project-scoped GH configuration was inside the SDK checkout's
`.git/gh-zeus`, not Git-tracked. A fresh clone cannot recreate it. Use the
independent `ZEUS_GH_CONFIG` chosen above, which also works before cloning.
Reauthenticate rather than printing or embedding credentials:

```sh
: "${ZEUS_GH_CONFIG:?Set a project-specific private GH config directory}"
GH_CONFIG_DIR="$ZEUS_GH_CONFIG" gh auth login --hostname github.com --git-protocol https --web
GH_CONFIG_DIR="$ZEUS_GH_CONFIG" gh api user --jq .login
```

Check the reported login is `zeusbuilds`. Do not switch the global account as
a shortcut. Organization SSO/repository permissions may need renewal.
For **absent** checkouts only, clone with the same scoped credential helper:

```sh
: "${ASTER_ROOT:?Set the intended Aster clone destination}"
: "${SDK_ROOT:?Set the intended SDK clone destination}"
: "${ZEUS_GH_CONFIG:?Set the authenticated project-specific GH directory}"
GH_CONFIG_DIR="$ZEUS_GH_CONFIG" GIT_TERMINAL_PROMPT=0 \
  git -c credential.helper= -c 'credential.helper=!gh auth git-credential' \
  clone https://github.com/zeusbuilds/aster-dev.git "$ASTER_ROOT"
GH_CONFIG_DIR="$ZEUS_GH_CONFIG" GIT_TERMINAL_PROMPT=0 \
  git -c credential.helper= -c 'credential.helper=!gh auth git-credential' \
  clone https://github.com/zeusbuilds/rgb-sdk-flutter.git "$SDK_ROOT"
```

For existing or restored checkouts, skip cloning and inspect `git status`,
`git remote get-url origin` and `git log -1` first. Do not reset to the older
evidence commit or discard local changes. Apply author identity locally:

```sh
: "${ASTER_ROOT:?Set the verified Aster root}"
: "${SDK_ROOT:?Set the verified SDK root}"
git -C "$ASTER_ROOT" config --local user.name zeusbuilds
git -C "$ASTER_ROOT" config --local user.email zeusbuilds113@gmail.com
git -C "$SDK_ROOT" config --local user.name zeusbuilds
git -C "$SDK_ROOT" config --local user.email zeusbuilds113@gmail.com
```

### Restore References by Git Revision

Use the repository map and snapshot `origin`/`head` to obtain each source
baseline. Create fresh reference clones at `RN_ROOT` and `RLN_ROOT` rather than
depending on temporary directories from the old machine. In those **fresh,
disposable reference clones only**, fetch and select the comparison revisions:

```sh
: "${RN_ROOT:?Set the fresh RN reference checkout location}"
: "${RLN_ROOT:?Set the fresh RLN reference checkout location}"
git -C "$RN_ROOT" fetch origin dev
git -C "$RN_ROOT" switch --detach e38329eba11cce16e3bea75b8a4e7becd52c0036
git -C "$RLN_ROOT" fetch origin tag v0.16.0-beta.3
git -C "$RLN_ROOT" switch --detach 8777d71d7781b408fcce89c9c965ae29e8ad2300
```

Clone URLs are `https://github.com/UTEXO-Protocol/rgb-sdk-rn.git` and
`https://github.com/UTEXO-Protocol/rgb-lightning-node.git`. Use an authorized
scoped identity where private access is required. If an object is unavailable,
recover its verified bundle/object database; do not substitute latest `dev`
and report equivalent evidence. Package archives come from SDK manifests and
their checksums, not an old Pub/npm cache path.

Normal push pattern, only when there is an approved commit to push:

```sh
: "${ASTER_ROOT:?Set the verified Aster root}"
: "${SDK_ROOT:?Set the verified SDK root}"
: "${ZEUS_GH_CONFIG:?Set the authenticated project-specific GH directory}"
GH_CONFIG_DIR="$ZEUS_GH_CONFIG" GIT_TERMINAL_PROMPT=0 \
  git -C "$ASTER_ROOT" -c credential.helper= \
  -c 'credential.helper=!gh auth git-credential' push origin main

GH_CONFIG_DIR="$ZEUS_GH_CONFIG" GIT_TERMINAL_PROMPT=0 \
  git -C "$SDK_ROOT" -c credential.helper= \
  -c 'credential.helper=!gh auth git-credential' push origin main

GH_CONFIG_DIR="$ZEUS_GH_CONFIG" GIT_TERMINAL_PROMPT=0 \
  git -C "$SDK_ROOT" -c credential.helper= \
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
: "${ASTER_ROOT:?Set the verified Aster checkout location}"
cd "$ASTER_ROOT"
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
: "${SDK_ROOT:?Set the verified Flutter SDK checkout location}"
: "${RN_ROOT:?Set the RN checkout at the comparison commit}"
cd "$SDK_ROOT"
flutter pub get --enforce-lockfile
./tool/generate_pigeon.sh
dart format --output=none --set-exit-if-changed lib test tool
flutter analyze --fatal-warnings --fatal-infos
flutter test --coverage
dart doc --validate-links
RGB_SDK_RN_PATH="$RN_ROOT" dart run tool/validate_rn_parity.dart
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
| Protected `rgb-lightning-node-perf-lab` | 18443 Bitcoin, 50001 Electrum, 3000 proxy | Owner's restored `datacore`, `dataindex` and other declared mounts | Its owner maps the restored root; never its regtest.sh from this task |
| Aster `aster-app-regtest` | 19443 Bitcoin, 51001 Electrum, 3100 proxy | `$ASTER_ROOT/.local/aster-regtest/` | Aster Git: `ops/regtest/compose.yaml` |
| Flutter SDK `rgb-sdk-flutter-regtest` | 18444 Bitcoin, 50002 Electrum, 3013 proxy | `$SDK_ROOT/tool/regtest/data/` plus actual Docker-owned writable state | SDK Git: `tool/regtest/compose.yaml`, `config.sh`, `regtest.sh` |
| Historical Iris `utexo-wallet-devstack` | Defaults include 18443/50001/3000, 3002 issuer, 9736 peer, 3003 Esplora, 18081 VSS, 8080 LSP | Iris `.devstack/` and declared volumes | Iris `ops/devstack.lock.json`; defaults collide with protected perf-lab |
| New Iris bridge `iris_bridge_20261013` | Gateway18088, Postgres26432, Anvil18555, RGB forwarder28090; frontend3000 and Mailpit18025 separate | `$BRIDGE_RETEST_ROOT/stand-data` | Bridge Git: `deploy/local/README.md`; private topology and RETEST.md from backup |

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

### Relocation Checks Before Starting Services

- Map every restored checkout to its captured Git origin/commit and record its
  new root privately. Keep independent worktrees/dirty overlays separate.
- Restored linked worktrees may contain stale absolute Git metadata. Preserve
  the parent common object database and use Git's `worktree repair` workflow
  for the new locations; verify status and refs afterwards. Do not hand-edit
  `.git` pointers or discard dirty work to make a fresh clone look clean.
- Inspect path-valued local configuration without printing credentials. Update
  Compose bind sources, env-file references, local build contexts, certificates,
  AVD metadata and source manifests to the chosen roots. Keep credentials,
  chain generation, asset IDs and operation journals unchanged.
- Aster's checked-in Compose binds are relative to `ops/regtest/compose.yaml`.
  They move with `ASTER_ROOT` when its `.local` state is restored there. Verify
  `ASTER_LOCAL_UID` and file ownership against the new account before launch.
- Recreate FVM links, generated Flutter/Xcode/Gradle configs and local SDK paths
  through the repository setup tools. Do not transplant old absolute build paths
  or assume the Homebrew installation prefix is unchanged.
- App sandbox/Keychain and native wallet-store relocation need their own
  verified recovery contract. Do not bulk-replace strings in wallet databases
  or metadata to suppress a resource mismatch.

These are configuration checks, not authorization to change protected stacks.

### Aster Restore or Fresh Isolated Setup

For **restored** `.local` state and config, do not rerun the initializer. Check
paths, permissions, ownership, network/asset generation and free ports, then:

```sh
: "${ASTER_ROOT:?Set the verified restored Aster checkout location}"
cd "$ASTER_ROOT"
docker compose --env-file .local/aster-regtest/compose.env \
  -f ops/regtest/compose.yaml up -d --wait --wait-timeout 180
docker compose --env-file .local/aster-regtest/compose.env \
  -f ops/regtest/compose.yaml ps
```

For a deliberately **new test-only generation** with no state to restore:

```sh
: "${ASTER_ROOT:?Set the verified fresh Aster checkout location}"
cd "$ASTER_ROOT"
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

For the new bridge retest, set `BRIDGE_RETEST_ROOT` to its restored backup
location. Restore its private `stand-data/config/compose.env`, then inspect the
bridge Git checkout's `deploy/local`
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
: "${ASTER_ROOT:?Set the verified Aster checkout location}"
: "${ASTER_SIMULATOR_ID:?Select a newly verified Aster-owned simulator}"
cd "$ASTER_ROOT"
make verify-generated ios-dependencies
BUNDLE_FROZEN=true BUNDLE_PATH="$PWD/.bundle" \
  bundle exec fvm flutter run --no-pub -d "$ASTER_SIMULATOR_ID" \
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

The October13 app/SDK logs were temporary, non-Git files prefixed
`aster-rgb-upgrade-`. Recover them into a chosen `EVIDENCE_ROOT` from the private
backup, retaining full original basenames. Do not expect the old temporary
directory to exist after reset. Important suffixes after that prefix are:

- `app-committed-tests.log`: 975 exact-clean implementation tests.
- `app-closeout-commit.log`: normal hooks for documentation closeout.
- `app-ios-final.log`: source-equivalent iOS Debug compile.
- `app-android-arm64.log`, `app-android-host-tests.log`: compile/host evidence.
- `sdk-final-coverage.log`, `android-native.log`, `sdk-ios-build.log`.
- `clean-consumers.log`: incomplete run and failure boundary, not a pass.

Committed summaries remain available without those local paths: Aster
`docs/PRODUCTION_REFACTOR_TRACKER.md` at the recorded app commit, and Flutter SDK
`doc/RELEASE_READINESS_TRACKER.md` plus `tool/release_baseline.json` at `7c44506`.
They are summaries/manifests, not substitutes for missing raw evidence. If raw
logs or unpublished fixtures were not backed up, report them missing and rerun
the appropriate checks; do not invent Git links for files that were never pushed.

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
- [ ] New roots mapped by Git URL/commit; no old username, sibling layout or temporary directory required.
- [ ] Worktree metadata, local path-valued configuration and device IDs verified after relocation.
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
