# Security Model

Aster is wallet software. Security changes require evidence across Dart,
native storage, SDK lifecycle, platform packaging, and user experience.

## Secret Classes

Recovery phrases, native database passwords, authentication secrets, tokens,
preimages, and private keys are secret. Invoices, payment hashes, wallet paths,
public keys, xpubs, and transaction identifiers are sensitive context even when
not secret by themselves.

Never place these values in logs, diagnostics, analytics, route arguments,
SharedPreferences, build defines, screenshots, source fixtures, issue reports,
or transient toasts. Tests use synthetic values that cannot spend funds.

## Storage

- One encrypted, versioned, wallet-owned credential envelope contains the
  mnemonic and independent native database password.
- iOS uses non-synchronizing, this-device-only Keychain storage and protected,
  backup-excluded wallet files.
- Android uses namespaced AES-GCM secure storage with destructive reset
  disabled; cloud backup and device transfer are disabled. The pinned plugin
  initializes its cipher markers within that namespace and cannot read a
  previous app schema or namespace.
- Native wallet-file policy validates every app-owned ancestor back to the
  trusted platform storage root, rejects symbolic and multi-hard-link aliases,
  requires owner-only modes below that root, and bounds metadata replacement.
- Each Flutter engine owns one native storage-channel session. Work is
  serialized off the platform thread, obsolete-engine completions are
  suppressed, and concurrent calls fail closed without mutating storage.
- Metadata uses a checksummed two-slot journal and ownership-bound recovery.
- Corrupt or non-current records are preserved as evidence and fail closed.

Dart strings cannot be reliably zeroized. Keep secret objects route-scoped and
inside the narrowest asynchronous scope; release references deterministically.

## Device Authentication And Sensitive Views

The approved October 25, 2026 policy uses operating-system authentication.
Aster does not create, collect or store its own PIN or passcode. App lock is
on by default for all wallets in the installation when the device has a
screen-lock credential. iOS uses `LAContext` with
`deviceOwnerAuthentication` (Face ID/Touch ID with device-passcode fallback).
Android uses its biometric/device-credential APIs with strong biometrics or
the device PIN, pattern or password; weak biometric recognition is not enough.
A biometric enrollment is optional when a device credential is available.

The user explicitly chose unrestricted access if the operating system reports
that **no device screen lock exists**, including when it is removed after a
wallet already exists. This bypass applies to app unlock, create/import,
seed viewing, xpub export, wallet deletion and App lock preferences. A failed capability check,
cancelled prompt or unavailable biometric sensor is never treated as proof
that the device is unsecured. Foreground and protected actions recheck device
security so adding or removing a device credential takes effect without a
wallet reset.

The first-run Welcome animation does not require an empty-wallet unlock.
Create/import authenticates before recovery words are generated or accepted.
For an existing wallet, cold launch holds the white opening/logo artwork at its
initial frame until authentication and wallet bootstrap complete, then plays
the reveal once. Cancellation stays on the lock cover with Unlock.
Genuine background/device-lock transitions hide the complete UI immediately;
a warm return unlocks the prior ordinary screen without replaying launch.
The native authentication sheet's own lifecycle cannot recursively relock it.

An action-owned system prompt appears above its originating screen. Create and
Import stay on Welcome; Delete stays on Wallet details; App lock changes stay
on Security. Advanced authenticates and prepares seed/xpub disclosure before
pushing a ready destination. Cancel stays on the source; a failed action has
one source-owned toast and no intermediate loading page. Direct disclosure URLs
have no authority and return to Advanced.

Visual prompt ownership is separate from wallet authority. Source content
remains painted but input, focus and accessibility actions are blocked while
authentication is pending. Wallet access and grants still require a resumed
host. Native and Dart prompt ownership last through final capability and
foreground checks, with an explicit presentation-cleanup acknowledgment. Real
background, capture, wallet changes and explicit revocation invalidate late
results, including when App lock is off. Unrelated inactivity still covers the
app, and a failed/abandoned prompt cannot leave an inactive source exposed.

iOS scopes its visual exemption to the scene presenting the LAContext; genuine
background snapshots and sensitive capture always override it. Android keeps
temporary FLAG_SECURE protection through its owned credential/prompt handoff,
then clears only that temporary protection after cleanup and host resume.

Settings > Security offers App lock, immediate automatic locking and Lock now.
Disabling App lock requires confirmation plus fresh device authentication.
Regardless of that preference, each seed reveal and xpub export obtains a
fresh, purpose- and wallet-bound, single-use authorization. Repository guards
check it inside the serialized operation and discard a late result after
lock, capture, wallet/session change or route departure. New queued wallet
work cannot begin while locked; already-dispatched payments retain their
existing journal/outcome protection and are never resent by unlocking.

Prepared disclosures use one process-local, one-use session bound to purpose,
wallet and security generation. No secret, grant or prepared session enters
route arguments, URLs, persistence or restoration state. Seed words remain in
that protected session only, with no Copy or Share action.
Xpub export explicitly labels Bitcoin and RGB account keys and offers Copy
and Share; public keys still reveal sensitive wallet activity. Backgrounding,
capture or wallet changes remove disclosed values and require a new reveal.
Native capture protection remains active until the cleared disclosure frame
is submitted; clearing in-memory values alone cannot expose a still-painted
secret frame.
Create/import holds a native sensitive-view lease throughout its private
steps. Capture covers its entire content and accessibility tree without
resetting an in-flight provisioning attempt or replaying its operation.

Android sensitive views use `FLAG_SECURE`. iOS covers app-switcher snapshots
and hides sensitive content while recording/mirroring is detected. **iOS
cannot reliably prevent ordinary screenshots**; screenshot notification is
after capture and is not presented as prevention. This platform asymmetry is
part of the approved policy. Synthetic review captures are isolated, labelled
TEST DATA and do not prove platform screenshot prevention.

The existing encrypted credential envelope is independent of this app access
policy: keys are not newly bound to a passcode or biometric enrollment that
would invalidate funds when the user removes device security. No released-user
migration is required for this unreleased app. Dart strings cannot be promised
to be zeroized. Hardware authentication, fallback/lockout and capture behavior
still require qualification on supported physical devices; Android execution
has not been performed for this change while Android builds remain deferred.
Implementation and host/Simulator review are not a mainnet release sign-off.

## Local Wallet Deletion

Settings > Wallet details deletes the selected active wallet. To remove a
different wallet, select it first. A deliberate confirmation identifies the
wallet and warns that a recovery phrase alone cannot restore USDT/RGB state.
Cancel, dialog dismissal and cancelled system authentication leave its data
unchanged.

Deletion requires fresh device authentication even when App lock is off. The
authorization is single-use, bound to the deletion purpose, wallet and security
session, and consumed inside the serialized repository operation. The approved
no-device-screen-lock policy applies here too: an authoritative unsecured-device
result bypasses authentication; capability or sensor failures do not.

The authentication owner waits for Flutter foreground both before and after
the final device-security status reply. A successful native prompt can precede
its lifecycle events; a late `inactive` event during that last status request
must not silently discard an otherwise valid completion. Genuine background,
wallet/session changes and request revocation still invalidate the grant. This
is covered through the full application/router and production MethodChannel
adapter; an ordinary pre-fix native run is not evidence of a failed ordering.

Before recording irreversible authority, Aster checks selected runtime/registry
identity, unresolved outgoing payments and RGB preparation records, then audits
the native wallet. Nonzero RGB holdings, nonterminal RGB transfers or an
unavailable/untrustworthy audit block removal. All imported RGB contracts are
checked, including asset-less pending receives. An exact expired, unfulfilled
receive may be retired only after the native check and a fresh state read. Time
alone does not establish that it is safe. The audit never dispatches/resumes a
payment. Bitcoin-only holdings are not an RGB-holdings blocker; the confirmation
still requires the user to retain the recovery phrase.

RLN requires an asset or transaction filter for transfer history. Aster's
deletion audit therefore reads the imported asset inventory and per-asset
history, plus the native refresh map for batches whose incoming asset is not
yet known. A null refresh `updatedStatus` means unchanged/pending, never an
empty or safe result. Native `noAssetOnly` reconciliation may retire only
eligible expired unassigned receives. A current waiting request continues to
block deletion even when the imported asset inventory is empty. After any
reconciliation, inventory, balances and transfer state are read again. Native
query rejection, malformed state or unavailable refresh fails closed. The SDK
correctly rejected Aster's former unscoped query and was not changed for this
fix.

An action's feedback follows the authoritative top page key, effective URI and
shell tab. A router metadata refresh must not replace an imperatively pushed
Wallet details page with its underlying Home URI and discard its result.
Actual navigation, a covered origin or wallet changes still expire obsolete
feedback. A refused deletion shows one action-owned toast; it adds no inline
operational paragraph. This routing defect and the native query defect are
separate from the authentication completion ordering fix above.

A durable `deleting` profile is written before destructive cleanup. That exact
record authorizes idempotent cleanup across restarts without a new deletion
grant. Aster closes the native wallet, removes its wallet-owned credential and
owned native directory/tombstone, then removes wallet-scoped payment and setup
records and finally the registry profile. Ownership and path checks remain in
force. Missing native data is not permission to invent a deletion. Partial
cleanup or a failed survivor activation blocks wallet access rather than
presenting an erased wallet as usable. The owned Retry resumes committed
cleanup, never a payment and never an unreviewed wallet removal.

The SDK native close call is uncancellable and must drain before files can be
removed. If that native work never settles, process restart is the recovery
boundary. Elapsed time does not release its owner for concurrent cleanup; not
all native calls are bounded. An application deadline cannot safely cancel
that native work or authorize erasure beneath it.

With surviving wallets, Aster opens the first remaining ready profile. Only a
committed empty registry clears wallet presence and returns to Welcome; there
is no empty-wallet unlock prompt, while the next Create/Import still follows
its normal authentication policy. Existing security preferences are retained.
Deletion removes local application data. It does not move funds, remove chain
history, erase copies held elsewhere or guarantee physical secure erasure of
flash media. No release or physical-device qualification is implied by this
source contract.

## Runtime And Network

All native wallet calls pass through the serialized `WalletRuntime`. All
app-owned HTTP passes through `ResilientHttpClient`. Public destinations and
service endpoints reject credentials and unsafe host/scheme forms. Service
values are bounded visible ASCII, use canonical DNS/IP syntax, and reject
resolver-dependent numeric aliases before crossing the native bridge. Mutation
requests are not retried without a real idempotency contract.

Insecure loopback service transports are a Debug/Profile-only regtest
capability. Release composition rejects HTTP, unencrypted Electrum, and
unencrypted RGB transport before native creation on both platforms. Release
regtest deployments must provide explicit TLS-protected service endpoints.

A wallet failure that retains or cannot prove consistency of a native handle,
directory, credential, or registry record is marked `requiresReconciliation`.
The runtime preserves the first exact failure and rejects subsequent wallet
mutation, including work already queued. Unknown mutation outcome is a stricter
subset of this state. Audit cannot clear or replace the failure; only successful
same-wallet rollback or runtime disposal can release the quarantine.

Third-party market credentials are never compiled into the app. Release market
requests require a deployment-owned HTTPS proxy; direct provider hosts and
credential-bearing endpoint values fail closed. The proxy is infrastructure,
not a place to forward wallet, payment, or user identity data.

Errors exposed outside adapters are typed, bounded, and redacted. Production
logs contain stable codes only and never raw native/network payloads. Android
release builds use R8 to remove dependency `android.util.Log` calls; debug and
profile builds retain native diagnostics for local investigation. A future
production telemetry system must use an app-owned redaction boundary instead
of re-enabling arbitrary dependency logs.

Build inputs are part of the security boundary. The Gradle wrapper checks its
distribution digest, Gradle rejects unreviewed external artifact checksums, and
iOS tooling is resolved from the checksummed Bundler lock rather than an
arbitrary host CocoaPods executable. Verification metadata is reviewed source;
regenerating it is a dependency change, not a routine way to make a failed
build pass. Every release package consumes one sorted, bounded, non-secret JSON
manifest. Unknown keys, placeholders, insecure/private endpoints, direct market
provider hosts, credentials, and malformed RGB identity fail closed before
packaging. Local manifests and iOS export policies are ignored; their digests,
not their deployment values, belong in release evidence. Android release
inspection re-hashes directly executed Gradle-cache
JARs at point of use through bounded streaming reads. Signed AAB evidence
requires complete one-certificate coverage for every payload entry; a matching
certificate on only part of an archive is rejected. APK/AAB archive inspection
rejects duplicate and unsafe entry names, bounds archive and expansion
resources, proves the exact native ABI/runtime-library matrix, and writes only
validated native basenames beneath an owned temporary directory. Line-oriented
ZIP output and wildcard extraction are not trusted security boundaries.
Every repository-owned shell entrypoint runs external work through one pinned
Dart subprocess boundary with independent stdout/stderr byte ceilings, strict
incremental UTF-8 decoding, an operation-class deadline, redacted watchdog
errors, and complete POSIX process-group cleanup on success or failure. Quick,
artifact-inspection, and build/platform profiles are fixed centrally; callers
cannot select a different runner through the environment. Nested pipelines run
inside that owned process group, preserve every status with `pipefail`, and
retain only the bounded result needed for the decision. Android identity,
signature, archive, ELF, package-state, renderer, Git-hook, and iOS simulator
paths all use this contract. A watchdog failure invalidates evidence; it does
not justify an automatic mutation retry.

iOS archive verification compares packaged identity with committed source,
validates the exact approved privacy declarations and local-network-only
transport policy, bounds installed size, and hashes the executable. Signed
exports additionally preflight the
actual IPA against archive-path and expansion attacks, then require matching
identity/privacy metadata, platform signature verification, embedded
provisioning, installed-size bounds, and package/executable digests from its
extracted app. These mechanical checks do not establish certificate ownership,
legal export classification, or App Store approval.

## Open Security Decisions

- Apple's export-compliance classification for the app and native wallet
  cryptography requires release-owner/legal approval. The repository must not
  infer or publish `ITSAppUsesNonExemptEncryption` before that decision.
- The approved device-authentication and capture policy above is implemented;
  physical iOS/Android authentication and capture qualification remains open.
- SDK native artifact provenance is accepted for internal beta only.
- No public security-reporting contact is configured in this repository.
- Store privacy/data-safety disclosures, an owned privacy-policy destination,
  and cryptography/export-compliance answers are not approved. They require a
  release-owned data-flow review across every configured wallet service.

These are tracked release blockers. Enabled sensitive actions follow the
explicit device-authentication policy above; their implementation does not
resolve the separate hardware and distribution qualification requirements.

## Platform Privacy Manifests

The iOS Runner aggregate-declares the required-reason APIs used by app-owned
storage and the statically linked wallet executable: file metadata inside the
app container and disk-capacity checks that can prevent a write. It does not
declare tracking. The pinned wallet SDK's own privacy manifest is empty despite
those native imports, so the Runner declaration is an app-level mitigation for
that exact revision. Other package-owned API use, including preferences, remains
in each dependency's own privacy manifest and is not duplicated in the Runner.

This technical manifest is not a substitute for App Store privacy answers,
Google Play Data safety declarations, a privacy policy, or export-compliance
review. Those distribution disclosures depend on deployment endpoint behavior,
retention, linkage, and legal ownership and remain blocked by `SEC-015`.

## Reporting

Use the repository owner's private security-reporting channel. Do not open a
public issue containing a recovery phrase, credential, live invoice, wallet
path, native payload, or other user data. A public release must configure and
publish an owned security contact before distribution.

### App privacy declarations and native release admission

Aster has no app-owned disk-capacity check and does not claim DiskSpace reason
`E174.1`. Its own privacy manifest retains the justified FileTimestamp `C617.1`
category for app-owned files and disables tracking. The archive verifier rejects
an unsupported extra category; adding a reason cannot approve an unreviewed
native call path. SDK/native privacy and the exact signed app's API/aggregate
manifest report remain separate release requirements. In particular, removal of
an unused RGB_L1 filesystem probe does not resolve the legacy RLN dependency's
independent privacy finding. RGB_L1 product/release admission remains closed.
