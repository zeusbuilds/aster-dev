# Gated BFA.7 application adapter

The RGB_L1 adapter is implemented behind Aster's existing activation and release
gates. `WalletBackend.activationAllowed` remains false for RGB_L1. The resolver,
factory and runtime reject product activation; runtime does so before creating
directories, persisting credentials or constructing a native engine. There is
no compile-time override that enables this gate. Native adapter tests construct
their isolated boundary directly and do not enable a product wallet. The separate
integration entrypoint additionally uses a typed Debug-only regtest constructor
with owned `aster_full_wallet_qa/<run>/native` storage and explicit loopback
services. Profile/Release, public chains, Dev and ordinary storage are rejected;
normal app composition cannot select that constructor.

## Canonical asset bootstrap

RGB_L1 USDT configuration requires the exact contract ID and precision plus the
issuer-approved public genesis Base64, its SHA-256, and the native name/ticker.
Runtime and release tooling share bounded canonical encoding/digest validation.
The digest identifies approved bytes; it does not independently authenticate an
issuer or approve a deployment. Dev remains blocked and its historical BFA.5
export is not used as the newly issued asset.

Activation first verifies the backing EVM chain and required native capabilities.
For an already imported asset, it reads and verifies the existing native
metadata without importing again. This permits a pending-payment owner to
reopen for read-only recovery without crossing the native mutation fence.
Only the SDK's exact `ASSET_NOT_FOUND` condition permits a new import. Native
registration validates the expected asset ID; the app then verifies the returned
and reread BFA schema, native name, ticker and precision before online access.
An unavailable or malformed metadata read never becomes permission to import.
The first witness receive binds the canonical asset and exact requested amount.
Every Aster witness request explicitly requires one confirmation, including an
amountless request. An unconfirmed receipt stays pending with zero settled and
spendable RGB balance. This is an app policy; the SDK's zero-confirmation
default remains compatible for other consumers.

BFA.7 EVM configuration also requires explicit minimum/maximum mint-lock bounds.
These count **external backing EVM blocks**, not Bitcoin blocks. There is no
default; the bridge/issuer must approve the range for the exact deployment.

## Signing and lifecycle

`WalletMnemonicOpenEngine` is an optional app-owned boundary. Runtime reads the
wallet's existing secure record and supplies its mnemonic for restore, lifecycle
resume, quarantined-reader resume and drained-owner recovery. The adapter's SDK
reader exposes that value only during activation and is cleared in `finally`,
including failures. Its reader scope ends immediately after native open, before
registration and online RPC work. Signing material is never put into provider
state or retained for later automatic opens. Dart strings cannot promise physical zeroization.
Public xpub export reads the actual verified native profile derivation.

The app-owned wallet directory contains its ownership token. RGB_L1 therefore
uses a dedicated, stable `rgb-l1` child as the SDK's native directory. Fresh
provisioning requires a genuinely fresh layout; root-level legacy native state
is preserved and rejected rather than bypassed. Ready-wallet activation checks
the child and regular profile exist before reading keys, then uses the SDK's
explicit `openExisting` lease to authenticate the persisted profile/cohort and
native database. Missing/empty/ambiguous state is a nonretryable storage recovery
failure, never permission to initialize a blank same-seed RGB wallet. The parent
ownership token continues to govern recursive deletion and local snapshots.

## Durable payment flow

The app keeps its existing persist-intent, prepare, persist-commit-intent, commit
and exact status/cancel flow. RGB_L1 uses the SDK's version-3 envelope, binding
the native backend/source/overlay, wallet identity, storage cohort and complete
reviewed request. A changed amount, recipient, asset, fee, witness output or
wallet/cohort is rejected. Direct one-shot product sending is unavailable.

Restored requests are checked against the original approved intent. An expired
RGB invoice can be revalidated for read-only status without authorizing another
preparation. For an invoice that contained no expiry, only its originally
derived deadline and fingerprint are excluded from comparison; native dispatch
and inspection continue to use the original persisted bytes. No deadline is
extended, no timeout clears a monetary fence, and no monetary call retries.

Native pending-record inventory independently blocks deletion, including when
an app marker is absent. An incomplete audit is never an empty/safe result.
Authenticated pending native inventory reconstructs a missing app marker using
the original approved version-3 command, bound to the current wallet/source/cohort.
The app records that origin explicitly. Reconstructed records never authorize
Commit, including the explicit Resume path; status reads may establish exact
acceptance, or native cancellation may certify that a pre-commit preparation
cannot send. Conflicting/multiple records fail closed. RGB recovery stores the
native recipient reference without inventing the original invoice, and its fee
is historical evidence without an invented quote target or renewed freshness.
The local discovery timestamp is not presented as the unknown original payment
time; a native RGB recipient reference is not presented as an original invoice.

Native accepted receipts preserve an exact approved gross amount independently
of the app journal, including Bitcoin self-transfers. Revision-consistent bounded
pagination matches the actual chain-history row by asset/transaction/batch and
recipient when available. It never creates an activity row or changes native
status, confirmation, ownership, time or fee. Conflicting amounts/identities fail
closed. A changing revision may repeat reads once; no payment action retries.

Expired unfunded receive requests are reconciled only through native guarded
selection; no send is resumed or authorized. A native backup can be a coherent
but old snapshot of an operation that later continued elsewhere. Restored native
snapshots therefore cannot certify absence, authorize cancellation or permit a
new spend until freshness authority is qualified. Exact historical acceptance
may remain readable, but `RECOVERY_RESTORE_UNCERTAIN` preserves the mutation
fence. Intact-storage funded mobile qualification has passed; portable restore
freshness authority remains unavailable and is a separate release blocker.

## Truthful backend observations

On-chain network information carries its native wallet identity. An unobserved
tip and unavailable Lightning node/channel/peer observations remain absent;
confirmation counts remain unknown until a tip exists. The existing Settings
layout uses its compact unavailable value and omits unsupported Lightning rows.
The RLN path retains its existing observations and presentation.

Sync waits for one chain sync and one detailed RGB transfer refresh. Any batch
failure, including an older witness whose ancestry cannot currently be checked,
makes the overall refresh unavailable even when newer batches succeeded. Home
keeps its entire last-known portfolio and its existing quiet background recovery;
it does not reread or publish the partially refreshed cache, add inline prose or
show an unsolicited toast. Native failure text never becomes user-facing copy.

RGB-output preparation binds an explicit identity kind. Existing RLN reviews
retain their historical compressed-node-key encoding; RGB_L1 binds its real
native wallet-profile hash. The legacy serialized `nodePublicKey` field is
interpreted only with that kind, so a wallet-profile hash is never represented
as a Lightning public key. Separate preparation cost/confirmation protections
remain unchanged.

### Explicit change-output preparation from Send

For RGB_L1 USDT only, an explicit Send action first reads the existing setup
journal and native output inventory. If an output is ready, payment validation
can proceed. Otherwise a required preparation opens the shared confirmation
dialog with the exact output count/value, reviewed sat/vB rate and disclosure
that a total fee cap is unavailable. Cancel never creates outputs. Only Prepare
dispatches the existing journal-protected native creation once. The app remains
on Send amount, gives one action-owned toast and never automatically sends USDT
afterward. A later Send checks pending/uncertain setup read-only; it cannot replay
creation. Wallet/foreground changes and expired reviews prevent dispatch.

Preparation identity includes the actual native wallet binding, storage cohort
and sealed source identity, preventing a review from moving to another copy of
the same account. The existing RLN flow and all activation gates are unchanged.
The presentation is tested using an isolated fake native engine with the real
repository journal. Actual iOS/Android Aster campaigns also reviewed/cancelled
preparation, prepared once, confirmed the exact transaction, and subsequently
sent once. Native interrupted/reply-loss coverage remains identified separately
in the SDK qualification record.

Deletion reads the complete native unspent allocation inventory. Every
assignment kind is protected, including mint/inflation rights with zero fungible
balance, foreign assets and unsettled allocations. Missing, malformed or failed
inventory never authorizes deletion. The inventory is read again after transfer
refresh so newly received rights cannot be missed.

Both final platform native artifacts and the actual Aster funded/lifecycle flows
have exact recorded regtest acceptance, including a separate process reopen
with the same intact storage. Portable RGB backup restoration has no approved
freshness service; local tests cannot invent that authority, so the product gate
remains closed. Dev contract/deployment admission is independent and remains
blocked even when non-Dev local mechanisms pass. Public contract/service,
aggregate privacy and signed release delivery admission remain separate gates.

## Deliberate dispatched-handoff revocation

A verified successor archive advertises dispatched RGB revocation separately
from ordinary Cancel. Only an explicit reviewed action on the exact unknown
payment's details invokes `revokeOnchainSend`. Check and passive reads retain
pre-dispatch-only Cancel, including when a queued dispatch races their observed
state. Eligibility reads add no messages or loaders; the compact action is
hidden when unsupported. The shared confirmation keeps a blue primary action
and a separate Keep payment choice.

Native acceptance wins over cancellation. A signed `cancelled` rejection must
be acknowledged durably before the app retires its fence. Unknown/released
outcomes, changed request or wallet, and failed acknowledgement preserve it.
Route/foreground/wallet changes suppress stale presentation; duplicate taps
cannot invoke another revocation. No Begin/End/Commit is retried.

See [the current qualification boundary and harness](RGB_L1_ACTIVATION_QUALIFICATION.md).
