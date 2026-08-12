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

Errors exposed outside adapters are typed, bounded, and redacted. Production
logs contain stable codes only and never raw native/network payloads.

## Open Security Decisions

- Authentication for seed viewing and xpub export is not selected.
- Recovery-screen screenshot/screen-recording policy is not selected and has
  platform asymmetry.
- Legacy wallet recovery requires an explicit migration/support policy.
- SDK native artifact provenance is accepted for internal beta only.
- No public security-reporting contact is configured in this repository.

These are tracked blockers. Sensitive actions remain disabled rather than
shipping an implicit policy.

## Reporting

Use the repository owner's private security-reporting channel. Do not open a
public issue containing a recovery phrase, credential, live invoice, wallet
path, native payload, or other user data. A public release must configure and
publish an owned security contact before distribution.
