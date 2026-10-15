# On-chain Send submission recovery

Aster persists the reviewed Bitcoin or RGB Send command before dispatching it.
The wallet-scoped journal binds the intent to its wallet ID, private storage token,
network, amount, exact destination, fee review, and RGB recipient/output policy.
Its storage uses the existing owner-only, backup-excluded, flushed two-slot native
metadata replacement policy. A corrupt present slot is an error; financial records
never fall back to a stale earlier accepted or unsubmitted document.

## Durable states and admission

- `submitting`: dispatch may have started. The marker is not proof of broadcast
  success or failure. Native/transport/protocol ambiguity leaves this state intact.
- `accepted`: an exact native response was durably saved before success could be
  returned to presentation. It requires a canonical transaction ID, the reviewed
  asset/amount, and (for RGB) the native batch index. This proves native acceptance,
  not confirmation/finality. The receipt remains available after restart.
- `rejected`: the native adapter explicitly proved a local predispatch validation
  rejection. That fact was saved before another user-reviewed attempt is allowed.
  Generic retryable errors, empty history, and native HTTP error messages are not
  proof of rejection.

An interrupted `submitting` record reinstalls a mutation fence on bootstrap. Send,
new receive requests, RGB output preparation, wallet switching/creation, and exports
are denied. Balances, fee/network reads, synchronization, and Activity remain
available through a narrow read-only lease. The Activity screen shows the retained
submission warning and an explicit **Check payment status** action. This action
never sends or repeats a mutation. A denied wallet switch preserves the current
wallet's presentation state so Activity stays reachable.

Background suspension closes the reader; resume reopens it with the fence intact.
A lost lifecycle/disposal response or a stronger native owner/storage error escalates
to complete runtime quarantine. Exact payment history cannot repair an uncertain or
partially destroyed native owner.

## Exact reconciliation and the remaining native limitation

If an accepted receipt became durable immediately before its storage acknowledgement
was lost, the current process stays fenced. Explicit reconciliation requires exactly
one native record with the recorded transaction ID, asset, amount, outgoing operation,
and (for RGB) batch index. Similar amounts, timestamps, an empty feed, duplicate
matches, and unrelated earlier receipts cannot resolve it.

After restart, a durable `accepted` receipt is authoritative recorded native
acceptance, exactly like a normally returned successful submission; it is surfaced
in Activity data and retains the exact transaction identity. Restart never turns a
`submitting` record into `accepted`.

If the process dies after native dispatch and before the native transaction identity
can be saved, the Flutter interface currently supplies no durable native request ID
that can bind a BTC history record to that reviewed intent. Aster therefore keeps
that submission fenced, including after restart, even if an apparently matching
transaction exists. Universal automatic recovery requires an upstream persisted
request/transaction correlation protocol. Do not delete the journal, restore an
older journal slot, guess by amount/time, or rerun Send as a recovery step. This
change prevents blind replay; it does not claim universal unknown-outcome recovery.

## Verification

The payment submission suite injects failures before marker acknowledgement, during
native dispatch, and after native acceptance, and recreates runtime/repository owners
against preserved storage. It covers concurrent submits, accepted/rejected receipts,
malformed transaction IDs/batches, corrupt/stale records, exact/ambiguous histories,
background/resume, stronger cleanup failures, and mutation gates. ViewModel/widget
coverage verifies persistent Activity access and warning/status controls. These are
controlled local fault tests; no stack/container or real funds are used.
