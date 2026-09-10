# Design System Contract

This document defines how Aster presentation code consumes the design system.
The authoritative release status and finding history live in
`docs/PRODUCTION_REFACTOR_TRACKER.md`; this guide must not claim that a partial
audit is a repository-wide clean bill of health.

## Runtime Ownership

`ThemeData` is the runtime contract:

- `ColorScheme` owns Material surface, content, primary, and error roles.
- `TextTheme` owns the Material 3 type scale.
- Aster `ThemeExtension`s own product-specific semantic decisions.
- `ThemeContext` fails fast when a required extension is missing. Feature code
  must never construct fallback token objects.

The app is intentionally light-only. Do not add a fake dark theme that aliases
the light theme.

## Systems

- `AsterColors`: app-specific semantic colors; palette primitives stay private.
- `AsterSpacing`: layout distance only.
- `AsterRadii`: squircle radii and named component roles.
- `AsterIconography`: glyph sizes.
- `AsterStrokes`: hairline, divider, border, and focus widths.
- `AsterComponentMetrics`: touch targets and fixed component geometry.
- `AsterTypeRoles`: complete product typography roles.
- `AsterStateLayers`: disabled, hover/focus overlays, and visibility/surface
  treatment. Pressed ink is prohibited; `interactionOverlay` owns that policy.
- `AsterEffects`: named visual-effect alpha decisions.
- `AsterMotion`: authored durations, curves, and choreography phases.
- `AsterGradients`: reusable gradient recipes.
- `AsterArt`: branded composition and custom-painter recipes.
- `AsterShadows`: only `none`, `raised`, `sheet`, and `modal`.

## Colors

The current palette is product-approved and must not change during structural
normalization. Feature UI uses `context.colorScheme` or semantic
`context.appColors` roles. Raw `Color(0x...)`, `Colors.*`, palette names, and
generic opacity ramps are forbidden outside theme/token implementations.

An opacity is a token only when it represents a reusable state or authored
effect. Mathematical interpolation inside a painter may remain local.

When an opacity widget requires explicit endpoints, use
`context.stateLayers.visible` and `context.stateLayers.hidden`; never introduce
an `opacity10`-style ramp.

## Typography

DM Sans is the UI font. Public Sans is used only for numeric spans. Feature UI
uses `context.type`; it does not choose local sizes, weights, or letter spacing.

- `NumericText` is for numeric content.
- `AmountText` is for mixed strings such as `0.001 BTC` or `7 sats/vbyte`.
- Currency symbols, percent signs, units, labels, asset names, and addresses
  remain DM Sans.

Add a semantic type role when a repeatable product role is genuinely missing.
Do not create a type token just to hide a one-off override.

## Geometry

Spacing is not a catch-all number bucket. Use:

- `context.spacing` for gaps and layout padding.
- `context.icons` for icon size.
- `context.strokes` for line width.
- `context.metrics` for component dimensions and ratios.
- `context.radii` for squircle shape roles.
- `context.art` for authored visual composition.

Cards, tiles, fields, sheets, and rounded surfaces use
`RoundedSuperellipseBorder` or `Squircle`. Exact capsule controls use
`StadiumBorder` or `AsterPill`. A circle is reserved for genuinely circular
content. `BorderRadius` values are valid inputs to a superellipse; they do not
by themselves make the rendered shape a rounded rectangle.

## Insets

Window insets are not spacing tokens. Use `SafeArea` for ordinary screen roots
and bottom sheets. Use `context.windowInsets` only when full-bleed composition
requires an explicit coordinate space:

- `topSafe` / `bottomSafe`: currently unobscured `MediaQuery.padding`.
- `topSystem` / `bottomSystem`: persistent `viewPadding` hardware insets.
- `keyboard`: `viewInsets.bottom` obstruction.

Do not combine `SafeArea` with manual padding for the same edge.

## Motion

Read authored timing from `context.motion` and resolve it through
`context.motionPolicy`. Reduced motion renders state transitions at zero
duration and stops decorative loops at a stable frame. Hidden tab content must
be under `TickerMode(enabled: false)` and must not receive interaction or
semantics.

## Verification

`dart run tool/verify_design_system.dart` parses every repository-owned screen,
page, and widget. It rejects direct `TextTheme`/`TextStyle` decisions, raw
colors and alpha, raw reusable geometry, gradients, shadows, rounded-rectangle
surfaces, and legacy token access. Positive and adversarial fixtures protect
the validator itself, and `make verify` runs it locally, in pre-commit, and in
CI.

Theme/token implementations are intentional owners. Local custom-painter
coordinate math and non-visual deadline arithmetic are reviewed as code rather
than misclassified as reusable design decisions. Repository-wide feature
completion, platform visual QA, accessibility traversal, and physical haptic
tuning remain governed by the production tracker.

These searches are supplemental diagnostics, not the enforcement boundary:

```sh
rg -n "context\\.colors|context\\.radius|spacing\\.spacing[0-9]+|radius\\.radius[0-9]+" lib
rg -n "fontSize:|fontWeight:|letterSpacing:" lib/features lib/shared/widgets
rg -n "\\bColors\\.|\\bColor\\(0x|RoundedRectangleBorder|OutlineInputBorder|ClipRRect" lib/features lib/shared/widgets
rg -n "package:haptic_feedback|Haptics\\." lib --glob '*.dart'
rg -n "MediaQuery\\.(paddingOf|viewPaddingOf|viewInsetsOf)" lib/features --glob '*.dart'
```

Expected matches still require review: theme definitions, custom-painter math,
and the platform haptic adapter are intentional owners.
