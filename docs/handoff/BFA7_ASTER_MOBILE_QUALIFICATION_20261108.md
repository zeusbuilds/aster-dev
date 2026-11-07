# Aster BFA.7 mobile qualification — 2026-11-08

Actual Aster flows passed on iOS 27 and Android 17 against the existing isolated
BFA.7 fixture. The normal RGB_L1 activation gate and the independent Dev gate
remain closed. This record qualifies the stated local mechanisms; it does not
approve mainnet USDT, portable RGB restoration, aggregate privacy, store signing
or public release configuration.

The final SDK source is immutably pinned by Aster at
`349978fbeaac1f43ca563d103b271346c55fe0f1`. The independently hashed native
archives are published at
[native-bfa7-flutter.2](https://github.com/UTEXO-Protocol/flutter-sdk/releases/tag/native-bfa7-flutter.2).
Final App pin checks resolve the exact Git checkout without a local SDK or
native artifact override; the mobile source/runtime admission below identifies
the earlier execution of that same native generation.

The final immutable-Git source passed all **2,053 App host tests**, including
the late-confirmation Home rendering regression. Package configuration resolves
the clean `rgb-sdk-flutter-349978fbeaac1f43ca563d103b271346c55fe0f1`
Git checkout; all 21 SDK source files admitted by the final mobile observer
match that checkout. There is no local SDK override. The first Pub fetch could
not use the intended scoped credentials; an explicit authenticated exact-commit
fetch as `zeusbuilds`, followed by cached Git-source Pub resolution, established
the pin without changing global credentials or placing a token in a URL.
This is local verification, not a claim of a completed remote CI run.

## Exact identities

| Item | Admitted value |
| --- | --- |
| Native version | `0.3.0-beta.7-upstream-dev-bfa.7-bfa-flutter.2`, bridge 5 |
| Native integration tree | `8ac556ee67db70b93abb69b4ebd8fb0e6752dc0e` |
| Android AAR SHA-256 | `73301c7c7e7d3844aa30c0ff8ccc78b3ebd360327c652e7718b252877761fc42` |
| Swift archive SHA-256 | `60c33914222a62a822440bf155babd0b030a74f4fc166f7bd5c5955e6f49932c` |
| iOS `Runner.app` tree SHA-256 | `eff129c88465347ac09a0e1612ff20df6a7d938fe6304d74e317e3f1e1f5fa25` |
| Android Debug APK SHA-256 | `82f84f7d14fc243019e8e69bde572befbdc63670c3431f517d46c3f2c27650aa` |
| iOS public proof manifest SHA-256 | `35b8edff61803a5903be19ef6bc9f68df4a7ee8fd59b68c2dee9b997db4d1f2c` |
| Android public proof manifest SHA-256 | `cc75ef23e5921c3f0f536c19de0c0ad00f8f5436bbc43172320bc467c5d3adf7` |

The ignored evidence roots are `.buildlog/rgb-l1-full-flow/aster-l1-ios-20261107-k`
and `.buildlog/rgb-l1-full-flow/aster-l1-android-20261107-k`. Their
`FINAL_IOS_PROOF.json` and `FINAL_ANDROID_PROOF.json` enumerate public reports,
actual runtime events, source hashes and receipt hashes. All 28 admitted source
files were rehashed after execution. Actual runtime admission on each full and
cold run reported the exact native identity and all four capabilities:
registration, durable recovery, dispatched revocation and existing-only open.
Private wallet copies and secrets are excluded from these public manifests.

The fixture's asset is
`rgb:kOryemwN-I8Iutl8-otIPmDa-rn1cPTq-7VuhGvS-oe6oiMc`, ticker `QBFA`,
precision 6, backed by the existing test EVM chain 31337. Amounts 100 and 50
below are **base units**, not whole USDT. The public 444-byte contract SHA-256 is
`189674bd83baa0a74c06f86d4652d896e7725f33285b9e25c8006b2087044cb0`.

## Executed flows

Both platforms used separate QA application storage. They exercised actual
Create Wallet, recovery quiz, naming, native contract registration and Home;
three suspension/resume cycles; provider teardown and bootstrap on the same
wallet; a single 100,000-sat development funding; invalid-recipient rejection
and valid entry; amount cancellation; an accepted 1,000-sat BTC Send; witness
receipt of 100 QBFA; preparation review/cancellation without creation;
one deliberate change-output preparation; and one accepted 50-unit RGB Send.
Each send reached the dedicated success screen and Continue. Confirmed history
retained exact gross amounts and transaction references.

| Platform | Executed scope | Final exact send references |
| --- | --- | --- |
| iOS 27 | Retained `g` onboarding/lifecycle; `h` BTC/100-unit receipt; `k` same-wallet preparation/50-unit return, then same-artifact cold process | BTC `cf4d739e1c2076d6607f3dc753de00dd25fbb6e48b32d9da4d12aca56d9c15cf`; RGB `18d7c722bb6d78c07cfa7765db0d3a0c304a33e8ac93af896244ee53736b73e2` |
| Android 17 | Fresh final `k` performed the full flow, then same-artifact cold process | BTC `8b30f4b9d467cd9c5b0f4a0a6eb44313278eab0dcaf32aaadc8ca1b579e0f4d1`; RGB `3dd0ec7c58b28e85c53d586133c3858bfaea9ad108bfa4497ae5009a314f5c97` |

Android's new witness request explicitly required one confirmation. Before any
block was appended, its exact incoming transaction
`828c2be726fb6026bfca640a286d323584223d9c20bda3a89b91e4bbf18cd5ba`
appeared as waiting for confirmations with 100 future units, zero settled and
zero spendable. Exactly one appended block matured it. Preparation and the
return were independently confirmed with three blocks each. The retained iOS
incoming invoice was created before this app policy fix with the SDK's default
zero; it was independently confirmed with three blocks. It is not evidence of
the new one-confirmation policy. Captured SDK-call tests cover both amount and
amountless Aster requests; the SDK default remains unchanged.

The Android device used actual 16,384-byte pages with compatibility fallback
disabled. The complete arm64-only APK passed ZIP alignment and inspection of all
30 actual `PT_LOAD` segments across its ten ELF libraries. This is a Debug
artifact, not the signed release packaging gate. iOS used the existing iPhone
18 Pro Max simulator. Its original simulated Face ID enrollment state of zero
was restored after testing; device/app security policy was not weakened.

## Funded process restart

After native shutdown and a verified private local copy, each exact artifact
was relaunched with retained installation/storage. The public completion marker
selected the observation-only branch before any Aster UI or portfolio owner
mounted. It used existing-only native open and audited native/app pending state;
it ran no generic RGB refresh, maintenance, funding, preparation or payment
commands. Fresh process events were required, not old controller success.

| Observation | iOS | Android |
| --- | --- | --- |
| First → cold process ID | `98366 → 99023` | `6703 → 16993` |
| Persisted native cohort | `36a47ecb72604fbaa3ffee2ae36f79f2` | `14ca4b9c498c4f1cb0e9839988245e64` |
| QBFA settled / future / spendable | `50 / 50 / 50` | `50 / 50 / 50` |
| BTC settled / future / spendable sats | `98305 / 98305 / 18561` | `98305 / 98305 / 18561` |
| Native pending / app payment fence | `0 / false` | `0 / false` |
| Full driver / new cold driver | exit `0 / 0` | exit `0 / 0` |

The balance distinction is native output availability, not a missing payment:
colored outputs remain reserved. Independent chain accounting is
100,000 initial sats + 1,000 incoming witness sats − 1,000 BTC sent − 1,000
outgoing witness sats − 695 total fees = 98,305 total sats. Neither a local
snapshot nor a matching seed establishes portable RGB recovery authority.

## Home presentation observation

The immediate `k/home-final-50.png` captures on both platforms were taken before
Home's retained provider repainted; they still show the earlier 100-unit value
(the iOS image also caught a navigation transition). They are preserved as QA
timing evidence and must not be described as final 50-unit Home screenshots.
The native confirmation loop can return on its first successful observation
before another UI frame or Home's normal polling interval runs.

A separate Android `l` observer required the exact completed `k` checkpoint,
identity/cohort, confirmed history and no pending payment before mounting the
real Aster app. Normal Home refresh was explicitly permitted; no refresh was
called manually, no provider was invalidated, and no funding, preparation or
payment command ran. The actual Home provider and painted asset rows were
asserted and visually checked: `0.00098305 BTC` and `0.00005 USDT`, with no
refresh failure or in-progress refresh. Its driver exited zero and shutdown/
private local copy completed. A regression also verifies accepted success and
Continue before confirmation, followed by later native confirmation and the
ordinary 31-second Home poll updating both rendered asset rows.

The public manifest is
`.buildlog/rgb-l1-full-flow/aster-l1-android-20261107-l/FINAL_HOME_PRESENTATION_PROOF.json`,
SHA-256 `f4166a60b6a5d140241c0939f5f90746e1b223357db5b3f5b7d861ce79946dbe`.
It binds the screenshot `home-current-50.png` and observer APK SHA-256
`a729e11d97c21391986cf9a480ef8ae8f1d264b0062baae6942c41c461e6bef1`.
This ordinary-refresh UI observation is separate from the strict no-refresh
cold-process proofs. No production Home defect was established.

## Findings corrected and preserved attempts

- Actual initial Aster provisioning found the app ownership token collided with
  the SDK's exclusive native root. A stable `rgb-l1` child now separates them.
  READY activation requires existing native storage and `openExisting`; missing,
  empty, ambiguous or legacy layouts fail closed before keys or initialization.
- A partial historical witness refresh could have looked current. Aster now
  inspects every detailed refresh result once, retains the last complete Home
  portfolio on failure and keeps background recovery quiet.
- Aster previously inherited the SDK's intentional zero-confirmation receive
  default. It now explicitly requests one; actual Android pending/mature behavior
  and amount/amountless regression tests verify the app policy.
- Integration-only text-input caching after unfocus dropped subsequent synthetic
  input. The driver now requests real field focus and checks controller/provider
  acknowledgement; product validation was not relaxed. Stale optional-copy
  assertions and a QA lifecycle observer omission were corrected separately.
- An earlier Android launcher used `--no-keep-app-running`, which uninstalled
  only its QA package after a pre-send BTC-only attempt. That private backup and
  failure are retained; its deleted Keystore is not assumed recoverable. Final
  flows use `--keep-app-running`, awaited shutdown/backup and process stop only.
- Final Android host funding first received a definitive **pre-dispatch**
  `insufficient_asset_balance` rejection: no transaction/batch and
  `endAuthorized=false`; no Commit occurred. The host's previous confirmed iOS
  change was still cached. After one existing-state refresh proved 246 settled
  and spendable units and no pending operation, explicit parent authorization
  admitted one **new** operation to the same unused invoice. It accepted once;
  the old rejected operation was never replayed. Host preflight now checks a
  fresh successful observation and sufficient spendable balance before Prepare.

All old attempts, invoices, operation identities and receipts remain preserved.
No container or chain was created/reset, no contract was deployed, no extra
asset was minted and no user/Iris wallet was changed by these Aster campaigns.
Unknown outcomes never authorize automatic monetary replay.

## Remaining release boundaries

There is no approved service that establishes freshness of a restored RGB
snapshot. Portable RGB restore and unrestricted restored-wallet spending remain
blocked. Public Dev/mainnet contract, service and EVM policies require separate
approval and real-network qualification. Configured BFA EVM outages still block
opening that wallet, including its BTC access; omitting the EVM silently is not
a safe workaround. Final signed app identity/delivery and aggregate privacy
admission remain separate from these Debug regtest proofs. Neither product nor
Dev gates were enabled.
