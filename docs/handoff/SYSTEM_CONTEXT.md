# Aster, RGB SDK and UTEXO System Handoff

Snapshot: **13 October 2026**, Asia/Kolkata. Audience: the project owner and
the next Codex session after a machine reset. Keep this pack in the **private
Aster repository** and an off-machine backup. It includes internal workspace
context and must not be mirrored into the public SDK repository automatically.

## Start Here

The Flutter SDK and Aster upgrade is committed and pushed. Neither is fully
release-qualified. A clone restores committed code, not wallet data, credentials,
uncommitted sibling work, local services, test evidence or Codex history.

1. Before erasing anything, follow [Reset And Restore](RESET_AND_RESTORE.md).
2. After restoring, give Codex [the resume prompt](RESUME_PROMPT.md).
3. Use [the workspace snapshot](WORKSPACE_SNAPSHOT.json) to identify repositories,
   worktrees and local-only changes. This is metadata, not a source backup.
4. Use [the issue snapshot](OPEN_ISSUES_SNAPSHOT.md) as a dated index. The live
   trackers remain authoritative; do not maintain a competing issue tracker here.

No system reset, wallet export, secret backup, chain reset, mining, transfer or
live service reconfiguration was performed to prepare these documents. A Docker
metadata query did not return and was terminated without changing any container;
current running-service health is therefore **not established by this handoff**.

## Repository Authority and Version Pins

| Component | Authority at this checkpoint | Local location relative to Projects |
| --- | --- | --- |
| Aster Flutter app | Private `zeusbuilds/aster-dev`, `main`; pre-handoff HEAD `1ccbd74f26c2572f168e12e3bf9e8533a3c6eb4a` | `aster-dev` |
| Flutter SDK working repository | Private `zeusbuilds/rgb-sdk-flutter`, `main`, `7c44506fdfe1dae6f3a6fe884f849c7ca2ad028b` | `rgb-sdk-flutter` |
| Flutter SDK public source mirror | `UTEXO-Protocol/flutter-sdk`, `main`, same `7c44506` | App consumes this Git URL |
| RN parity reference | `UTEXO-Protocol/rgb-sdk-rn`, `dev`, `e38329eba11cce16e3bea75b8a4e7becd52c0036`, `1.0.0-beta.37` | Isolated current comparison under `/private/tmp/aster-rgb-upstream-20261013/rgb-sdk-rn` |
| Shared TypeScript SDK core | `@utexo/rgb-sdk-core@1.0.0-beta.9` | Exact archive pinned in SDK `tool/release_baseline.json` |
| Native RLN | `UTEXO-Protocol/rgb-lightning-node`, `v0.16.0-beta.3`, `8777d71d7781b408fcce89c9c965ae29e8ad2300` | Isolated source under `/private/tmp/aster-rgb-upstream-20261013/rln` |
| WebRGB and WC companion | `@utexo/webrgb@0.1.2`, `@utexo/webrgb-walletconnect@0.1.2` | SDK peer manifests and isolated source audit |
| Iris React Native app | Base checkout origin `UTEXO-Protocol/iriswallet-mobile`; newer retest origin `UTEXO-Protocol/utexo-mobile`; these are distinct recorded checkout identities | `utexo-app`, plus linked worktrees and ignored retest checkout |
| WDK RGB module | `UTEXO-Protocol/wdk-rgb-lightning` | `utexo-trial/wdk-rgb-lightning` and worktrees; exact release state differs by checkout |
| Node/Bare native bindings | `UTEXO-Protocol/rgb-lightning-node-nodejs` and `rgb-lightning-node-bare` | Same-named Projects folders; separate newer retest sources/artifacts also exist |
| Lightweight native SDKs | `UTEXO-Protocol/rgb-sdk-swift-light`, `rgb-sdk-kotlin-light` | `utexo-lightweight/` workspace |
| EVM/RGB bridge | `UTEXO-Protocol/bridge-utexo` plus signer, parser, contract and relay repositories | `utexo-app/.devstack/bridge-retest-20261013/` |

At inspection Aster and the Flutter SDK were clean with tracking branches at
the same commit. The public SDK `main` was independently checked through GitHub.
Aster's repository was independently confirmed private; project-scoped GitHub
authentication identified `zeusbuilds`. Do not change SDK origin to its public
mirror. Push SDK commits to both destinations when requested; app work goes to
its private origin. Old GitLab/Jainakin SDK destinations are retired, not fallbacks.

The long-lived `Projects/rgb-sdk-rn` checkout is older (`821ae4f`, beta.32-era).
Do not mistake it for the inspected latest RN reference. Re-fetch `dev` on the
new machine and explicitly record any drift before upgrading further.

## What Each System Is

### Aster versus UTEXO versus Iris

**Aster** is this Flutter wallet product. Its branding, UI and multi-wallet
experience belong to the user. **UTEXO** identifies the RGB protocol ecosystem,
SDKs and services, not a replacement product name. **Iris** is a separate React
Native app with a WDK integration and its own design, product scope, owners,
runtime, credentials, test fixtures and release evidence. Do not merge its
architecture or bootstrap state wholesale into Aster.

The current Aster release scope is Bitcoin onchain and configured RGB USDT
onchain. Historical/future Lightning types and non-mainnet activity remain;
Lightning actions are rejected at the repository boundary, not just hidden by
widgets. RLN 0.16 additionally starts without Lightning on mainnet and rejects
Lightning operations there. The SDK retains non-mainnet APIs for RN parity.

### RGB, Assets and Payment Rails

RGB validates asset state client-side using Bitcoin-anchored commitments and
consignment history. Bitcoin chain data is not a substitute for the private
RGB state and proofs needed to validate transfers. A seed can derive keys; it
does not, by itself, prove that all RGB state, Lightning state or burn journals
have been recovered.

Keep these concepts distinct:

| Concept | Meaning and engineering consequence |
| --- | --- |
| Network | Regtest, signet or mainnet. A service profile named `utexo` is an SDK carrier, not a fourth chain. |
| Product | User-facing economic identity such as Bitcoin or USDT. |
| Representation | Exact network-scoped RGB contract ID, schema, precision and issuer/bridge relationship. A ticker is not authority. |
| Rail | Onchain or Lightning. It is not the asset or blockchain environment. |
| Canonical/linked assets | Separate contract representations may be related by a verified service/registry contract. Never aggregate/substitute by matching names or assume conversion is free or available. |
| NIA/IFA/CFA/UDA/BFA | Different native asset schemas/types and rights. Do not cast non-fungible rights or issuance authority into transferable currency. |
| Integer units | BTC sats; Lightning millisats where the API specifies them; RGB integer base units at the exact contract precision. Fiat is a separate estimate. |
| Total versus available | Ownership, pending/locked amounts and channel capacity are different quantities. Unknown data is not zero. |

The Flutter SDK preserves native UInt64 amounts with `BigInt`. Aster currently
supports the narrower nonnegative signed-64 domain and rejects out-of-range
values. WebRGB ordinary JSON numbers additionally respect JS safe-integer
limits; large transfer history retains an exact decimal string.

### Three Different Meanings of Bridge

1. **Flutter platform bridge:** Dart -> generated Pigeon -> Swift/Kotlin ->
   upstream UniFFI -> Rust RLN. This is IPC/binding code, not an asset bridge.
2. **WDK native bridge:** WDK JS -> Node or isolated Bare addon -> a reviewed
   C-FFI adapter -> RLN. Its binaries and packaging are not Flutter's AAR or
   XCFramework, even when both use the same Rust source commit.
3. **Asset bridge:** EVM contracts, Bitcoin commitments, RGB BFA state, relays,
   connectors, signers and backend services that mint/redeem a bridged asset.
   A method returning a native burn transaction does not establish a payout.

### BFA and USDT

A BFA is a **bridged fungible asset**. The local fixture uses mock USDT locked
on a local EVM chain and RGB issuance/validation tied to the corresponding
bridge event. A real deployment needs an approved asset ID, exact schema,
precision, bridge contracts, chain policy and issuer/route evidence. Regtest
mock USDT and signet IFA fixtures are not real mainnet Tether.

A typical mint path is EVM lock -> observed/validated event -> RGB mint and
consignment -> wallet acceptance after chain/consensus validation. Redemption
is RGB burn -> proof export -> independent proof/finality checks -> signer
authorization -> EVM payout -> observed completion. Every stage has its own
identity and failure/unknown-outcome state. Do not repeat an uncertain burn,
credit unvalidated assets, or report payout from burn success alone.

The currently inspected bridge stand is hub-less: a dedicated mint signer and
three release signers with a 2-of-3 release threshold. Its test/dev enclave
profile is not evidence of a production TEE or production custody deployment.

### RLN, LSP, APay, VSS and WebRGB

- **RLN:** shared Rust wallet/node implementation; native artifacts and their
  exact dependency graph matter as much as wrapper method names.
- **LSP:** service orchestration for liquidity/channels, invoices and linked
  assets. Service capability is not proof of funds, liquidity or product linkage.
- **APay:** asynchronous-payment/address and payment-hash coordination. Hash
  consumption and server-side mappings can be mutations, not safe retries.
- **VSS:** remote versioned state storage with authentication, ownership and
  conflicts. It is not the unsupported `createBackup`/`rlnBackup` API, and is
  not automatically a complete seed-only recovery guarantee.
- **WebRGB:** dApp-to-wallet capability/approval protocol. The host must bind a
  verified origin, wallet, network, permissions and session lifetime.
- **WalletConnect:** transport/session plumbing. A typed request router does
  not provide pairing, peer verification, durable sessions or consent UI.

Disabling Lightning defers funded Lightning/LSP/APay qualification for the
current app scope. It does **not** waive BTC/RGB onchain, BFA/Ethereum (when
advertised), VSS (when used), lifecycle, privacy, platform or supply-chain gates.

## Flutter SDK Architecture and Current Work

Public consumers use `rgb_sdk_flutter.dart`; optional WebRGB consumers use
`rgb_sdk_flutter_webrgb.dart`. Public domain models are separated from native
wire contracts. Pigeon is the chosen bridge for this release, not an accidental
interim implementation to replace during app work.

```text
App repository / trusted SDK consumer
  -> UtexoWallet, typed requests/results, lifecycle/error contracts
  -> RLNBinding / RlnClient and generated Pigeon DTOs
  -> Swift/Kotlin engine-scoped operation and handle ownership
  -> upstream UniFFI-generated native interfaces
  -> Rust RGB Lightning Node and its exact dependency graph

Optional authenticated dApp host
  -> WebRgbWalletConnectSession (router, not complete transport)
  -> WebRgbProvider (approval/capability/revocation boundary)
  -> BurnOperations + app-owned durable journal when burns are enabled
  -> UtexoWallet
```

Do not duplicate lifecycle/concurrency ownership, let a Dart timeout release
serialization while native work still runs, guess native handles, or rewrite
financial native validation in Dart. Generated Pigeon files must come from the
generator. UniFFI-Dart remains a separate evaluation requiring exact API,
async, callback/signer, error, object-lifetime, packaging and parity proof.

The October 13 upgrade delivered exact RLN/RN pins, WebRGB witness receiving
and per-request native signing approval, durable burn failure handling,
external-unlock Ethereum endpoint forwarding, bounded WalletConnect request
routing, proof chunking, consent/expiry/revocation checks and formatted,
byte-stable Pigeon generation. The SDK package line is `0.1.0`, Git-installed
with `publish_to: none`, not a published pub.dev production release.

Important safeguards and accepted differences:

- `sendRgb(skipSync: true)` fails rather than silently dropping the option.
- Backup remains explicitly native-blocked; no fake backup output or success.
- Durable secret storage is the app's job. SDK in-memory minimization remains
  required; Dart strings cannot be promised to be securely zeroized.
- Standalone Dart BIP340 signing requires explicit experimental opt-in. Native
  wallet/node signing is a different identity/path and remains the normal path.
- The WebRGB host payout-chain allowlist is intentionally stricter than RN.
  Allowlisting is authorization, not validation of a bridge redemption route.
- Pending burns fence new mutations until independent reconciliation; proof
  export/revocation rules are not replaced by a matching txid or old consent.
- Native/regtest qualification is local-only by decision, not skipped evidence.
- PKG-006 keeps production supply-chain mode fail-closed. Upstream checksums
  and beta artifacts are not trusted signatures/reproducible source attestations.

### Exact Candidate Evidence

| Evidence | Result at the recorded checkpoint | What it does not establish |
| --- | --- | --- |
| SDK Dart suite | 429 tests; about 88.0% package coverage | Native-funded behavior or complete fresh file audit |
| SDK Android bridge | 30 JVM tests | Installed Android execution |
| SDK iOS | Simulator app and dual-architecture XCTest bundle compile | XCTest execution or funded lifecycle |
| SDK static/docs/generation | Strict analyzer, Dartdoc, API/drift, baseline and internal-beta gates pass | Production supply-chain pass |
| Aster exact implementation commit `1a7ca65` | 975 tests; 14,736 / 16,714 lines = 88.17% | Physical devices, funding or signing |
| Aster Android host | 3 storage-channel tests; ARM64 Debug APK compile | Runtime endpoint reachability or 16-KiB compatibility |
| Aster iOS | Source-equivalent Debug simulator compile | Device/simulator launch, fresh XCTest execution or signed archive |
| SDK clean consumer matrix | Partial path/Git consumer compilation only | A complete clean exact-current matrix |

App closeout `1ccbd74` was documentation-only. Its parent `1a7ca65` owns the
implementation and exact clean-commit test run. SDK `7c44506` follows upgrade
`16c750d` with generator formatting. Native evidence must retain its actual
source-equivalence/commit boundary, not be relabeled as every later commit.

Evidence locations are enumerated in the restore runbook. Some large compiled
products were removed for disk space after hashes were recorded. Never claim
they still exist just because an earlier report has their path.

### Remaining SDK Work

At snapshot: **279 findings: 246 Verified, 22 In progress, 2 Open, 2 Blocked
upstream, 7 Accepted constraint**. The 26 unresolved rows are not necessarily
26 still-unimplemented functions: many require independent native/evidence
closeout. See the exact rows in the issue appendix and their detailed audit
registers before changing code.

The main groups are complete WalletConnect transport integration; funded
BFA/Ethereum/proof/recovery and VSS qualification; installed iOS/Android and
clean-consumer matrix; native lifecycle/error/bounds regression evidence;
release evidence/governance reconciliation; and the unfinished fresh audit
(OCT-006 records 160 pending repository-file reviews).

OCT-027 tracks native BFA event selection: an earlier wrong-amount event can
hide a later correctly backed mint for the same operation ID. A normal valid
mint passing elsewhere does not close that adversarial case. LSP-019 tracks
missing upstream idempotency/reconciliation contracts. Do not compensate with
client-side auto-retry or invented success.

## Aster Architecture and Product Contract

```text
View -> generated Riverpod ViewModel -> Repository
     -> one WalletRuntime -> RgbWalletEngine -> public SDK
     -> injectable storage/network/platform services
```

Keep simplified MVVM, immutable app models, generated Notifier/AsyncNotifier
patterns, unidirectional flow and operation-specific loading. No use-case layer.
UI must not import the SDK, storage, HTTP or platform plugins directly.

One app-owned `WalletRuntime` serializes provision/open/sync/suspend/resume/
switch/destroy. `RgbWalletEngine` holds the one SDK wallet and converts native
types. New stores use init/unlock; persisted stores use reinit. The registry
commits ready profiles only after real activation and preserves rollback or
reconciliation-required failures. Wallet switching restores the previous owner
when safe; unknown outcomes stay quarantined.

`AppResult<T>` / `AppFailure` carry typed redacted failure categories,
retryability and reconciliation state. App HTTP uses explicit deadlines and
bounded jittered retry for idempotent reads only. Financial mutations do not
automatically retry. SDK/native timeout ownership is not bypassed.

Secure storage contains the per-wallet mnemonic and random native database
password together. App metadata, native wallet directories and credentials
must agree. iOS uses non-synchronizing this-device-only Keychain storage;
Android storage and backup policies also deliberately constrain restoration.
Copying only files or reinstalling over a surviving Keychain record can produce
the recurring resource-mismatch error. This is not permission to erase data.

Hot reload (`r`) is normal UI iteration. Hot restart (`R`) replaces Dart without
releasing the existing native engine owner in the pinned SDK. Quit and relaunch
the app process for a full restart; do not delete wallet data or add private
platform-channel workarounds. Cold-start failures still require investigation,
not blanket attribution to this development limitation.

### Locked UI and UX Decisions

- Preserve the user's original visual language and Home content. Architecture
  cleanup is not permission to redesign screens. Do not reintroduce retired
  wallet integrations or unreleased-app migration paths.
- Keep the existing palette exactly, DM Sans for text and Public Sans for
  numeric spans only. Fonts are bundled. Units/labels/addresses remain UI type.
- Keep semantic ThemeData/ColorScheme/TextTheme/ThemeExtension roles: spacing,
  component metrics, iconography, strokes, radii, typography, state layers,
  motion, art and insets. Reusable literal values belong in that system.
- Pills use true pill shapes; cards, tiles, fields and sheets use squircles.
  Circles are for genuinely circular elements. No Material ink/splash effects.
- Keep semantic haptics, accessible queued/deduplicated toasts, stable-size
  loading buttons, disabled prerequisite states and reduced-motion support.
- Home has **no pull-to-refresh**. Its eye control and BTC/sats unit preference
  are durable. Market price/history retry quietly; missing data uses the
  skeleton/approved chart animation. Only classified offline chart state says
  "You're offline" / "Tap to try again". No generic failure/reload message.
- Home Bitcoin fiat value is right-aligned to the normal screen padding.
  Do not restore the removed CoinGecko credit without resolving the separate
  attribution/commercial-policy issue; its removal did not waive that issue.
- Onboarding and Add Wallet share the **static blue mesh** and content-switch
  choreography. Do not restore the rejected animated mesh or white flow.
- Create: welcome -> recovery phrase -> verify seed phrase -> wallet name.
  Import: welcome -> twelve-word grid -> wallet name. Add Wallet uses matching
  artwork but a multi-wallet intro, back header and Add New Wallet / Import
  Wallet actions instead of the welcome logo/grid treatment.
- Quiz positions are **3, 7, 11**, three equal-width options per row, matching
  recovery-chip height/radius; green/red feedback, no radio ornament. This
  supersedes the older tracker decision referring to 3/6/9/12.
- Import uses twelve editable recovery-style cells, not the old carousel.
  Lowercase input, no check/cross icons, color feedback; word 12 always Submit
  and focuses the first invalid/missing word or continues when valid. Final
  checksum still matters. No validation banner above Continue.
- Navbar enters/exits with welcome choreography, then remains stable between
  subsequent steps. Step indicators: height 4, active width 20, collapsed width
  8; indicator transition 500 ms, independently of content choreography.
- Recovery reveal/hide is a small icon/text action below word 12, right-aligned,
  not the navbar icon. Copy remains a text action without its old icon. Primary
  action/text-action spacing is 8; translucent-button loader uses primary.
- Name input has no extra label/blue active outline; outside tap unfocuses,
  going back and returning resets draft naming. Completion/switch returns
  directly Home, preserving the animated selection confirmation timing.
- SafeArea, persistent viewPadding and keyboard viewInsets have separate
  meanings. Preserve keyboard/focus behavior; investigate clipping/scroll bugs
  without replacing layouts or suppressing accessibility scaling.

### App Capabilities and Limits

Send/Receive model four target choices, with Lightning disabled as Coming later.
RGB needs a configured exact contract. Send handles real validation and integer
amounts; fee-aware Max remains unavailable where native semantics cannot
support it, not approximated. Receive owns real requests, amount sheet,
copy/share and deadline/error state. Swap is a truthful non-executing preview.

Activity normalizes stable source identities, deduplicates, sorts and routes
details by ID. Outgoing Send/Burn/Inflation uses the SDK's requested recipient
amount, not native change allocations. Missing amounts stay unknown. Settings
include currency/region/Bitcoin units and read-only service configuration.
Secret/xpub disclosure must retain the authentication/security gates.

At pre-handoff snapshot: **458 findings: 424 verified, 34 blocked**, plus 2
accepted constraints (PKG-006 and no swap backend). File inventory: 585 rows,
521 verified, 46 reviewed-clean, 18 blocked. This handoff adds documentation
rows; historical counts are not the resulting repository count.

Principal release gaps: exact-candidate funded/device/physical/performance
matrix, 16-KiB native Android ELF, SDK privacy/SPM packaging, complete WebRGB
consent/session product, final bundle/signing identities, disclosure/capture
security policy, service/asset registry and market deployment, store/privacy/
export policy. The issue appendix contains every currently unresolved row.

## Iris, WDK and the Bridge Retest

These are related workstreams, not dependencies that Aster can start using
implicitly. Their source and tests must stay separate from Flutter evidence.

Iris base checkout is `Projects/utexo-app`, origin
`UTEXO-Protocol/iriswallet-mobile`, `dev` at `21fa0f4`. It has substantial
uncommitted source, test and documentation changes. Its React Native New
Architecture uses Expo, TanStack Query, SecureStore and one WDK Bare worklet.
The older base manifest pins WDK/Bare beta dependencies and a moving WDK dev
dependency; the newer release/retest checkout is a different candidate.

The retest Iris checkout specifically records origin
`UTEXO-Protocol/utexo-mobile`, branch `release/rln-0.15.0-beta.3`, commit
`243fb047011b872cb78d9187a73aa3a933bd26de`. Do not change either existing
remote automatically or assume their permissions/branches are interchangeable.

Preserve `Projects/pr-series/` as well as its parent repositories: linked
worktree `.git` files point back to parent `.git/worktrees` state. The WDK
family also has separate worktrees beneath `Projects/utexo-trial/`. Do not
assume the first folder or a branch name identifies the latest native version.

### Newest Local Bridge Evidence Found

Read `utexo-app/.devstack/bridge-retest-20261013/RETEST.md` first, then its
`sources.json`, result records and the bridge's `deploy/local/README.md`.
The ignored retest directory contains source edits, wallets, state, binaries,
logs, certificates and an Android AVD. **It is not a disposable build cache.**

The report records:

- Frontend `feat/onbording` at `c0edab6377f22de7faee28750933e7144c01ac31`,
  including merged PR83; backend dev at `a97d0605`.
- Iris release flow includes session fix `243fb04`; Bare artifact identity
  `cc62bf3a1765d89cb8b0b990ea16a47936f799de` from CI run `38213919881`.
- Dedicated local Bitcoin regtest and **persistent local Anvil**, chain ID
  42161. The matching number is NOT public Arbitrum. No real EVM funds here.
- Real mTLS-enabled backend readiness and 14 backend test assertions passed:
  20 mock USDT received, 0.02 burned and paid out, quorum/SPV and persisted
  completion checked. This was a backend test wallet, **not Iris/Flutter/WC**.
- Initial beta.43 receiver rejected the deployed contract's event shape.
  Saved consignment independently validated with beta.47; a separate fresh
  beta.47 receiver completed a distinct operation. The original failed wallet
  was preserved, not repaired by manual balance changes.
- Frontend's `POST /api/v0/unlock/verify` returned 404; its missing handler was
  associated with still-open backend PR470 at that test. Do not bypass auth or
  call frontend redemption complete. Re-check PR/server state after restore.
- Frontend test/build: 1,433 tests; Iris regression: 2,735 tests. Android
  installed on an API36/16-KiB emulator in that task. These are that report's
  results, not tests rerun for this handoff or Flutter's AAR qualification.
- Browser frontend `localhost:3000/console`; test-only Mailpit at port 18025;
  Android RGB transport at `10.0.2.2:28090`, with an internal proxy preserving
  the exact endpoint. Account creation/mobile pairing were still pending.

The fixture asset is recorded in the private retest report. Do not copy its
contract ID into Aster or hardcode it into production. Restore the exact
chains, contracts, proofs, wallet stores and journals as one generation, or
explicitly create a new isolated fixture and label it new.

### WDK/Bare versus Flutter Qualification

The newer Bare upgrade report records a seven-target build matrix, Node a
five-target runtime matrix, and separate source/provenance/ELF checks. That
does not fix the upstream Maven AAR consumed by Flutter: its two 64-bit RLN
ELFs were independently found to have 0x1000 LOAD alignment. Different binary
pipelines require independent checks even at the same Rust commit.

Older WDK reports cover 0.11/0.13/0.15 and historical failures including
persistent-signer reopen, RGB reorg settlement, strict signing and Lightning
funding/force-close recovery. Treat each as dated evidence; trace the exact
current source and qualification before declaring it fixed or still reproduced.

### Lightweight SDKs and Other Sibling Work

`Projects/utexo-lightweight` is a non-Git workspace containing Swift/Kotlin
SDK repositories, a shared Rust local signer, gateway PR174 work and many
workspace-level review documents. Both native SDK repos are dirty; the shared
signer and root docs are not protected by a top-level Git remote.

These SDKs use a high-level UTEXOWallet facade with gateway-assisted operations
and local intent validation/signing. They are not the Flutter platform bridge
or a reason to change Aster to a gateway architecture. Their latest September
29 handoff/function-status documents supersede earlier broad progress reports.
Durable submission/recovery and deployment contracts remain explicit gates.

`rgb-lightning-node-perf-lab`, `rgb-ops-perf-lab` and
`rgb-protocol-perf-lab` are separate performance/source investigations.
`Projects/rln-lightning` contains mainnet guard/startup branches, local notes
and repro state. Preserve them; their names do not grant this task ownership.

## Newly Identified Context Corrections

These are handoff follow-ups, not silently closed release findings:

| Follow-up | Verified observation | Required next step |
| --- | --- | --- |
| HANDOFF-01: external-signer burn wording | Pinned RLN `8777d71` has `src/rgb.rs::rgb_burn` using burn_begin -> sign/validate PSBT -> burn_end in external mode. RN beta.37 and Flutter signers still gate facade burn capability; Flutter docs say native unsupported. | Correct the native-versus-facade distinction in the SDK tracker/docs, inspect intended RN parity policy, and test before widening capability. Do not flip supportsBurn just to match WDK. |
| HANDOFF-02: version labels in sibling reports | Bare's October12 report labels source `8777d71` as 0.15, while Flutter's verified published tag/manifest calls it 0.16. | Use exact source/artifact identity and reconcile metadata with that workstream; neither label alone proves artifact contents. |
| HANDOFF-03: stale current-looking prose | SDK older headings still say dirty/uncommitted despite pushed commits; app DEC-048 says four quiz words despite source `[3, 7, 11]`; REGTEST says refresh Home although pull-to-refresh was removed. | Reconcile these documentation claims during the next owned docs pass. Preserve dated evidence rather than bulk replacing version strings or replaying superseded UX. |
| HANDOFF-04: recoverability is not a clone | Dirty Iris/lightweight repos, ignored bridge workspace, non-Git root docs and `/tmp` evidence exist. | Complete and test an encrypted off-machine backup before reset. A metadata list or this handoff cannot restore their bytes. |
| HANDOFF-05: current service liveness | Docker metadata query stalled during handoff; no environment was restarted. | Re-establish bounded read-only Docker/port health after restoring. Do not infer down or healthy. |

## Where to Resume Engineering

1. Complete restoration verification, including dirty sibling work and secret
   availability, before any destructive cleanup or dependency upgrade.
2. Reconcile HANDOFF-01/02/03 and candidate evidence dates against source.
3. Finish WalletConnect transport/session/approval implementation under SDK
   OCT-031 and Aster SDK-015. Missing project identity blocks live relay tests,
   not writing correct code. Avoid irreversible burn exposure without the full
   host authorization and reconciliation contract.
4. Run exact clean-consumer and installed iOS/Android lifecycle/regtest matrix
   on isolated fixtures. Do not reuse the Iris stand without explicit ownership
   permission; reproduce its setup separately when useful.
5. Arrange BFA adversarial validation/proof/recovery and VSS infrastructure
   qualification. Resolve native event-selection and Android artifact blockers
   through approved upstream changes and immutable replacement artifacts.
6. Complete pending independent file review and owner/security decisions.
   Record each finding and evidence boundary before final release promotion.

Internal-beta allowance is not automatic approval of a particular build. No
current whole-product signet or funds-bearing mainnet production qualification
is asserted. Do not set a target such as "100% ready" by waiving evidence.

## Authoritative Reading Order

App: README, `docs/PRODUCTION_REFACTOR_TRACKER.md`, architecture/SDK integration,
security, testing, regtest, development, presentation systems, typography,
barrel exports and release checklist. Current source and the latest user design
decisions resolve historical prose conflicts; document the conflict explicitly.

SDK: README, `doc/RELEASE_READINESS_TRACKER.md`, compatibility/divergence,
WebRGB/burns, integration security, bridge behavior, coverage and release
evidence schema; then `tool/release_baseline.json`, parity manifests,
test matrix and native provenance. Reconcile status with code and exact tests.

Iris/bridge: latest ignored RETEST/source manifest first, current checkout's
PRD/release tracker next, then dated WDK upgrade qualification. The October5
comparison is historical and must not override October12/13 source evidence.

The workspace snapshot records full paths/branches. Original Codex tasks are
listed in the reset runbook. This pack intentionally contains no raw transcripts,
private keys, tokens, seeds, passwords, database exports or production endpoints.
