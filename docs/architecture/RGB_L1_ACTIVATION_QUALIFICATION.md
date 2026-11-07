# RGB_L1 activation qualification

The product backend gate remains closed. Dev Signet remains quarantined. A
passing local mechanism campaign is not approval of a public contract,
mainnet services, portable RGB recovery or a signed store release.

## Current boundaries

| Area | Implemented or proven | Still required |
| --- | --- | --- |
| Native consumer | Final `.2` / `8ac556ee…` has separate host, 20 funded mobile case and 14 existing-only-open mobile case evidence in the SDK. | Requalify affected behavior on any successor archive. An older source's execution is historical evidence only. |
| Aster runtime | Actual iOS 27 and Android 17 flows passed registration, Create/quiz/naming, lifecycle, BTC/RGB receive/send, exact history and intact-store process reopen. Android proved the app's one-confirmation receive policy from an unconfirmed receipt. | Preserve exact source/artifact/proof admission. These Debug regtest campaigns do not qualify a signed store binary or public deployment. |
| Qualification entrypoint | A Debug-only regtest constructor uses an actual IO manager below `aster_full_wallet_qa/<run>/native`. Ordinary factory, resolver and runtime admission remain closed. | A uniquely named retained run, admitted existing fixture and sequential financial window. Release/Profile and public/Dev chains cannot use this constructor. |
| Partial RGB cancellation | Details-only reviewed action uses the distinct native revocation API and verified archive capability. The final SDK records sealed signed-revocation and both mobile ABI proofs; Aster's action ownership has targeted tests. Check never gains this external mutation permission. | Retain archive/capability admission. Controlled Aster UI screenshots are fixtures, not an additional real revocation execution. |
| Backup freshness | Stale coherent backups retain quarantine. Seed import does not reconstruct RGB state. | No approved freshness service exists. Portable full-RGB restore and unrestricted restored-wallet spending cannot be claimed or enabled. |
| Public deployment | Contract bytes/digest, identity, metadata and EVM lock policy are explicit. | Approve and fund the actual public deployment. Local QBFA is not public USDT. Dev remains blocked independently. |
| Release configuration | L1 rejects LSP/VSS. Internal BTC-only validation no longer requires incompatible VSS; public BTC/USDT still requires complete approved USDT metadata and EVM policy. | Final release admission remains closed after structural validation. |
| iOS privacy | App-owned FileTimestamp C617.1 is declared. The unsupported app-owned DiskSpace E174.1 claim was removed. | Native call-path disposition and final signed-app required-API/aggregate privacy evidence. Legacy RLN's independent finding remains unresolved. |
| Delivery | Complete 64-bit Android ABI selection and bounded package gates exist. | Exact final Aster signed release, ABI/ELF/ZIP, privacy and distribution-identity evidence; no simulator/debug success substitutes for these. |

## Real app campaign

The entrypoint is `integration_test/rgb_l1_wallet_flow_test.dart`; it cannot be
selected by a flag in the normal app. `ASTER_QA_STAGE=lifecycle` performs the
ordinary Create Wallet UI, recovery quiz, naming, zero-balance checks, three
suspend/resume cycles and provider teardown/bootstrap against the same intact
store. Secret words stay in RAM and are never exported in control messages or
screenshots. This is a normal restart, not backup restoration.

`ASTER_QA_STAGE=rgb-l1-full` additionally requires one host-owned, journaled
public-only controller and the exact approved fixture contract. Its requests
have unique IDs and no automatic retry:

| Event | Controller responsibility |
| --- | --- |
| `fund_requested` | Fund exactly 100,000 regtest sats once, confirm them and return one owned `btc_send_address`. |
| `btc_confirm_requested` | Independently verify the exact submitted BTC/RGB transaction and expected recipient/amount, progress the existing recipient protocol if needed, then append confirmation blocks once. |
| `rgb_witness_funding_requested` | Transfer exactly 100 existing QBFA units to the native witness invoice once; return a fresh, exact 50-unit witness `return_invoice`. Never rewrite or extend an invoice. |
| `rgb_setup_confirm_requested` | Confirm only the exact reviewed change-output preparation transaction; never create replacement outputs. |
| `fixture_backup_requested` | Preserve the run's closed private local storage and verify the copy. A copied snapshot receives no restore/spending authority. |

The app sends 1,000 sats through the actual Send UI, checks exact confirmed
history, receives 100 QBFA through the ordinary witness Receive UI, reviews and
cancels change preparation without creation, then explicitly prepares outputs
once. Preparation never automatically sends tokens. A later deliberate Send
returns 50 units, verifies its exact accepted/confirmed record and remaining
50-unit balance, and checks the dedicated success screen and Continue action.
A stale fee is refreshed only through its deliberate non-dispatching review
action; no payment Commit is retried.

The final Android campaign observed the new witness request at zero
confirmations with 100 future units, zero settled/spendable units and pending
history. Exactly one appended block made that request eligible to complete;
change preparation and the subsequent 50-unit return were confirmed separately
with three blocks each. Aster explicitly requests `minConfirmations: 1`, for
both amount-specific and amountless requests. The SDK's compatible zero default
is unchanged. The retained iOS incoming request predates this app policy change
and was independently confirmed with three blocks; it is not one-confirmation
policy evidence.

After a successful funded flow, a public completion checkpoint selects a
separate observation-only branch on the same artifact's next process launch.
It requires the exact READY wallet, native profile/cohort, 50-unit balances,
confirmed gross BTC/RGB records, and empty native/app payment fences. It returns
before mounting Aster UI or portfolio owners and does not run generic RGB
refresh, maintenance, funding, preparation or payment commands. A missing or
changed checkpoint cannot fall back to creating or restoring a wallet. This is
an intact-storage restart, not portable backup or mnemonic-only RGB recovery.

The [mobile qualification record](../handoff/BFA7_ASTER_MOBILE_QUALIFICATION_20261108.md)
identifies each actual artifact, execution scope, preserved harness failures and
public evidence digest. In particular, iOS onboarding, BTC/receive and final
return were composed from the same retained wallet across three named runs;
Android's final fresh campaign completed all those steps in one run.

Launch retained qualification artifacts with `flutter drive
--use-application-binary=<owned-artifact> --keep-app-running`, supplying the
assigned integration driver, target and device. In the pinned Flutter tool,
`--no-keep-app-running` stops **and uninstalls** the app; it is unsafe for a
retained wallet campaign because uninstall also removes Android Keystore
entries. Await the harness's native-disposal and backup acknowledgement, then
stop only the owned process (`adb shell am force-stop <qa-package>` or
`simctl terminate <device> <qa-bundle>`). Never uninstall, clear application
data, reset a simulator or assume a copied encrypted store restores its keys.
The earlier Android c attempt exposed this launcher mistake after its
BTC-only, pre-send checkpoint; its backup and failure evidence are retained,
and it is not evidence of portable recovery or a product wallet failure.

The optional Debug-only `rgb-l1-resume-funded` stage is limited to an intact
owned pre-send store. It requires a different run ID, the exact original public
identity, one READY wallet, exactly 100,000 settled/spendable sats, zero RGB,
no pending submission and no sent history. It uses the previously approved
destination without another funding request. Missing storage or any changed
checkpoint fails closed; the stage does not restore a backup or replay a send.

Before running, read the existing stack's `AGENTS.md`, consumer documentation
and registry, then the fixture owner's runbook and the SDK qualification record.
Use the existing compatible fixture only. Android L1 endpoints use loopback
with owned `adb reverse` mappings, not the legacy adapter's host alias. Preserve
all containers, chains, contracts, other wallets and prior attempt records.
Do not start the campaign until its financial window and source/artifact
identity have been assigned. A failed or ambiguous step is preserved and stops
the campaign; restarting the runner is not authorization to repeat it.

## Explicit revocation authority

The extra action appears only on the exact unknown RGB payment's details and
only after the native archive verifies dispatched-revocation support. It uses
the shared confirmation dialog with blue primary action. Capability problems
stay quiet; cancellation produces one concise action-owned toast. Route,
wallet and foreground changes invalidate presentation and pre-dispatch consent.

Ordinary Check and passive discovery never invoke the revocation API. Native
acceptance wins over cancellation. Only an authoritative native rejection with
the signed `cancelled` certificate may retire a dispatched fence, followed by
the existing durable app acknowledgement. Unknown/released responses, a failed
capability read, mismatched request, or failed acknowledgement retain protection.
No rejected response becomes permission to resubmit the old operation.

The controller is deliberately manual: `scripts/rgb-l1-qa-control.py` only
journals events and serves exclusive responses; it contains no RPC, wallet,
mining or transfer invocation. Start it only for the assigned run and port, then
inspect each request and execute its authorized fixture action separately.
Use port **29671**, matching the integration app's existing strict loopback
control policy, and run platform campaigns sequentially. Do not use the older
49889 draft command; it fails application admission before onboarding. The
Android manifest binds its existing fully qualified Kotlin activity, so a
separate QA application ID does not resolve a nonexistent relative activity.
`reply --id ... --payload-file ...` accepts a response only for an existing
request and refuses replacement. Duplicate identical publication is one intent;
a conflicting body or cross-run ID is rejected. Private-key fields, duplicate
JSON keys, excessive input and unsafe paths are rejected. The local controller
unit tests do not contact any network or fixture:

```sh
python3.13 scripts/test_rgb_l1_qa_control.py
```
