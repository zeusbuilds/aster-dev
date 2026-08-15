# Security Model

UTEXO is wallet software. Security changes require evidence across Dart,
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
  disabled; cloud backup and device transfer are disabled.
- Metadata uses a checksummed two-slot journal and ownership-bound recovery.
- Corrupt, unknown, or legacy records are preserved and fail closed.

Dart strings cannot be reliably zeroized. Keep secret objects route-scoped and
inside the narrowest asynchronous scope; release references deterministically.

## Runtime And Network

All native wallet calls pass through the serialized `WalletRuntime`. All
app-owned HTTP passes through `ResilientHttpClient`. Public destinations and
service endpoints reject credentials and unsafe host/scheme forms. Mutation
requests are not retried without a real idempotency contract.

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

## Open Security Decisions

- Authentication for seed viewing and xpub export is not selected.
- Recovery-screen screenshot/screen-recording policy is not selected and has
  platform asymmetry.
- Legacy wallet recovery requires an explicit migration/support policy.
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
