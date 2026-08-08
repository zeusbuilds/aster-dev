# Presentation Systems

This guide covers cross-feature interaction behavior. Business outcomes remain
owned by ViewModels and repositories; widgets own only transient presentation.

## Buttons And Submission

`CustomButton` has stable geometry, keyboard activation, a minimum 48-point tap
target, explicit disabled/loading semantics, and duplicate-tap suppression.
Mutation buttons stay loading on the current screen until the operation returns
a confirmed result. Navigate only after success. Ordinary navigation does not
show artificial loading.

Controls are disabled when prerequisites are incomplete or an incompatible
operation is active. A disabled or loading control emits no haptic.

## Toasts

Transient feedback goes through `context.toasts`. The Riverpod controller owns
a bounded, deduplicated FIFO queue; the single `ToastHost` owns animation and
timer lifecycle. Do not create `OverlayEntry`, static toast globals, or feature
timers.

- `success`: a transient operation actually completed.
- `failure`: a recoverable operation failed.
- `warning`: an actionable caution or temporary limitation.
- `info`: neutral transient information.

Validation errors stay inline. Initial/loading/error/empty states that affect
the whole screen stay on-screen with an explicit retry action. Toast content is
bounded and must never include secrets, invoices, preimages, wallet paths,
native payloads, or raw exception text.

## Motion

Every authored duration and curve comes from `context.motion`; every animation
resolves reduced-motion behavior through `context.motionPolicy`. Decorative
loops settle on a deterministic frame. Widgets dispose controllers/timers,
hidden tabs disable tickers, and navigation never waits for cosmetic delays.

## Insets

Use `SafeArea` for conventional roots. `context.windowInsets` distinguishes the
current safe viewport, persistent hardware padding, and keyboard obstruction.
Bottom overlays such as floating navigation use persistent bottom-system
padding; forms and sheets let `SafeArea` and keyboard insets cooperate without
double padding.

## Accessibility

Interactive surfaces use Material controls (`InkWell`, `IconButton`, buttons)
with keyboard/focus behavior and at least a 48-point target. Icon-only commands
have a tooltip or an equivalent explicit accessibility label. Loading and toast
changes are live regions. Inactive indexed screens are excluded from pointer
input and semantics.

Text must remain usable under platform text scaling. New fixed-height text
containers require compact and large-phone widget tests before acceptance.

## Shimmer

Shimmer is reserved for initial content loads and preserves final layout.
Refresh keeps existing content visible with refresh feedback. Pagination uses
inline progress. Reduced motion replaces shimmer with a stable solid treatment.
