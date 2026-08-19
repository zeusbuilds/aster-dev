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
- Authentication for seed viewing and xpub export is not selected.
- Recovery-screen screenshot/screen-recording policy is not selected and has
  platform asymmetry.
- SDK native artifact provenance is accepted for internal beta only.
- No public security-reporting contact is configured in this repository.
- Store privacy/data-safety disclosures, an owned privacy-policy destination,
  and cryptography/export-compliance answers are not approved. They require a
  release-owned data-flow review across every configured wallet service.

These are tracked blockers. Sensitive actions remain disabled rather than
shipping an implicit policy.

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
