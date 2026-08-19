# Haptic Feedback

Aster uses semantic haptic intents. Presentation code requests what happened;
the app-owned adapter decides which platform pattern represents that intent.
Feature code must not import `haptic_feedback` or call `Haptics` directly.

## Contract

Use `context.haptics.trigger(...)` from an accepted interaction or inject
`hapticFeedbackServiceProvider` into a Riverpod-owned presenter. Haptic failure
is never part of action success or failure: the adapter caches its capability
probe and absorbs plugin/platform errors.

| Intent | Meaning | Typical uses |
| --- | --- | --- |
| `selection` | A value or choice changed | tab, asset, wallet, currency, region, unit, toggle |
| `lightImpact` | A low-impact local command was accepted | copy, reveal, max, paste, scan capture |
| `commit` | A meaningful mutation was submitted | create/import wallet, send, pay, open/close channel |
| `success` | An asynchronous operation actually succeeded | confirmed wallet creation, send, payment, sync |
| `warning` | A meaningful caution state was reached | permission denied, insufficient funds, expiring request |
| `error` | An operation actually failed | rejected send, failed import, camera or network failure |

The platform adapter currently maps `commit` to medium impact and enables
Android's native haptic constants. That mapping belongs in one adapter and may
be tuned without changing feature code.

## Timing Rules

- Trigger selection or local-impact feedback only after an enabled interaction
  is accepted.
- Trigger commit once when a real mutation starts. Do not also emit a generic
  tap haptic from the same control.
- Trigger result feedback only when the asynchronous result is known.
- Never emit feedback on pointer-down, disabled/loading controls, every
  validation keystroke, or an already-selected option.
- Never delay navigation or business logic while awaiting haptics. Use
  `unawaited`; the service is best-effort presentation feedback.
- Avoid automatic haptics for ordinary back navigation and high-frequency
  scrolling.

## Widgets

`CustomButton`, `AsterIconButton`, selection rows, and bottom navigation accept
or own a semantic intent. Prefer those controls to one-off gesture wrappers.
For a new interaction, decide first whether the state changed, a local command
was accepted, a mutation began, or a result arrived.

```dart
void copyAddress() {
  unawaited(context.haptics.trigger(HapticIntent.lightImpact));
  // Perform the accepted local command.
}
```

## Testing

Override `hapticFeedbackServiceProvider` with a recording implementation. Tests
must cover disabled/loading suppression and ensure one accepted interaction
emits at most one tap intent. Unit tests also prove that capability and emitter
failures never escape the adapter.

Simulators cannot validate tactile quality. Final release evidence must record
the device model and OS used for physical-device tuning; until that pass exists,
haptic feel remains unverified even when intent mapping tests pass.
