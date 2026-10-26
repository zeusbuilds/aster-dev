# Aster shared local regtest

Aster consumes the existing `utexo_local` development stack. Wallet storage is
app-owned and separate from every infrastructure wallet and from SDK examples.
Do not initialize another stack, run SDK `regtest.sh`, reset chains, remove
containers, or clear existing wallet data to run these tests.

Before configuring a consumer, read the shared folder's `AGENTS.md`,
`docs/CONSUMERS.md`, `artifacts/consumer-config.json`, `README.md`,
`docs/RUNBOOK.md`, `manifests/sources.json`, and `docs/VALIDATION.md`.
Use its exported public RGB contract only after checking the recorded SHA-256.
The contract identity belongs to this preserved local chain and must not be
copied into a public-network configuration or replaced with invented metadata.

## Existing services

| Service | Host / iOS Simulator | Android emulator |
| --- | --- | --- |
| Esplora | `http://127.0.0.1:18094` | `http://10.0.2.2:18094` |
| Electrum | `127.0.0.1:18001` | `10.0.2.2:18001` |
| RGB proxy | `rpc://127.0.0.1:28090/json-rpc` | `rpc://10.0.2.2:28090/json-rpc` |
| Local EVM | `http://127.0.0.1:18555` | `http://10.0.2.2:18555` |
| Gateway | `http://127.0.0.1:18088` | `http://10.0.2.2:18088` |
| Explorer | `http://127.0.0.1:18095` | `http://10.0.2.2:18095` |

EVM chain ID `42161` is a local fixture, not public Arbitrum. The main profile
does not supply an LSP, VSS backup service, or funded Lightning channels. Keep
those app capabilities unavailable; do not treat a healthy indexer as proof of
Lightning or backup operation.

The already existing `wdk-rln-017-qualification` stack is reserved for destructive
regression testing (RLN API `29301`, Esplora `29302`, proxy `29300`). The separate
qualification Anvil uses RPC `29545`, chain `31337`. Never perform reorgs or
interrupted-transaction experiments on `utexo_local`, or substitute these chains
for one another during a bridge operation.

## App configuration

Use ignored `config/shared-stack.ios.local.json` and
`config/shared-stack.android.local.json`. Set `ASTER_NETWORK` to `regtest`,
`ASTER_INDEXER_URL` and `ASTER_RGB_PROXY_URL` to the appropriate endpoints above,
and `ASTER_ETH_RPC_URL` to the local EVM. Take `ASTER_USDT_ASSET_ID` and
`ASTER_USDT_PRECISION` from the shared consumer manifest. Leave LSP/VSS unset.
Reserve free app-process listener ports with `ASTER_DAEMON_PORT` and
`ASTER_LDK_PEER_PORT`; this qualification uses `19745` and `19746`. These are
embedded wallet listeners, not stack services. Do not stop another process to
make a port available.

Build the normal app with the explicitly selected Aster-owned device:

```sh
fvm flutter run --no-pub -d <ASTER_DEVICE_ID> \
  --dart-define-from-file=config/shared-stack.ios.local.json
```

Use the Android file on Android. On Android 17 / target API 37, Aster requests
local network access before native wallet initialization. Allow it in the OS
dialog. Denial leaves wallet initialization unstarted and gives a typed,
actionable failure; allow the permission in system settings before retrying.
Public endpoint profiles do not request this local permission. See Android's
[local network permission documentation](https://developer.android.com/privacy-and-security/local-network-permission).

Local HTTP transport is Debug/Profile only. These defines do not satisfy the
TLS or deployment ownership requirements of a Release artifact.

## Funding and RGB receiving

Create only disposable local test wallets. Obtain an actual new `bcrt1...`
receive address from the app, then use the shared stack's locked funding tool:

```sh
cd "$SHARED_STACK"
./stack fund <NEW_APP_ADDRESS> 2000000
```

Amounts are integer satoshis. The shared stack owns mining and mutation locking.
Keep financial intent, transaction IDs and receipts; inspect the existing
journal before acting on a lost response. Never repeat an uncertain mint or
burn. Never expose a mnemonic, native password, RPC credential or private key
in a command, log or screenshot.

Aster creates witness receive requests only. Receiving does not require output
preparation.
Its sender separately reviews a 1,000-sat Bitcoin output to the recipient plus
network fees. Receive has one QR flow, with no blind/witness selector or output-
preparation action. Amount changes and regeneration also create witness requests.
The app never spends BTC to create a receive request or silently falls back to
blind receive. Sending to a valid blind recipient remains supported.

Flutter SDK blind receive remains available to integrations that require it.
The existing bridge mint protocol accepts blind recipients only because its
request does not carry a witness Bitcoin output amount. Do not pass an Aster
witness invoice directly to that bridge or substitute contract identities. Test
funding through that bridge requires a separate SDK-backed blind receiver,
followed by an ordinary reviewed RGB transfer into Aster's witness invoice.

Previously started preparation journals remain protected. The on-chain mutation
guard checks their authoritative status without creating more outputs. Pending
or uncertain records continue blocking unsafe mutations. Removing the preparation
UI does not prove an old transaction completed, authorize replay, or erase its
journal.

The first receive invoice can be unbound to an asset and amount until the
first valid consignment imports the contract. The sender must review and enter
the intended exact amount. After receipt, verify canonical asset identity,
precision, balance and history; do not manufacture a USDT balance or label a
first unbound invoice as an amount-bound request.

## Device qualification

`integration_test/full_wallet_flow_test.dart` uses production Aster bootstrap,
native SDK, cryptography, repository and real platform storage with a separate
`aster_full_wallet_qa/<run-id>` directory and secure-storage namespace. A unique
run ID is mandatory. Existing runs and financial requests must never be
overwritten or automatically replayed.

`tool/run_shared_wallet_qualification.py` launches one run against the already
operated loopback evidence/controller service on `127.0.0.1:29671`. That
controller must follow the shared consumer contract, mutation lock and durable
mint/burn journals. The runner neither starts it nor provisions infrastructure.
Android requires `adb -s <ASTER_SERIAL> reverse tcp:29671 tcp:29671`.

The `full` stage is currently blocked before QA storage creation, wallet
provisioning or funding with `qa_bridge_mint_requires_external_blind_receiver`.
Its original bridge seeding expected an Aster blind invoice. Enabling it again
requires a separate SDK-backed blind bridge receiver, an ordinary witness
transfer into Aster and verified host conservation/receipts. Do not bypass the
guard, silently re-enable blind receive, or pass a witness invoice to blind-only
mint. Use `lifecycle` for a new disposable namespace. `restore`, `reconcile-mint`
and `reconcile-transfer` require their exact retained fixture/checkpoint and do
not replace full funded qualification.

```sh
FLUTTER_BIN="$(command -v flutter)" python3 tool/run_shared_wallet_qualification.py \
  --device <ASTER_DEVICE_ID> --run-id <NEW_UNIQUE_RUN_ID> --stage lifecycle
```

Use the pinned Flutter, scoped JDK, Bundler and Xcode environment described in
`DEVELOPMENT.md`. The runner records source hashes, consumer/configuration
hashes, events, test output and a private closed-fixture copy under ignored
`.buildlog/full-wallet-20261015/<run-id>/`. A native disposal and verified
host-copy acknowledgement are required for a passing report. Failed runs and
uncertain journals remain intact.

The harness captures the exact wallet-selector `ModalRoute` and requires it to
be inactive, the selector absent and the target wallet committed before another
navigation command. A GoRouter refresh can leave the original push Future
unresolved after actual removal, so its completion is not navigation proof;
Future errors are still observed. Its binding retains a framework-error
latch after an exception has been consumed, while preserving normal Flutter
and driver failure reporting. A late asynchronous failure stops further UI and
financial work. Historical preparation-confirmation receipts remain evidence
for the earlier app and are never replayed by the current witness-only flow.
A failed scheduling run remains failed even when earlier financial steps
completed. Preserve its closed fixture and receipts; do not rerun its financial
requests to repair the report. A fresh full qualification uses a new run ID.

A process-start failure before test entry must not be reported as native
disposal or a closed-wallet backup. The narrowly reviewed Android I/J admissions
requires the immutable failed report with zero events, no test/SDK entry,
unchanged source/SDK/configuration, a stopped process and an absent QA root
before, after and at quiescence. Its separate preservation supplement binds
the full app credential-encrypted/device-encrypted snapshot and exact prior
fixture files. This admits only a fresh isolated run; it never replays a
financial request or turns the failed report into a pass. All other failed
checkpoints retain their ordinary refusal and preservation requirements.

The reviewed K launch names both prior pre-entry failures explicitly:

```sh
python3 tool/run_shared_wallet_qualification.py \
  --device emulator-5582 --run-id aster-full-android17-20261015-k --stage full \
  --admit-pretest-failure aster-full-android17-20261015-i \
  --admit-pretest-failure aster-full-android17-20261015-j
```

Its cold restore uses `--stage restore`,
`--restore-from aster-full-android17-20261015-k`, a new control run ID
`aster-restore-android17-20261015-k`, and the same two explicit admission flags.
These flags admit only the pinned I/J reports and preservation evidence on the
same owned device; they are not a general failed-run bypass. The runner checks
read-only Android framework readiness before creating invocation evidence or
launching Flutter: boot completion and both package/activity services are
required. A zero-exit service query saying the service is absent still fails.
The reviewed data-preserving reboot changes no AVD, wallet files or stack.
After reboot, verify API 37, 16 KiB/fatal compatibility, app UID/data and prior
fixture hashes; restore only controller reverse port 29671. Standard drive
uses `--no-start-paused` with `--keep-app-running`.

The private copy is a local test snapshot, not a portable recovery backup.
iOS credentials remain in the same simulator's Keychain account. Android
credentials remain in the original app's Keystore and encrypted preferences;
do not uninstall or clear that app. Flutter iOS integration can uninstall at
run boundaries, so preserve closed files before teardown and restore only
into a verified empty owned fixture while keeping the same Keychain identity.
Cold-process restore must follow verified process termination and retain the
same two wallet identities, all BTC/BFA balance dimensions and active selection,
with unchanged source/SDK/configuration and original-backup hash. A normal app
launch is separate evidence and must not replace that isolated restore check.
The final iOS J and Android K full/cold-restore reports meet these local
onchain criteria. Earlier failed reports, including zero-event I/J OS failures,
remain immutable; the same AVD recovery preserved the full app archive and
prior fixture files. Both normal main entry points also launch independently;
the matching normal Android APK installs without erase and renders Welcome on
API 37 / 16 KiB with compatibility fallback disabled. That public-screen proof
uses the fresh direct-ADB capture, not the retained stale tool frame. The final infrastructure audit confirms every accepted
app Send from its full Esplora transaction body and rechecks exact financial,
acknowledgement and event evidence after health. It never replays a financial
request or uses `/status` alone as proof of transaction existence. Exact
reports, hashes and qualification limits are in
`SHARED_WALLET_QUALIFICATION.md`.

Device reports distinguish actual UI interaction from repository-level native
payment checks. Simulator/emulator success does not qualify physical camera,
VoiceOver/TalkBack, hardware performance, release signing, mainnet funds,
unimplemented Lightning routes, or upstream reorg and recovery fixes. See
`SHARED_WALLET_QUALIFICATION.md` for the current evidence and remaining limits.

## Historical isolated-stack tooling

`ops/regtest/compose.yaml` and `tool/initialize_local_regtest.dart` remain from
the earlier Aster-owned infrastructure experiment. They are not prerequisites
for this shared-stack workflow and must not be invoked for this qualification.
Their old endpoints (`19443`, `51001`, `3100`) do not identify `utexo_local`.

## Already accepted mint after a harness failure

`--stage reconcile-mint --restore-from <FAILED_FULL_RUN>` is a narrow,
read-only recovery path for the recorded `qa_private_field_rejected` test
failure after an accepted mint acknowledgement. It requires the same owned
device, unchanged consumer/configuration identities, one matching canonical
mint, and a hash-verified closed fixture. It opens the original storage and
secure namespace, syncs the already-issued consignment, validates exact BTC
and BFA state, and closes with another private snapshot. It never funds,
mints, burns, sends or prepares outputs. Other failed checkpoints are refused;
inspect their journals explicitly instead of replaying a financial request.
