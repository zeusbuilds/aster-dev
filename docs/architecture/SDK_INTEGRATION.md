# RGB SDK Integration

The app consumes `rgb_sdk_flutter` through its stable public Dart API. Native
wire DTOs, Pigeon messages, platform channels, and SDK-owned storage are not app
architecture boundaries.

## Reproducible Dependency

Aster's source candidate pins the SDK in the private repository
`https://github.com/zeusbuilds/rgb-sdk-flutter.git` at immutable commit
`68a690916eabe96407c03669d569bf86babb8e72`. The manifest and portable Git lock
name the same full commit. Authenticated restoration into an empty Git cache
passed without a local path override; the hosted Pub cache was reused. All 74
SDK Dart source files match the tested fixture. This does not claim a fully
cold hosted-dependency restore or native artifact publication.
The credential belongs in the developer's credential store or CI secret, never
in the dependency URL, lockfile or repository.

CI uses a read-only deploy key restricted to the SDK repository, supplied from
the encrypted App Actions secret `SDK_READ_SSH_KEY`. Its ordinary
`GITHUB_TOKEN` is scoped to the workflow repository, as
[GitHub documents](https://docs.github.com/en/actions/concepts/security/github_token).
The reviewed helper creates runner-only credential files, pins GitHub's host
key and rewrites only the exact SDK URL. Setup is restricted to trusted events;
an always-run step removes those credentials immediately after locked Pub
resolution. Fork pull requests receive no SDK key. The source must not enable
`pull_request_target` to bypass that boundary.

An isolated real read matched the exact SDK commit with owner tokens removed
and global/system Git configuration disabled. Credential mode was `0600`, and
cleanup removed its runner directory. Eight offline helper tests and 23 focused
governance tests pass. These local checks do not claim a remote workflow result.

This source pin exposes the durable-send Dart and bridge API. It does not
publish the matching native binaries. The official older native artifacts
remain unchanged and fail closed with unsupported durable sends; they never
fall back to a one-shot payment. A verified ignored binary fixture is still
required for local native protocol qualification. Authenticated Git restoration
and host tests do not establish a usable native payment release.

Historical published baseline: public SDK beta.2 commit
`992b86ee528d0811bd17cedca901de08561c1982` added typed public-contract import,
safe native diagnostics, authoritative RGB invoice recipient type and cleanup
quarantine. It retained the derived Android AAR published in
[v0.2.0-beta.1](https://github.com/UTEXO-Protocol/flutter-sdk/releases/tag/v0.2.0-beta.1)
and its immutable URL/checksum. The historical empty-Git-cache restore binds
beta.1 commit `c4e3c2d`; it is not a restore of a later candidate. A separate
empty Gradle cache fetched that release AAR and verified its size/SHA-256.
Those checks qualify the identified historical dependency, not current funded
or release flows.

Do not replace the commit with a branch, tag, moving reference, or local path
in a committed change.

After changing the SDK pin intentionally, clear app build outputs before
resolving dependencies. Immutable Git pins use different Pub checkout paths;
stale Kotlin incremental outputs can otherwise omit plugin classes even when
Gradle reports compilation as up to date. Then run:

```sh
fvm flutter clean
fvm flutter pub get
fvm dart run build_runner build
fvm flutter analyze --fatal-warnings --fatal-infos
fvm flutter test
```

Both iOS and Android builds are required for release acceptance of a new SDK
commit. A source-only candidate push does not close those platform gates;
Android builds remain deferred at the author's direction.

The published native baseline targets RN `1.0.0-beta.39` (commit
`41ff170f794edff2a1822a672ddab37e29505f14`), core `1.0.0-beta.9`, WebRGB
`0.1.3`, and RLN `0.17.0-beta.3`. The app's Flutter 3.47.7 / Dart 3.13.5,
iOS 18.5 minimum, Android compile/target SDK 37 and Java 17 compilation already
satisfy its requirements. Native artifacts follow the SDK's checked-in
baseline and checksum-verifying hooks; never reuse binaries from a previous
Pub checkout by copying them manually.

The Android candidate replaces the official RLN AAR's 4 KiB-aligned JNI
libraries with a derived 16 KiB build of the exact RLN `0.17.0-beta.3` source.
The SDK baseline pins coordinate
`com.utexo.flutter:rgb-lightning-node-android:0.17.0-beta.3-16k.1` and AAR
SHA-256 `ca1aa12d44c1e83c0a0f51a38c7bf1486e0ea3ac796dcc02d479acbdf4d832c5`.
Its recorded recipe preserves official non-JNI AAR contents and validates
generated Kotlin bindings, FFI exports and runtime dependencies before and
after stripping. This build contains no WDK PR45 source overlay. That open PR
proposes a P01 lifecycle repair across native core, UniFFI, C-FFI and Node, with
source/host progress but pending mobile closure/replacement and funded iOS
qualification; P02/P03/P04/P06 remain open. Its overlay is absent from the
published RLN 0.17 release consumed here. The local build record is not a
signed provenance or independent reproducibility attestation.

Historical SDK evidence includes the Android 17 / 16 KiB native Flutter signer test
(1/1), 30 JVM bridge tests, all eight packaged native libraries passing ELF
checks, and APK ZIP alignment. The iOS 27 native signer test (1/1) and 26 Swift
tests also pass. The final SDK commit passes 496 host tests and coverage policy
(88.3% package coverage).

The corresponding historical Aster candidate passed 977 host tests, fatal
analysis, generation, documentation and all normal repository policy gates. Its Debug builds launch to visually verified
welcome screens on iOS 27 and Android 17. All 25 native libraries in the exact
Android APK pass ELF inspection and 16 KiB ZIP alignment. That APK runs on an
API 37 guest with 16,384-byte pages and both linker/package compatibility
fallback disabled; its extracted RLN library separately passes native contract
and health checks. The underlying SDK ELF/load defect is fixed in this local
candidate. SDK-004's release AAB/split-APK qualification remains open. No funded,
backend, wallet restore or payment qualification follows from these checks.

The app explicitly disables Swift Package Manager through
`flutter.config.enable-swift-package-manager: false`. All native plugins use the
locked CocoaPods graph while the SDK lacks SwiftPM support. This also avoids
missing plugin modules in a clean hybrid restore.

## Upgrade Contract And Feature Coverage

| App path | Stable SDK contract | Upgrade handling |
| --- | --- | --- |
| Create/import | generateKeys, validateBip39Mnemonic, init, unlock | App owns secrets and commit/rollback; no new-store init on persisted data. |
| Restore/switch/resume/dispose | reinit, shutdown, destroy | One serialized app owner; native deadlines and quarantines remain authoritative. |
| Home/balances | getBtcBalance, getAssetBalance, getNodeInfo, listChannels | RGB read values are BigInt. Narrow only after non-negative signed-64 range checks; sum exactly, never via double. |
| Activity/details | listTransactions, listTransfers(assetId), listPayments | WaitingBroadcast has a dedicated app status. An unallocated pending/failed receive has unknown amount, never its requestedAssignment amount. Settled fungible records still require actual positive allocations. |
| Send/receive | getAddress, decodeRgbInvoice, decodeLnInvoice, onchainReceive, onchainSend, sendBtc, createLightningInvoice, payLightningInvoice | Identity, network, expiry, amount and mutation-outcome checks are retained. RGB decoded amounts use checked BigInt conversion; non-fungible instructions are rejected. |
| Fees/settings | estimateFeeRate, getNetworkInfo, getNodeInfo | Fees remain sat/vbyte; network metadata and account xpubs stay behind the adapter. |
| Network policy | getNetworkDefaults | SDK owns indexer/proxy defaults. The LSP resolver is not exported, so the reviewed UTEXO signet LSP URL remains explicit app deployment policy, validated and shown in Settings. |
| Errors | Typed SDK exceptions | Quote/proof verification failures and LNURL business rejections are not connectivity failures and are not automatically retryable. Raw reasons, response bodies and credentials never cross to UI. |

Aster intentionally supports the configured USDT contract ID, including BFA
inventory, not arbitrary ticker-based or linked-asset substitution. Lightning
send/receive choices stay visible but disabled as Coming later on every network.
Direct repository requests also fail before any native work. Non-mainnet
existing Lightning balances/history remain visible; mainnet skips those APIs
because RLN 0.17 has no Lightning runtime there. Other errors are never converted
into empty balances/history. Outgoing RGB Send/Burn/Inflation uses the SDK's
exact recipient amount rather than change allocations; absent amounts remain
unknown. The upgrade does not
add Lightning Addresses, APay proofs, LSP relay/bridge/channel provisioning,
linked/canonical asset selection, inflation, PSBTs or native VSS backup UI.
These require explicit app models, product flows and funded integration proof;
the presence of methods in the dependency is not evidence they work in Aster.
Detailed refresh, UTXO existence and linked-IFA metadata are SDK capabilities,
not newly exposed app APIs. Existing sync uses syncWallet; fee-aware Send Max
and Swap remain unavailable rather than approximated or simulated.

Aster's RGB Receive policy is witness-only, including initial requests, amount
changes and regeneration. The app has no blind receive selector, output-
preparation action or automatic fallback. New receive requests do not spend BTC.
Flutter SDK blind receive remains supported for other consumers, and Aster Send
still accepts valid blind recipients. The current bridge mint protocol requires
blind recipients; its funding flow needs a separate SDK-backed receiver followed
by an ordinary RGB transfer into Aster. It is not a direct Aster Receive route.

The app retains the reader and mutation fence for preparation journals from
earlier versions. Observational reconciliation can establish their status before
later on-chain mutations. A pending or uncertain record stays protected and is
never cleared or replayed because the Receive controls were removed. This policy
does not qualify mainnet or resolve historical uncertain transactions.

The optional SDK WebRGB provider supports witness receiving and approved native
message signing. Its WalletConnect router is not a complete connection flow:
Aster has no live WalletKit pairing/consent integration or configured Reown
project ID. These remain explicitly tracked; no Connect or burn success is
simulated. BFA/Ethereum and VSS service qualification and PKG-006 still prevent
a mainnet-ready claim.

The SDK reads the full UInt64 RGB range; Aster's supported amounts and sums
remain `0..9223372036854775807` smallest units. Values outside that domain fail
closed. This is an app limitation, not a claim that the SDK cannot represent
them. Bitcoin Lightning values remain millisatoshis; node.localBalanceMsat is
derived from whole localBalanceSat, not a new source of sub-satoshi precision.
Unbound no-asset receive requests cannot appear in an asset-specific feed until
native identifies their asset; they are never guessed to be USDT.

## Optional Local Override

When developing the SDK and app together, create an ignored
`pubspec_overrides.yaml` in the repository root:

The example below assumes sibling clones only for illustration. Replace `path`
with your SDK checkout's actual absolute path or a path relative to Aster;
neither the old machine's directory layout nor sibling clones are required.
Pub YAML does not expand shell variables such as `$SDK_ROOT`. Normal installs
use the immutable private Git source dependency above with authenticated access
and no local SDK checkout. This is separate from native artifact qualification.

```yaml
dependency_overrides:
  rgb_sdk_flutter:
    path: ../rgb-sdk-flutter
```

Run `fvm flutter pub get` after adding or removing the file. Compilation,
analysis, documentation, test, and repository-verification Make targets enforce
the committed lockfile and regenerate ignored sources before consuming that
graph. Before production-candidate lint, integration or release evidence, remove
the override, run `make dependencies`, and confirm that `pubspec.lock` contains
the immutable Git `resolved-ref` above. The override is ignored by Git and is
never supported for public-release evidence. The local source qualification
described below does not replace that release requirement.

## October 24 durable on-chain recovery candidate

The ROOT-01 work adds a native prepare/commit/status/cancel protocol and an
app journal version 3. The private immutable SDK source pin exposes its APIs,
so an authenticated source restore and host tests do not require an override.
The official native binaries do not contain this protocol. Exercising it
locally therefore requires the verified ignored binary fixture described
below. This is not a qualified native release or a production payment build.
Never remove native preflight, fall back to a one-shot send, or bypass artifact
verification to make an older binary appear compatible.

The sibling SDK's `native/durable_onchain_manifest.json` pins the original RLN,
RGB library and Lightning source revisions plus the reviewed recovery patches.
Its candidate builder stages a separate, manifest-verified arm64 iOS Simulator
SDK. Point `pubspec_overrides.yaml` at that explicit fixture for native candidate
qualification, run the matching Flutter toolchain's `pub get`, then install
pods. The authenticated Git source pin or a sibling source-only override is
sufficient for host tests, but both still use the unsupported official native
artifact unless the verified fixture is selected. Keep the committed dependency
Git-based and bound to its exact source commit. Update native artifact versions
and checksums only after qualified publication; never commit the fixture path.

New SDK command envelopes use version 2 and bind the canonical network and both
full account XPUBs through a domain-separated digest. They do not bind an
absolute container path: iOS may relocate an intact app directory during an
ordinary update. Each recovery call verifies the live account identity and
current physical directory inside a lifecycle lease. Older unpublished SDK
version 1 envelopes retain their original path and fingerprint; they are never
silently migrated. This SDK envelope version is separate from the app journal
version and the unchanged native request schema.

The app creates and validates the immutable request, then checks native support
before saving its intent. Version 3 records distinguish an intent created
before Commit from one whose Commit boundary was durably authorized. The former
proves no payment was submitted even when preparation or journal cleanup still
needs attention. Older app version 2 records remain conservative; their
immutable accepted receipt bytes are preserved rather than rewritten as version
3. A preflight failure creates no payment record or possible-payment UI entry.

Native preparation durably retains the transaction before committing
reservations or authorizing End. Commit can release only those saved signed
bytes. A Commit exception triggers at most one observational read of that exact
native operation in the same user action. Exact Accepted produces the success
screen; a durable Rejected certificate with End never authorized produces a
known non-send. Anything else remains genuinely unknown. Prepare, Commit, proxy
upload and broadcast are never automatically repeated. Exceptions, an empty
history, similar amounts and elapsed time are not rejection certificates.

Payment certainty and permission to mutate are separate. Exact native Accepted
remains accepted if Aster cannot persist or archive its required local receipt:
Send returns success, retains the exact evidence, and keeps a wallet-scoped
storage-repair fence. A known non-send may similarly need protected cleanup.
Neither becomes an unknown payment merely because local persistence or later
native-owner recovery fails. Required repair must finish before another
financial mutation; stronger native-owner quarantine still blocks native
access independently. Activity enrichment and status projection are read-only,
so a failed archive write cannot hide the receipt or its Check action.

The existing transaction-details Check action never commits. It inspects the
same authoritative operation and can obtain a durable cancellation certificate
for a preparation that was never authorized for End. If an RGB invoice expires
between preparation and Commit, rejection requires that certificate; an
unavailable or contradictory result preserves protection. The separate
`resumePaymentSubmission` repository action can complete an already-authorized
operation with its saved transaction. The current UI does not call it, and no
screen invokes it automatically.

Certified pre-dispatch rejections carry allowlisted native reason codes for
funds, allocations, recipient, invoice expiry, amount, fee, network,
configuration and storage. Aster maps these only after the certificate proves
nonexecution; arbitrary native error text cannot provide that proof. Invalid
input, fee review, expired invoice and configuration failures do not become
retryable without the appropriate changed input or review.

Send reviews capture the wallet ID before queued work. The ViewModel and
serialized repository callback reject an owner change before fee reads or
native dispatch. Late clipboard/read results cannot restore the prior wallet's
form. Recovery evidence is retained separately for each wallet. A payment-only
fence permits audited safe reads, ordinary Bitcoin receive and a serialized
switch to another wallet; it does not permit another financial mutation in the
fenced wallet. A stronger native-owner failure cannot be cleared by these reads.

Native work runs on the SDK's owned worker with the RGB Tokio context available
to the durable commit path. A deadline retains queue ownership until that work
drains. Bounded non-sending identity, pure invoice and exact-status inspection
remain available after drain; ordinary work remains quarantined until Aster
reopens the same persisted native owner. Failed reopen retains the stronger
quarantine. No timeout causes monetary replay or an automatic cancellation.

An explicit Send therefore shows the success screen when acceptance is known,
or one action-owned toast. Activity uses one compact entry only in the matching
asset history; references and deliberate recovery actions live in existing
transaction details. Operational paragraphs are removed from Send, Activity
and retained Receive content. Receive preparation keeps concise required or
pending states and explicit reviewed confirmation; it never repeats uncertain
output creation. Toast ownership follows route and wallet context, including
popup presentation lifecycle without invalidating a parent confirmation action.

Version 1 unidentified one-shot records remain protected. They contain no
native operation identity, so an absent newer native operation cannot prove that
an older payment never happened. RGB recovery preserves the original concrete
preparation expiry, including for invoices without their own expiry; restoring
an intent never extends that deadline. Submission remains distinct from chain
confirmation.

The qualified storage contract is an intact private local store across native
and app-process restarts. Restored commands require their existing real outbox
directory; they must not recreate it and interpret the loss as nonexecution.
Recoverable sends reject VSS configurations because fingerprint-only VSS restore
does not preserve this outbox. Aster opens its existing owner-marked profile
directory rather than restoring an SDK archive over it. Native directories are
excluded from OS backup and secrets are device-only. General archive/cohort
restore, selectively deleted operation files and mixed old snapshots remain
unqualified; directory existence alone does not prove record continuity.
Terminal outbox records currently retain the request and unsigned/signed PSBTs;
new preparation validates all retained records. Long-history storage and latency
have not been qualified. Do not prune operation IDs or rejection certificates
without a crash-safe compaction and delayed-call nonrevival design.

The source-frozen App aggregate passes 1,497 tests with clean analysis and diff
whitespace checks. The current native host candidate passes 31 unit cases and
12 funded cases; SDK Dart checks pass 626 tests. These do not qualify a device,
Android, mainnet deployment or every storage-restore scenario. Four real iOS 27
native BTC cases using the current candidate also pass: typed insufficient
funds without Commit, a confirmed normal send, controlled loss of
the real Accepted reply resolved by one exact status read, and process restart
with unchanged operation/transaction identity and dispatch counts. This is
Simulator/regtest BTC evidence; funded BFA host cases and SDK deadline/queue
tests remain separate. Earlier candidate receipts do not qualify later
artifacts. The current staged wrapper manifest is
`769f2f81af3d2839fa35492d165d025be04557b60d6ee875824ebeb7d158e1fe`.

Device, Android, mainnet, distribution and immutable native-artifact
qualification remain separate release gates. Legacy unidentified attempts,
mixed or selectively lost storage, retained-record capacity and native EVM/BFA
lifecycle coupling remain open. Deleting Aster's EVM identity validation cannot
safely remove that native startup dependency. Android builds are explicitly
deferred by the author. Local host/simulator evidence is retained under ignored
`.buildlog/root01-recovery-20261024/` in both repositories; the public review
gallery receives only a redacted summary, never private journals, signed PSBTs,
wallet keys or fixture credentials.

## Ownership Boundary

`WalletRuntime` is the only app-owned native runtime. `RgbWalletEngine` is the
only adapter that holds a `UtexoWallet`; all SDK DTOs are converted to app-owned
models at that boundary, with private balance, activity and scalar-mapping
collaborators. The only stable SDK import outside that adapter family is the
redacted error mapper. UI and ViewModels depend on repositories and app models and never call
the SDK, native bridge, storage, HTTP, or platform plugins directly.

The runtime serializes all native access with provision, open, sync, suspend,
resume, switch, and destroy. Provisioning a new store maps to the SDK's
one-time `init` followed by `unlock`; opening any existing store maps to
`reinit`. Restore, wallet switching, switch rollback, foreground resume, and
fresh-engine recovery must never send a persisted store through `init`.

A wallet switch destroys the old native owner, opens the target, and restores
the previous wallet when target activation fails. Creation first persists a
`provisioning` profile, then commits it as `ready` only after native activation
succeeds. Bootstrap rolls back interrupted transactions before opening the
selected ready wallet. App pause, resume, and detach transitions enter through
the repository mutation queue so they cannot split native provisioning from
its metadata commit. Resume may reopen a suspended owner or recover a
known-safe retryable lifecycle failure against the durable active profile. It
cannot clear a reconciliation-required failure. `WalletRuntime` distinguishes
wallet-scoped payment repair from stronger native-owner quarantine. Audited safe
reads and switching can remain available for a payment fence; ordinary native
access remains blocked after a stronger owner failure until safe recovery or
disposal succeeds. Exact accepted/non-send evidence is preserved independently
of either fence. An unknown native outcome is not the only reason
reconciliation can be required.

### Debug hot restart

Hot reload is supported. A Flutter hot restart replaces the Dart isolate but
does not detach the iOS or Android plugin from the still-running Flutter
engine. The pinned SDK retains its engine-owned native RLN node, while the new
isolate has no public API with which to adopt or release that orphaned handle.
Creating another node for the same storage directory therefore fails closed.

Do not bypass the SDK with a private platform channel, guess native node IDs,
or delete wallet storage. Quit the current `flutter run` session and start a
new one when an isolate restart is required. A process restart releases the
plugin store and then exercises the same persisted-wallet `reinit` path used by
a normal app launch. Full hot-restart support requires a future immutable SDK
revision with a public, ownership-safe isolate-reattach contract.

## Runtime Configuration

The app reads non-secret service settings from compile-time defines. Debug and
Profile developers may pass individual values while investigating one local
environment. Every Release artifact instead requires the single reviewed JSON
manifest documented in `config/README.md` and consumes it through
`--dart-define-from-file`:

| Define | Purpose |
| --- | --- |
| `ASTER_NETWORK` | `regtest` (default), `signet`, or `mainnet` |
| `ASTER_INDEXER_URL` | Optional Electrum/Esplora override |
| `ASTER_RGB_PROXY_URL` | Optional RGB transport proxy override |
| `ASTER_LSP_URL` | Optional LSP base URL |
| `ASTER_VSS_URL` | Optional VSS base URL |
| `ASTER_ETH_RPC_URL` | Required credential-free HTTPS BFA validation RPC for release manifests and mainnet USDT; not an Ethereum wallet or payout verifier |
| `ASTER_ETH_CHAIN_ID` | Required deployment-approved decimal EVM chain identity for release manifests and mainnet USDT; checked through bounded `eth_chainId` before native initialization/unlock |
| `ASTER_EXPLORER_URL` | Optional public transaction explorer base |

Credentials and bearer tokens must never be supplied through either individual
defines or the manifest; those values are recoverable from the application
binary. Release validation rejects unknown keys, placeholders, and non-TLS
service endpoints before packaging. At composition,
`RgbWalletServiceConfigurationResolver` fills missing indexer and RGB transport
values from the immutable SDK's public network-default contract and fills the
same UTEXO protocol signet LSP default used by that pinned SDK. The resolved
object is then validated once and shared unchanged by the runtime and the
read-only Network Configuration screen. Settings therefore reports the complete
public endpoint, including a meaningful path, that the wallet will actually
contact. An explicit define always wins. Advancing the SDK pin requires
rerunning the exact default-resolution tests and reviewing this endpoint
inventory.

Each resolved endpoint is bounded to 2,048 visible-ASCII characters and must
use a canonical DNS, IPv4, or IPv6 host. Malformed DNS labels, encoded control
text, and resolver-dependent numeric aliases such as `127.1` fail before any
native wallet is created. Plain HTTP is accepted only for canonical loopback
development endpoints in Debug and Profile builds. Release validation rejects
HTTP, unencrypted Electrum (`tcp`), and unencrypted RGB transport (`rpc`) even
on loopback, so the SDK's local HTTP regtest indexer default deliberately makes
an unconfigured Release build fail closed. A Release regtest deployment must
supply explicit TLS-protected endpoints. Regtest validation recognizes
expanded and IPv4-mapped IPv6 loopback and rejects host ports `18443`, `50001`,
and `3000`, which belong to the protected external performance-lab stack
documented in `docs/DEVELOPMENT.md`.

The product-facing network is `mainnet`, `signet`, or `regtest`. The SDK's
`utexo` service profile is an implementation detail used for UTEXO protocol
signet services and is never treated as a fourth blockchain.

## Credential Ownership

Each wallet receives a random 128-bit opaque ID, an independent 128-bit storage
ownership token, and a random 256-bit native database password from
`Random.secure()`. The password and recovery mnemonic are stored together in
one schema-tagged encrypted record keyed by the opaque ID. They are never
stored in SharedPreferences or presentation state.

The non-secret ownership token is written to both the encrypted envelope and a
marker inside the native directory. Rollback deletes a resource only when its
token matches; collisions and resources with mismatched ownership are preserved
and reported. This prevents crash recovery from deleting data it cannot prove
the current provisioning transaction created.

Aster has not shipped, so storage has one current schema and no compatibility
reader for previous development formats. Older development installs must be
cleared and wallets restored from their recovery phrase.

- iOS uses a non-synchronizing, this-device-only Keychain accessibility class.
- Android pins RSA-OAEP key wrapping and AES-GCM data encryption in a dedicated
  Aster namespace. The pinned plugin's algorithm-change switch remains enabled
  only because version 10.3.1 uses it to initialize modern cipher markers in a
  fresh namespace; its backup compatibility path remains disabled. This does
  not read another namespace or app schema. `resetOnError` is false, app backup
  and device transfer are disabled, and optimized releases remove dependency
  Android log calls.
- Corruption is surfaced and retained for recovery analysis. It is never
  silently reset.
- Dart strings cannot be reliably zeroized. Callers therefore keep credential
  objects inside the narrowest asynchronous scope and never cache or log them.

The app does not yet define a PIN or biometric unlock product contract. Adding
user-presence protection is a future security decision, not an implicit plugin
default.

## Domain Boundary

Bitcoin and RGB are asset protocols; on-chain and Lightning are payment rails;
mainnet, signet, and regtest are chain environments. These are separate types.
RGB USDT identity is its immutable contract ID, never the `USDT` ticker.
Amounts use integer sats, millisats, or RGB smallest units. Fiat market data is
converted to the selected ISO currency's integer minor units at the repository
boundary. Bitcoin and Tether prices are independently validated so one partial
provider value cannot manufacture or erase the other. Market service and
attribution policy are app-owned and do not cross the SDK boundary.

The app reads the environment-specific USDT contract through
`ASTER_USDT_ASSET_ID` and its integer precision through
`ASTER_USDT_PRECISION`. Both must be present and valid or both USDT payment
routes fail closed as unavailable. Stable navigation carries only the product
target (`usdt-onchain` or `usdt-lightning`); the repository resolves that
untrusted identifier back to deployment-owned contract metadata before any SDK
operation.

The SDK's accepted PKG-006 artifact-provenance constraint remains visible in
the app release report. Until that constraint is resolved upstream, this app
cannot make a truthful funds-bearing mainnet production claim.
