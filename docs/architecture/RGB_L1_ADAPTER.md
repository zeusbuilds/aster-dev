# Gated BFA.7 application adapter

The RGB_L1 adapter is implemented behind Aster's existing activation and release
gates. `WalletBackend.activationAllowed` remains false for RGB_L1. The resolver,
factory and runtime reject product activation; runtime does so before creating
directories, persisting credentials or constructing a native engine. There is
no compile-time override that enables this gate. Native adapter tests construct
their isolated boundary directly and do not enable a product wallet.

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
fence. Full native/mobile funded and restore qualification remains required.

## Truthful backend observations

On-chain network information carries its native wallet identity. An unobserved
tip and unavailable Lightning node/channel/peer observations remain absent;
confirmation counts remain unknown until a tip exists. The existing Settings
layout uses its compact unavailable value and omits unsupported Lightning rows.
The RLN path retains its existing observations and presentation.

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
repository journal; funded/mobile setup and interruption qualification remain
requirements before RGB_L1 activation.

Deletion reads the complete native unspent allocation inventory. Every
assignment kind is protected, including mint/inflation rights with zero fungible
balance, foreign assets and unsettled allocations. Missing, malformed or failed
inventory never authorizes deletion. The inventory is read again after transfer
refresh so newly received rights cannot be missed.

Both platform native artifacts, funded transfers, interrupted sends, process
restart, mixed/lost storage, encrypted backup restoration and the exact Dev
contract/deployment must pass qualification before the gates are lifted.
