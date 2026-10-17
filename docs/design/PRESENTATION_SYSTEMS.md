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

Compact actions are true pills with a 40-point visual inside a 48-point hit
target. Use translucent pills over brand art, tonal pills for contextual
actions such as Paste/Refresh, and neutral pills for dark secondary controls.
Primary submission buttons retain the authored rounded-superellipse shape.

Tap ripples and pressed ink highlights are not part of Aster's design on any
platform. `AppTheme` uses `NoSplash.splashFactory` and transparent splash and
highlight colors. Material 3 component overlays and custom controls consume
`AsterStateLayers.interactionOverlay`: focus and hover remain visible, pointer
presses do not paint ink. Preserve the custom button's bounded scale response
and semantic haptics. Feature-local splash overrides fail the design validator.
Flutter documents the factory/overlay distinction in its
[tap-ink API](https://api.flutter.dev/flutter/material/TabBar/splashFactory.html).

`OnboardingTextAction` is plain icon/text content, not a transparent Material
button. Gesture, keyboard Enter/Space, and semantic activation share the same
guarded command; keyboard focus underlines the label. Its minimum touch target
and loading footprint remain stable without a painted button surface.

## Authored Layouts

The visual reference is commit `bbbc315`. Keep its price/chart Home, equal-width
Send/Receive/Swap pills, two-line asset rows and compact floating navigation.
Real values, loading, expiry, errors and unavailable operations must remain
truthful; historical mock quotes and obsolete assets are not a design contract.

- `AsterSplitCard`: one outlined squircle containing a main area and footer.
  Do not stack independently rounded halves.
- `AsterFormBody`: bottom-anchored actions with one scrolling form when space
  is constrained. The owner supplies SafeArea and horizontal padding. Do not
  put Expanded children or unconstrained scroll views inside its children.
- `AsterSheetHeader`: shared handle, left-aligned title and optional close.
- `Squircle`: clips children to the same boundary, paints outlines in front of
  filled children, and leaves shadows outside the clipping layer.
- Only the onboarding Welcome page exposes the retained blue mesh. Create and
  Import, including loading/error states, own opaque `ColorScheme.surface`
  Scaffolds and native page transitions. Recovery fields use
  `radii.recoveryWord`, `surfaceSubtle`, `borderSubtle`, and normal dark text;
  focus/cursor use primary blue. Do not reuse on-art text or glass here.
- Keypads use `radii.keypad`, not input/card radii. Numeric fields label their
  actual displayed unit, which is independent from the Bitcoin asset identity.
- `unwrappedTextWidth` measures the active font, locale and accessibility scale
  when a row must choose between horizontal and stacked layouts. Home commands
  remain equal-width pills; they stack only when the longest label cannot fit.
  Never squeeze accessibility text or let short values shift trailing edges.
- `WalletAmountEntry`: exact keypad-owned values use a stable-height horizontal
  viewport and visible scrollbar. Updates reveal the fractional tail; scrolling
  returns to the prefix. The whole amount is one accessible label. Never
  ellipsize, abbreviate or reduce text scaling to make an input fit.
- `AsterOptionRow.amountDetails` measures mixed-font monetary spans before
  reflowing; `details` keeps ordinary labels and identifiers in DM Sans.
- `statusForeground` is readable copy on light surfaces/status containers;
  success/warning/danger remain accent roles. Market uses white text on all three tiles, including orange Send and blue
  Receive, per the author's explicit October 16 correction. Preserve the existing
  artwork colors and the component's corresponding capsule treatment. MARKET-015
  records the measured contrast limitation; no contrast-pass claim applies to
  the first two tiles.

The original palette and bundled DM Sans/Public Sans families are unchanged.
Do not substitute a different screen composition while normalizing tokens.

## Visual Evidence

The test-only catalog renders production screens with isolated wallet, market
and camera fixtures. It is UI evidence, not proof of live payments. Its recovery
phrase is a public BIP39 test vector and must never hold funds.

```sh
fvm flutter test --dart-define=ASTER_CAPTURE_VISUALS=true test/visual_catalog_test.dart
fvm flutter drive --driver=test_driver/visual_catalog.dart \
  --target=integration_test/visual_catalog_test.dart -d <dedicated-ios-simulator-udid>
```

Host layouts export under `build/visual-restoration/host`; native PNGs export
under `build/visual-restoration/ios`. Use a dedicated simulator; never reuse
another task's device. The driver exports images before test-app cleanup.
The catalog includes all four payment rails, sheets, readiness/error/loading
variants, activity details, hidden balances, onboarding, settings and 2x text.
The import keyboard-inset scene simulates obstruction geometry; it does not
claim to capture the native keyboard. Native camera frames, real balances and
funded-payment proof are deliberately outside this fixture-only catalog.
The driver disables raw protocol logging to avoid writing the complete image
payload repeatedly. The PNG export and small result summary are retained.

## Toasts

Transient feedback goes through `context.toasts`. The Riverpod controller owns
a bounded, deduplicated FIFO queue; the single `ToastHost` owns animation and
visible-time lifecycle. The host pauses a toast's remaining display budget while
the application is not resumed, so queued outcomes cannot expire unseen in the
background. Do not create `OverlayEntry`, static toast globals, or feature
timers.

Accessible navigation disables automatic dismissal. Once assistive focus reaches
a message, that message remains until explicit dismissal, because speech
completion is not observable. Keyboard focus pauses the remaining budget;
leaving keyboard focus resumes it. Queue entries retain individual IDs so late
focus/timer callbacks cannot dismiss another message. Long messages receive a
bounded visual reading duration; this estimate is never a screen-reader timer.
Do not steal focus to announce a toast or move persistent errors into the queue.
The dismiss control and semantic dismiss action remain available; Escape also
dismisses the current message from route focus unless a descendant handles it.
Do not assume a route's closed Tab traversal reaches the app-root overlay.

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
Scrolling lists and details use `SafeArea(bottom: false)` and include the bottom
safe inset in their content padding. Their viewport reaches the bottom of the
screen; safe spacing appears only after the last item rather than as a fixed
blank bar. Bottom overlays such as floating navigation use persistent
bottom-system padding inside the scroll content. Send address and amount forms
use the same full-height viewport, with safe spacing passed to AsterFormBody
after its final action. The address viewport still resizes above the system
keyboard, and amount entry retains its custom keypad. Other bottom-anchored
forms keep their existing safe-area and keyboard protection without double
padding.

Home has no manual refresh command or pull-to-refresh gesture. Its top edge
clamps overscroll and suppresses Android leading stretch while the bottom
retains platform bounce. The visible,
foreground Home refreshes wallet balances on return and every 30 seconds.
Pull-to-refresh remains on Activity and Transaction details; details have no
app-bar reload command.

The initial phone release supports portrait-up only. Flutter requests this
before the first frame; iOS metadata and Android activity metadata declare the
same preference. Android 17 can override orientation requests on large displays
([platform policy](https://developer.android.com/about/versions/17/changes/ff-restrictions-ignored)).

## Accessibility

Interactive surfaces use Material controls (`InkWell`, `IconButton`, buttons)
without tap ink, or guarded plain actions with equivalent keyboard/focus
behavior and at least a 48-point target. Icon-only commands
have a tooltip or an equivalent explicit accessibility label. Loading and toast
changes are live regions. Inactive indexed screens are excluded from pointer
input and semantics.

When a labeled `Semantics(excludeSemantics: true)` replaces a control's inner
tree, it must expose the same guarded `onTap` as its Material control. Test
dispatch of the semantic action as well as pointer and keyboard input. Keep
tab wrapper types stable while changing their `excluding`/`ignoring` flags.
Generated recovery words retain two visual columns, but their grouped numbered
semantics explicitly traverse 1 through 12.

Receive keeps asset/rail in its title and real expiry visible, without repeating
the Bitcoin on-chain caption below the QR. At expiry, including foreground
resume, remove the QR and stale encoded text; retain context and regeneration.
Transaction details retain the record during explicit refresh and expose
progress plus failure/retry in place.
Activity summary cards show the total asset balance once, including their
loading and accessibility presentations.

Text must remain usable under platform text scaling. New fixed-height text
containers require compact and large-phone widget tests before acceptance.

Receive Share opens the platform sheet without changing tile labels, arrows or
layout. The real busy state still prevents overlapping actions; cancellation is
quiet and failures show feedback. Send recipient and amount titles identify the
asset. The amount card footer shows the rail and Max; Max fills the
exact available asset amount and stays disabled for fixed invoices or blocked
flows. Address appears below fees as one flowing paragraph: a 16-pixel label gap,
then the value, with continuation lines aligned to the row's leading edge. Validation, fee and payment
feedback uses guarded toasts rather than prose inside or below the card. Full
Bitcoin amounts that leave no room for fees are rejected before dispatch with a
warning; full USDT amounts are allowed because network fees use BTC. Missing or stale read
prerequisites recover silently with bounded attempts only on the same ready,
visible wallet; a changed fee requires review and another deliberate Send.

Final Send starts the real payment immediately and keeps its button loading for
at least two seconds before presenting an accepted receipt. This presentation
minimum runs alongside the payment; slower submissions add no artificial delay,
and failures end loading promptly. The screen retains its duplicate-send and
Back guards throughout the interval.

Accepted Send renders a terminal confirmation on its existing route: a double-size
token logo, exact accepted amount and Payment sent centered above a bottom Continue action.
There is no success toast or automatic Home navigation. Continue returns Home;
Back cannot reveal an already submitted form. Unknown or failed outcomes retain
their failure/reconciliation surface instead.

Bitcoin sends whose outputs all belong to the active wallet appear as Transfer
to self, with an unsigned reviewed amount when exact accepted metadata exists.
The network fee remains separate and the balance reflects the native owned coins.

## Shimmer

Shimmer is reserved for initial content loads and preserves final layout.
Refresh keeps existing content visible with refresh feedback. Pagination uses
inline progress. Reduced motion replaces shimmer with a stable solid treatment.
