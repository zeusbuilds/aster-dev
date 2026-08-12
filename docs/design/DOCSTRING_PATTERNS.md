# Dart Documentation Policy

Documentation explains contracts that types and names cannot make obvious. It
must stay true when read without implementation details.

## Document

- exported/public APIs
- lifecycle ownership and disposal requirements
- units, precision, normalization, and ordering
- side effects and mutation serialization
- failure, retry, cancellation, and unknown-outcome behavior
- security/privacy invariants
- non-obvious platform or SDK constraints

## Do Not Narrate

Avoid comments such as “returns the value,” “builds the widget,” or descriptions
that only repeat a field name. Prefer a better name or no comment. Generated
files are never manually documented.

## Examples

```dart
/// Sends [amount] in the target's integer smallest unit.
///
/// The mutation is serialized with lifecycle operations and is never retried
/// automatically. A failure may have an unknown native outcome.
Future<AppResult<PaymentReceipt>> send(PaymentCommand command);
```

```dart
/// Releases the active native owner after all queued operations settle.
///
/// Calling this method more than once is safe.
Future<void> dispose();
```

Use square-bracket references only when Dartdoc can resolve them. Keep examples
secret-free and use impossible placeholder identifiers, never real payment or
wallet material.

## Gate

`make docs` generates into a unique temporary directory, validates links, fails
on reported warnings/errors, and removes output afterward. This prevents stale
ignored pages from masking documentation regressions.
