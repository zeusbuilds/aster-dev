# Shared-stack wallet qualification — October 15, 2026

This campaign tests Aster and the Flutter SDK against already running local
infrastructure. Iris and WDK are read-only references. No stack, container,
chain, contract or existing wallet was created, replaced, reset or cleared.
New disposable wallet fixtures use separate storage and retained private copies.
This is local regtest qualification, not a funds-bearing mainnet release.

## Reproducible scope

Read `REGTEST.md` and the shared consumer contract before running. The main
stack is `utexo_local`, with Esplora 18094, Electrum 18001, proxy 28090, local
EVM 18555 / chain 42161, gateway 18088 and explorer 18095. Destructive tests
belong only to the existing qualification stack; none were run on the main
chain. The separate chain 31337 was not substituted into a main-chain bridge
operation.

The canonical BFA fixture is `Usdt` / `USDT`, precision 6, asset
`rgb:rNgQi9ID-fLRJkdf-8RO8ZZU-8d_fHpZ-3Dcuz36-SKnBEbg`.
Its exported contract SHA-256 is
`962c503ebac90a92760c397e019cf9d37204f5f08ef2bf4ddc537be967ba9d10`.
Consumer configuration SHA-256 is
`5a192f2764253f7facac702453f761f6fa608aaaecdd1cdfcf453a75ba6b5d8a`.
These identify this preserved fixture, not a public-network deployment.

Devices are the Aster-owned iOS 27 simulator and Android 17 / API 37 emulator.
Android uses 16,384-byte pages, linker compatibility mode `fatal`, and disabled
package page-size compatibility. Normal SDK wrappers and native cryptography
are used; storage namespaces isolate QA profiles from the normal app registry.
No mnemonic or wallet password appears in evidence or screenshots.

## Corrected behavior

- Android API 37 local endpoints require runtime local-network consent. Aster
  checks it before native initialization and persisted-wallet open. An actual
  OS denial produces an actionable typed failure without starting native
  provisioning. Actual Allow consent permits native unlock and same-store
  reopen. Public profiles skip local consent. See the official
  [Android permission contract](https://developer.android.com/privacy-and-security/local-network-permission).
- SDK cleanup failure retains ownership and quarantines ordinary operations
  until cleanup succeeds; a failed shutdown cannot admit another live owner.
- A typed SDK public-contract import validates the expected identity and
  canonical BFA metadata. Both platforms imported the actual exported contract,
  observed zero balance and verified idempotent reimport.
- SDK unspent decoding now carries the native pending blinded-allocation count on both platforms. Missing or malformed native values fail decoding instead of silently reporting zero.
- Aster sync awaits both Bitcoin chain sync and RGB consignment/ACK refresh.
- Receive retains its asynchronous dependencies and rejects stale generations before native dispatch. This fixes an observed `UnmountedRefException` in the production settings provider; real-dependency disposal and rebuild regressions cover the boundary.
- Receive commands reject prior data retained during loading or error states.
  Each generation tracks the active wallet and switching context; late results
  from a previous wallet cannot become a visible or copyable request. Genuine
  settled current-request fallback and explicit setup error actions remain
  available. The focused Receive/Send/lifetime pack passes 79 tests.
- Aster uses an explicitly labelled 1 sat/vbyte local test policy only on
  regtest, where the indexer's fee-estimate response is empty. Other networks
  retain native estimation and do not fall back to the test rate.
- Bitcoin accounting follows the pinned native UTXO semantics: confirmed is a
  subset of total, and native spendability may include pending change. Bitcoin
  unavailable value is total future UTXOs minus vanilla spendability, preserving
  all colored, immature and reserved value without clamping. RGB retains its
  distinct confirmed-allocation accounting. The native source is
  [rgb-lib at the pinned revision](https://github.com/UTEXO-Protocol/rgb-lib/blob/1b951af0c8233308c919975552487be19ad2a930/src/wallet/offline.rs#L1596).
- On-chain Send forwards the displayed fee-rate review. A single runtime lease
  checks freshness, re-estimates the same target, rejects rate/source changes,
  then dispatches the reviewed policy. Rejection requires explicit Refresh fee
  and another Send tap; no new rate is substituted silently.
- Activity reads sample history and balance before the independently advancing
  node tip. If a confirmation is ahead of that tip, at most three read-only
  rechecks run under the same native lease. Persistent inconsistency yields a
  typed retryable refresh failure; no height is fabricated and no transaction
  is replayed.
- Witness receive remains the default. A witness Send review discloses the
  additional 1,000-sat Bitcoin output sent to the recipient, separately from
  network fees. Authoritative native recipient type is carried through preview,
  reviewed command and final validation; unknown types fail before broadcast.
- Blind receive is an explicit choice. Preparing wallet-owned allocation outputs
  has a separate review and one confirmation, a durable committing marker,
  exact new-transaction reconciliation, and no automatic replay. Cancel spends
  nothing. Review says “up to four”; the native API acknowledges completion but
  does not return the observed output count. Corrupt financial journal slots
  fail closed instead of falling back to an older unsubmitted review.

The app pins SDK `0.2.0-beta.2` at immutable Git commit
`992b86ee528d0811bd17cedca901de08561c1982`, without a local path override.
The native RLN artifact is unchanged from the published beta 1 rebuild. On that
clean SDK commit, the iOS 27 native gate passed 27 XCTest cases with zero
failures or skips, identical source hashes before/after, and 31.205 seconds
wall time. Its report is under `build/full-wallet-20261015/native-ios-992b86e/`.
The SDK host/native matrix also passes 507 Dart tests and 31 JVM tests; the
existing VSS qualification blocker remains separate.

## SDK device evidence

Evidence is retained under the SDK checkout's ignored
`build/full-wallet-20261015/<run-id>/`. Reports bind source, consumer manifest,
public contract and output logs by hash. Failed reports remain failed.

| Run | Result and boundary |
| --- | --- |
| `sdk-lifecycle-ios27-20261015-c` | Pass: three shutdown/reinit cycles, destroy and fresh-object same-store reopen; identity unchanged. |
| `sdk-full-ios27-20261015-a` | Canonical import, two fresh 2m-sat wallets, 20k-sat BTC transfer, 2m-unit BFA mint and 500k blind transfer passed. Test stopped before witness send because its request omitted required witness Bitcoin data. Both closed native stores were preserved. Overall report remains failed. |
| `sdk-resume-ios27-20261015-b` | Pass from the verified closed checkpoint, without another fund or mint: 100k witness return, 20k burn, exact local EVM payout, funded identity/balance persistence, and private closed backup. |
| `sdk-full-android17-20261015-c` | Actual API 37 Allow consent, lifecycle, canonical import, BTC transfer, BFA mint, blind and witness transfer and native 20k burn passed. Host payout ACK failed because a bridge signer lagged the relay. Overall report remains failed. |
| Android same-proof recovery | Exact proof, chain receipts and bridge claims established that the failed attempt had not broadcast. After all three signer tips caught up, one submission of the same proof paid exactly 20k units. No new burn or mint occurred. Original failure records remain intact. |
| `sdk-verify-android17-20261015-d` | Native read-only restored identity and funded balances passed; framework semantics-lifetime teardown failed. Overall report remains failed. |
| `sdk-verify-android17-20261015-e` | Pass: hash-verified closed Android C fixture restored into a fresh owned fixture, original identity and exact BFA balances 1.58m / 0.4m retained across both-wallet shutdown/reinit. No financial requests. |

This is composite evidence with preserved failures and explicit recovery, not
one uninterrupted all-green financial run. The following public chain facts
allow an independent comparison with the retained receipts:

| Operation | Transaction |
| --- | --- |
| iOS BTC transfer | `cdcb5df9360b9b90facc6ea79d7ca0bf8785cf2d4d2976ad9990042354981637` |
| iOS blind transfer | `c347f2facc2bf0c6e217a06bd9fecd5ad3b089383e403df6da8cddc0ec139eab` |
| iOS native burn | `1df1be9e0160792128edbf9ff0af4a60a9451f30696453f9022729f5c8370b1f` |
| iOS EVM payout | `0x6e3fb4b72793f48f5a213b2c9d8c9acaa706560b692e4466e184c78fd20649ed` |
| Android BTC transfer | `5f75859cfc64016ceeec86fb3a6e4965bb0778a16be18aae2a814f3c83425e2b` |
| Android blind transfer | `ec1caa5bf5eb4ec92cba66518c5e1b702c398f86bce6896c71ebfdf2ec5b5c34` |
| Android witness return | `d5e480233d9790b644347ffa953eebc90abefcbaf650880b0871052cd384f160` |
| Android native burn | `8999144da8f1509e5d1b7553e5a4f6eba4746269cd3cb2487381e899519e1cee` |
| Android recovered EVM payout | `0xe7b567a9ea198b43d2c5843670dad22a8257c53fcfab9cc2ac81fb90c8ea6f21` |

Android recovery summary is retained in Aster's ignored
`.buildlog/full-wallet-20261015/infra/audit-android-burn-20261015/recovery-summary.json`,
SHA-256 `6831267230f5e65447c022c75665ad9c53f4d9576e05141545b4cd3ff79a70ae`.
The host helper now performs a bounded read-only signer-tip readiness check
before its one payout submission; 38 Go and seven controller tests pass.
The helper does not retry a financial mutation automatically.

## Aster device evidence

Reports and private closed fixtures are under ignored
`.buildlog/full-wallet-20261015/<run-id>/` in the app checkout. The runner
requires native disposal, durable private copy acknowledgement, unchanged
source during the run and a successful test exit for a passing result.
Wallets and secure credentials stay isolated by storage run ID. Restore uses
another control run ID, avoiding command-ID collisions and financial replay.

The Android denial test proved the OS refusal boundary. First funded Aster
runs exposed missing regtest fee data and stopped before BTC send broadcast;
their funded stores were preserved. iOS run `aster-full-ios27-20261015-b`
passed actual recipient rejection, excessive amount gating, review/Back cancel,
single UI Send of 20,000 sats, exact host-confirmed output and settled history.
Its transaction is
`bcc00e3fdaf1eab8ba69bbde21a6bf096d719571d8b803923a107ed4af2a5b2e`,
with 143 sats network fee. It then hit a harness assumption that all fresh RGB
requests were blind; the actual app correctly generated its default witness
request. That report remains failed and its closed store is retained.

iOS run `aster-full-ios27-20261015-c` completed the same BTC UI checks,
then exposed the Receive dependency-lifetime error after explicit blind choice;
no RGB preparation or mint occurred. Android run
`aster-full-android17-20261015-b` funded its fresh wallet, then stopped because
the harness entered a loading placeholder before Send became ready. The harness
now waits for the actual editable state. Both failed reports and verified
closed private snapshots are retained. Neither failure is relabelled a pass.

Runs `aster-full-ios27-20261015-d` and
`aster-full-android17-20261015-c` both passed BTC UI Send, blind-choice consent,
preparation cancellation and one preparation submission, then exposed an Aster
balance invariant that rejected native Bitcoin pending change. Both reports
are failed with unchanged source and verified closed backups. Neither issued a
BFA mint. Bitcoin transactions are
`12fc8abb85e78e52f76dd8b7341bdc657c75480801f20263ee372f0feb798945`
(iOS) and `3e22526ff037ceb0b4a7341db52a3ee266bbe63b15ad384856218ae69f38b23c`
(Android). Aster's correction follows the pinned native Bitcoin semantics:
confirmed balance is a subset of projected balance, and spendability can include
pending change. RGB allocation semantics remain separate.

Runs `aster-full-ios27-20261015-e` and
`aster-full-android17-20261015-d` passed the corrected pending Bitcoin state,
confirmed allocation preparation and each emitted one 5m-unit BFA mint request.
The host acknowledgements record accepted bridge operations, with
`receiverBalanceVerified=false`. The harness then incorrectly rejected two
public numeric token-accounting keys as credentials, before recipient refresh.
The reports remain failed with unchanged source and verified closed backups.
A narrow public-field schema correction admits only the exact two canonical
uint256 decimal amount paths; 24 positive/security regressions pass. Read-only
runs `aster-reconcile-ios27-20261015-a` and
`aster-reconcile-android17-20261015-a` subsequently passed against the original
closed fixtures: original node identity, 1,979,573 projected BTC sats,
1,899,573 spendable BTC sats, and exactly 5,000,000 settled/spendable BFA units.
No fund, mint, burn, send or allocation-preparation request was repeated.

Run `aster-full-ios27-20261015-f` passed the BTC UI flow, allocation preparation
and actual settled/spendable receipt of 5,000,000 BFA units. It then timed out
at import Continue after successful phrase validation: the keyboard covered
the button. The harness now dismisses it before one hit-tested tap. Run
`aster-full-android17-20261015-e` passed one BTC Send and host confirmation,
then exposed a read race: confirmed transaction history could advance ahead of
the independently sampled LDK block height. No Android RGB preparation or mint
occurred in that run. Both reports remain failed, with unchanged source,
successful native disposal and verified private backups.

Run `aster-full-android17-20261015-f` passed the corrected BTC history and RGB
preparation, then forwarded a retained Witness request while its explicitly
selected Blind request was loading. The bridge rejected it before deposit or
mint acceptance; only token approval completed. Read-only chain/database
evidence found no accepted deposit, prepared mint or payout. The failed ACK
remains unchanged. The harness now requires completed current Blind state and
authoritative native invoice decoding before any bridge request.

Run `aster-full-ios27-20261015-g` passed actual 5m BFA receipt and second-wallet
import. Its harness opened wallet selection with `go` instead of the normal
push-owned back stack, so the selector's pop failed. The host driver exited
while the asynchronous test continued and submitted one reviewed 1m transfer.
The native test later timed out because it refreshed only the receiver; the
single-active-wallet runtime also needs the sender to consume ACK and broadcast.
The original failed report remains unchanged. After native disposal, a separate
host coordinator verified a closed backup and durable acknowledgement. The
runner now serves that cleanup handoff for a bounded six minutes after driver
exit, and framework-error guards stop the test before further financial work.

The narrowly admitted `aster-reconcile-transfer-ios27-20261015-a` stopped at an
overly restrictive pending-status check and preserved a newer closed snapshot.
Run `aster-reconcile-transfer-ios27-20261015-b` passed using that latest pinned
snapshot and the original G intent. It required the same two identities, exact
transaction/amount, unchanged production/SDK/configuration, and original/current
evidence hashes. Receiver/sender refresh completed the already signed
`0517693e33f373e2a2ae96924e03d6fa0ef129260c015455be81851bc9eadd37`,
confirmed at block 7312, without a new Send, fund, mint, burn or output-preparation
request. Both unique histories settled, with exactly 4m / 1m spendable BFA.
This progress can broadcast the original transaction; it is not a claim of
chain-read-only execution. Native disposal and the final closed backup passed,
manifest SHA-256 `089df336357198728ffc0286c88f5f62ca8fa1f39a15a236660876091215f363`.
All earlier reports and private snapshots remain retained.

Run `aster-full-ios27-20261015-h` passed the BTC review/cancel/single-Send flow,
one 5m-unit mint, second-wallet import, and actual receipt of the reviewed
1m-unit blind transfer. Its transactions are
`05479a5faa1cb602dfd44b3aedff932c81154cf19cb37380fa11287bc2a97491`
(20,000-sat BTC Send) and
`4050804c347a695d446e32ec2fef6e351fbc4bb1f77500a48876bb0ace3dd565`
(1m-unit blind Send). The harness advanced after the wallet ViewModel committed,
before the selector's delayed route pop completed. That produced an asynchronous
`GoError`, followed by `qa_import_tap_blocked`; the report remains failed.
Native disposal and the host backup acknowledgement passed. The closed-file
manifest SHA-256 is
`a50eea6b83193e57ee1d526bfcd1a05935a6b71eca3017ab6349c853b5047cc3`.

Run `aster-full-android17-20261015-g` passed its 20,000-sat BTC UI Send and
confirmation, transaction
`e2228dcc87e6c06f1491b4e25736b0f660673d7728e91ddb91ab88a3fc1b035c`,
and completed one allocation preparation. Its helper did not wait for the
delayed, enabled Check preparation action and stopped with
`qa_setup_ui_timeout`. It issued no BFA mint request. The report remains failed;
native disposal and the host backup acknowledgement passed. The retained
365,568-byte Android archive SHA-256 is
`f45ac15e9b5228df9909437ddb24bae604239e0d8717959a6077d6c0bb0ac7bc`.
Both H/G reports bind unchanged app source, SDK and configuration. Their failed
reports, verified private backups and completed financial receipts are retained.

The first narrow harness correction awaited the selector's push Future and
disappearance. It also retained a binding-owned framework-error latch even if
the framework exception slot was consumed. Normal Flutter error reporting and driver
failure remain active; no global error-handler waiver is installed. The import
harness and public-field guard pass 33 focused tests, including a delayed pop,
an uncaught child-zone error and a consumed exception slot. The preparation
helper waits for the enabled Check preparation action and invokes it once,
without replaying Confirm. Three new preparation-harness regressions cover a
delayed control, a visible loading/disabled control that later enables, and an
already settled Blind request. They assert no setup confirmation or Witness
selection during those readiness checks. These are test-driver corrections;
no production wallet or native financial behavior changed.

Runs `aster-full-ios27-20261015-i` and
`aster-full-android17-20261015-h` each passed the 20,000-sat BTC UI Send,
actual receipt of 5m BFA units, second-wallet UI import, funding and allocation
preparation. Neither issued a new Blind or Witness Send. Both then stopped
with `qa_import_ui_timeout`: the new harness condition awaited an obsolete
GoRouter push Future even though the target wallet had committed and the
selector was removed. Both reports remain failed, with unchanged app source,
SDK and configuration, successful native disposal and verified backup
acknowledgements. The iOS closed-file manifest SHA-256 is
`17377edc56e994d40f7c8cd88b72b85461657fa820343e9bb328b791afaa754f`.
The 695,808-byte Android closed archive SHA-256 is
`3256dd79c032ccf94183bfd0d1e55bc30a60ac44bf55b817df7229c4f5bcb1ad`.

A host reproduction with the real app router, route configuration, wallet
ViewModel and selector confirmed that GoRouter 17.5 route decoding creates a
new Completer during refresh, leaving the original push Future unresolved.
The revised test helper captures the exact selector `ModalRoute` and requires
that route to be inactive, the selector absent and the target wallet committed
before advancing. It observes Future errors without treating completion of
that obsolete Future as proof of navigation. The regression paints two locked
native-work frames before completion. The production selector pop guard is
unchanged; this remains a test-harness correction requiring fresh device runs.
The final focused pack passes 37 tests: ten import-harness, 24 public-control
and three preparation-harness regressions, with clean fatal analysis and format.

The production Receive candidate's complete host suite passes 1,122 tests with
zero skips and 15,390 / 17,493 covered lines (87.98%). Its LCOV SHA-256 is
`34b01e841260b788993e5af6de3f5f53c04991916b7f4df9de58d1f4200cb4e9`.
The separately executed runner gate passes 93 Python tests. Those counts precede
the narrow H/G test-driver corrections; they do not claim a passing funded
device run or include subsequently added harness tests.

## Final Aster qualification

Run `aster-full-ios27-20261015-j` passes the complete configured onchain flow
in 316.01 seconds. The result SHA-256 is
`6e45f394f950c0687f5d8006354c3186aa93557b97bfe68135aa01ce22749182`;
the verified closed-file manifest SHA-256 is
`f834105967e349bed6d426f1cfff0c3bc4579b100951cf46028402562918907f`.
This includes the actual BTC and BFA UI flows, both Blind and Witness sends,
wallet import/switch and funded lifecycle checks. The completed native fixture
was closed and copied before the host stopped its process; PID 6882 was then
confirmed absent.

Run `aster-restore-ios27-20261015-j` passes in 45.832 seconds after that process
termination. It opens the original storage/secure identity in a fresh process,
verifies both original wallet IDs, every BTC/BFA balance dimension and active
selection, and closes again. Source, SDK, configuration and the original closed
backup remain unchanged. Its new closed-file manifest SHA-256 is
`45318b9d5670b64806ce500bad0be85441681ff59e92710227cc3fcfc6327ac3`.
This cold restore issues no new financial request.

The ordinary iOS `lib/main.dart` build was installed without uninstalling the
app and launched as PID 11305, with public Welcome-screen evidence. That normal
entry-point launch is separate from the isolated funded fixture's restore.

Run `aster-full-android17-20261015-i` remains failed before test entry: exit 1,
zero events, no SDK entry and no ordinary fixture backup. Its immutable failed
result SHA-256 is
`4258ff0919212697a1e128cf20960d2a0980a1174eeb77cdb17d1ae64edb2f55`.
No native-disposal claim is made for this pre-entry failure. A separate
`pre-test-preservation.json`, SHA-256
`470335619f27a17c3981a5b943b7ba3e50a923b611fcc6e876c4deeceb390843`,
records that the host stopped the process before creation of the QA root,
with zero events and that root absent before, after and at quiescence. The
148,838,912-byte app credential-encrypted/device-encrypted snapshot SHA-256 is
`fdd5dcf152ebbc450b2981f19427e437fa091a51ab10d45b6adb1a65f795a741`;
all 29 files retained from Android H match exactly. App source, SDK and
configuration remain unchanged. This supplement preserves existing data and
supports only narrow pre-entry admission, not a passing test or SDK teardown.

Run `aster-full-android17-20261015-j` also failed before app/test entry. Three
installation attempts returned `cmd: Can't find service: package`. Both package
and activity services were absent despite `boot_completed=1` and a live
system-server process. There was no app PID, test event, SDK entry or QA root.
The failed report remains immutable, elapsed 388.365 seconds, SHA-256
`573faf2b5049ffe180452add98f17dcb946e7523bb3186fb52e847902fe2e58c`.
App source, SDK and configuration remain unchanged; the ordinary fixture backup
is unavailable and no native-disposal claim is made.

J's separate pre-entry preservation certificate SHA-256 is
`d17fa38c5e2b193770b87dc68c36affdbf98844d4ee307d05687f2c9e94a6ed3`.
Its fresh 148,838,912-byte full app credential-encrypted/device-encrypted
archive is byte-for-byte identical to I's
`fdd5dcf152ebbc450b2981f19427e437fa091a51ab10d45b6adb1a65f795a741`,
with all 29 prior H files matching. At `2026-10-15T17:00:13.089Z`, one
data-preserving `adb reboot` was issued to the existing owned emulator. No AVD
creation, wipe or stack operation occurred. Post-boot service readiness,
API 37, 16 KiB/fatal compatibility policy, UID/data and retained H files must
be verified before the next launch; only controller port 29671 is reversed.
The runner's narrow I/J admission and pre-launch framework readiness gate
preserve these failures instead of treating `boot_completed` as app readiness.
The updated Python runner gate passes 119 tests; both real I/J admissions pass
their local evidence/hash checks without making a native-closure claim. This
runner-only gate is separate from the earlier 93-test evidence and the
unchanged production runtime host suite.
Standard drive uses `--no-start-paused` and `--keep-app-running`; production
wallet Dart code is unchanged.

The guest reboot did not restore framework readiness. The same existing AVD
was then recovered by restarting its process without creating an AVD or wiping
userdata. Post-recovery checks passed for package/activity/display,
SurfaceFlinger and Keystore services, API 37, 16,384-byte pages, fatal linker
compatibility and disabled package page-size compatibility. App UID 10230 was
retained. The full 148,838,912-byte credential-encrypted/device-encrypted
archive remained byte-identical to
`fdd5dcf152ebbc450b2981f19427e437fa091a51ab10d45b6adb1a65f795a741`;
all 180 regular files and the 29 retained H files matched. Only controller
port 29671 was reversed. This recovery did not operate shared infrastructure.

Run `aster-full-android17-20261015-k` passes in 573.962 seconds. Its result
SHA-256 is
`b19b563c365d1256192b6757356dfeb52a42dd37da68ae8393c9a1cede409ac0`.
The verified native-closed 830,464-byte archive SHA-256 is
`0ba9305a1aa20e05ebc1bc014239657a1817d470e80962e5c6650c6baa7eac01`,
with host backup acknowledgement. After completion, PID 4641 was stopped and
confirmed absent before cold restore.

Run `aster-restore-android17-20261015-k` passes in 61.253 seconds, result
SHA-256 `37a6c1da57f72f917d4c183097d9736b16325fda5105c2c88509cd833defdeb1`.
It retains both wallet IDs/public keys, all six BTC/BFA balance dimensions and
active selection. Source, SDK, configuration and original restore evidence
remain unchanged. Native disposal and acknowledgement passed; the new
847,360-byte closed archive SHA-256 is
`079098f33b2aed83f9b3b193dd98b29b06fbcbf2ca95af4da67f39d4c361f6a2`.
No financial request was repeated by either platform's cold restore.

Both final full runs pass real BTC Send recipient/amount rejection, review
cancel and one Send, explicit Blind preparation Cancel/Confirm, 5m-unit BFA
receipt, second-wallet UI import/fund/preparation, 1m-unit Blind Send, and a
100k-unit Witness return with its reviewed 1,000-sat recipient output. Unique
native histories and conservation checks retain 5m units: 4m / 1m after Blind,
then 4.1m / 0.9m after Witness. Funded lifecycle checks pass on both platforms.

| Final operation | iOS J transaction | Android K transaction |
| --- | --- | --- |
| BTC Send, 20,000 sats | `81e569cc659471e1e418bd8720356bff8442a9231773ddc44e714350d2e6a96a` | `1736fd1d54be5850a55f5fb23b92eab3e6390f7d1e0452817090de5ca1a4e90d` |
| Blind Send, 1m BFA units | `9429a4c01d2ee883614c9a923396fa446c290e3d4cb4653bd674c8dbc7858d30` | `b5f83cf03885200dd0f20802ed41dfeee13eaf9418811ed06f0bd11a475ca501` |
| Witness return, 100k BFA units | `dc248be3c398328ceda555af1c99e937017399b3c08aa75246d1b7425789c7ae` | `2d021710fd7625f25f5e96c86eaf2fafddb3dc7f8fec9c9e122bc64b5bfa7681` |

The normal universal Android APK is built and retained, 423,595,470 bytes,
SHA-256 `8916d8585a51f3256fd022a4971453708a5fec935576e72156a96f1f681b7c9d`.
All 25 native libraries across its three ABIs pass ELF and ZIP 16 KiB checks.
The matching APK installed with `-r`, without erasing app data, and its normal
main entry launched to Welcome with Create Wallet / Import Wallet. PID 21222
remained foreground, UID 10230 was retained, and API 37 / 16,384-byte pages /
fatal linker compatibility / disabled package compatibility were verified.
Launch receipt SHA-256 is
`110d35b2807b2b56f8942a475f2ab0611d2c4c7eb515681f1d3a1b3165d30ec2`;
the final post-inspection receipt SHA-256 is
`d6b76db3ca5f39013012b90770bc1b00f732f5fa704b0ec0e3cbc2c4203ed99a`.
The actual public-screen proof is the freshly captured and visually inspected
`normal-main-android17-welcome-adb.png`. The stale-frame tool screenshot and
preliminary wrong-activity launch assertion remain diagnostics only. This is
installed normal Debug-runtime evidence; release AAB/split qualification is
separate.

Both platforms pass configured onchain full-flow, cold-process restore and
normal-entry launch checks. This does not promote earlier failed reports into
passes or qualify physical devices and signed releases.

## Final preserved-infrastructure audit

After both final full runs and cold restores had closed and acknowledged their
backups, the final audit passed under
`.buildlog/full-wallet-20261015/infra/final-post-wallet-20261015-k/`.
Summary SHA-256 is
`5bfd582794dc7507f458e672cd7b8a7a3e76575628361fb8f351c3ee10aa01a6`.
All 47 container IDs/images/projects/ports and nine contract bytecode hashes
match the retained baseline; all 39 shared services are healthy. Canonical
asset/configuration, shared source checkouts and helper bindings remain exact.
All 107 request/result IDs match, including 59 financial/confirmation jobs.
The full 101-file acknowledgement set and original bytes remained unchanged
during the audit, as did financial and public/late-event journals.

All 22 unique accepted app Send transactions are confirmed in actual full
Esplora `/tx/<txid>` bodies, including accepted sends from failed runs and the
original G late journal. Alias events are deduplicated by transaction ID; a
status-only response cannot satisfy this check. The audit separately preserves
the exact failed SDK Android burn ACK with one same-proof payout recovery and
the exact Android F approval-only rejection. No financial request or container,
chain, contract or wallet reset was performed; the only shared write was
`stack health` evidence.
After rechecking unchanged financial/ACK/event evidence, the owned host worker
and relay were stopped and only this emulator's controller-port reverse was
removed; private `infra/controller-cleanup-{intent,result}.json` receipts retain
the cleanup proof, with containers and app data preserved.

The reviewed ignored audit helper passes 37 offline regressions, separately
from the 119-test runner gate and the production host suite. It rejects
duplicate-key/nonfinite/malformed or changed ACK payloads, retains both original
ACK/result byte hashes while allowing JSON encoding differences, rechecks the
exact ACK set/bytes at completion, and pins the reviewed recovery summary
before reading its claims. Independent review found no remaining blocker in
that audit helper. Host checks retain their own scope and never substitute for
the native funded results above.

## Remaining limits

The main profile has no LSP, VSS or Lightning channel infrastructure, and the
app intentionally leaves those payment routes unavailable. No live Lightning,
APay, WalletConnect pairing, VSS recovery, physical camera/accessibility,
physical performance/leaks, production signing or mainnet readiness is claimed.

References were checked at their actual revisions. A final scoped GitHub read
found WDK PR45 open at head
`6758e4d629c27ca6fdb234da30856be86acc1980`, three commits after the earlier
reviewed `9daec8607fba0456e4e268029c97c1f5ea7da6b4`. That delta retains
failed disposal owners for retry and updates dependency/source admission; it
does not change RLN's native financial graph. Flutter's retained-node cleanup
quarantine covers the analogous ownership boundary. Node PR24 is merged at
`04b641dce121ac690d5d0866eeba4fa76aebe7a5`, with unchanged PR head
`94a0881f4b1e83e037b6256b0380baca7e2ee6cc`, and merged Bare PR22 merge
`6bfd8726a644d79fc914929db3de19eec3c57a21`. Iris PR9 was inaccessible as
`zeusbuilds`; its local checkout at `9333c284ab5f65139f16a16da010cad4192ce1ee`
was used as a reference without claiming its remote PR head was verified.

The WDK native lifecycle overlay is not in Flutter's published RLN artifact.
The original P01 external-signer/mobile-overlay qualification, P02 orphan BTC
reservation, P03 reorg rollback, P04 general witness pending accounting, and
P06 BFA event-selection concerns remain open. The observed single-count
unconfirmed witness balances in these SDK runs do not close those broader
issues. Native signatures, reproducible-build/source attestations and physical
release qualification remain separate release constraints.
