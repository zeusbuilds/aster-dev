# Network Reliability

All app HTTP traffic goes through `ResilientHttpClient`. Feature widgets never
create clients or issue requests.

## Deadlines

The default policy has separate connection (15 seconds), response (20 seconds),
and whole-operation (45 seconds) deadlines. Each GET is abortable, and one
monotonic operation budget covers every attempt and backoff delay so timed-out
work cannot continue issuing retries. Native wallet operations use the SDK's
typed timeout policy and remain serialized behind `WalletRuntime`; app-side
timeouts must not release that queue while a non-cancellable native call runs.

## Retry Contract

Only GET requests retry automatically. The policy allows three total attempts
with capped exponential backoff and jitter. HTTP `Retry-After` is honored within
the whole-operation deadline. Rate limits, request timeouts, network failures,
and transient server errors may retry. TLS failures, malformed responses, and
non-transient 4xx responses do not.

Mutation retries are intentionally absent. Sends, payments, wallet creation,
imports, and channel operations must not retry until the concrete API offers a
real idempotency contract and the app supplies its key.

Riverpod's default timer-based provider-build retry is disabled at the
production composition root. An initial provider failure remains visible until
an explicit ViewModel retry command or a deliberate dependency invalidation
runs. Bootstrap, mnemonic generation, Receive request creation, and other state
machines therefore retain ownership of whether repeating work is safe; only the
HTTP GET policy above retries automatically.

## Failure And Privacy

Repositories return `AppResult<T>`. `AppFailure` carries a stable code,
category, retryability, optional retry delay, and internal cause. Presentation
uses only its redacted user message. Response bodies, SDK error payloads,
invoices, seeds, tokens, and wallet paths are not logged or rendered.

Successful HTTP bodies are bounded to 1 MiB before decoding. Reachability is
inferred from real, classified request results. A platform connectivity hint
may be added for a concrete UX later, but it must never suppress requests or be
treated as proof of Internet access.
