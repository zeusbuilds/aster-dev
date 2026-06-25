# Design System Normalization Tracker

This tracker records the current design-system contract and the audits required
to keep feature UI normalized. The standard is that UI code uses semantic APIs
from `ThemeData`, `ColorScheme`, `TextTheme`, and Aster `ThemeExtension`s,
without leaking primitive colors, catch-all spacing values, ad hoc typography,
or local component metrics.

## Current Status

- Last audit: 2026-06-24
- Scope audited:
  - `lib/features/**/presentation/**`
  - `lib/shared/widgets/**`
  - `lib/shared/screens/**`
  - `lib/shared/theme/**`
  - `lib/core/bootstrap/**`
  - `lib/main.dart`
- Open design-system normalization issues: none known after the latest audit.

## Systems In Place

- [x] `AsterColors`: semantic app-only colors. Raw palette values are private in
  `_AsterPalette`; feature UI cannot access `white`, `black`, `blueBase`,
  `transparent`, or other primitives.
- [x] `ColorScheme`: Material colors and standard surface/content roles.
- [x] `AsterSpacing`: layout gaps, padding, screen padding, and safe-area
  helpers only.
- [x] `AsterIconography`: icon glyph sizes.
- [x] `AsterStrokes`: divider, border, focus, and hairline widths.
- [x] `AsterComponentMetrics`: component dimensions, ratios, fixed control
  geometry, sheet handles, bottom nav metrics, keypad metrics, chart height,
  flag/avatar sizes, selection indicators, brand mark size, and similar
  non-spacing measurements.
- [x] `AsterRadii`: small semantic radius scale with real fields for `card`,
  `button`, `input`, `badge`, `iconButton`, and `control`.
- [x] `AsterTypeRoles`: semantic text roles for app bars, buttons, rows,
  sections, amounts, assets, brand-art screens, addresses, keypad numbers,
  market tiles, scan controls, support/error labels, badges, toast titles, and
  toast messages.
- [x] `NumericText`, `AmountText`, and `NumericTextSpans`: Public Sans numeric
  handling without applying the numeric font to non-numeric labels or units.
- [x] `AsterStateLayers`: semantic interaction/state alpha values such as
  disabled, translucent surface, selected container, and primary overlay.
- [x] `AsterEffects`: authored visual effects such as brand glass, scan scrims,
  market tile treatment, art noise, and brand content opacity.
- [x] `AsterMotion`: reusable durations and curves for component motion and
  screen choreography.
- [x] `AsterGradients`: authored gradient recipes.
- [x] `AsterArt`: brand-art composition metrics and mesh/grid recipes.
- [x] `AsterShadows`: limited elevation decisions: `none`, `raised`, `sheet`,
  and `modal`.
- [x] `AssetDisplay`: presentation-layer asset color mapping. `AssetModel` no
  longer imports Flutter or reads theme data.
- [x] Light-only app theme. No fake `darkTheme` or `AppTheme.dark() => light()`
  path remains.
- [x] Reusable tap surfaces have explicit semantic roles where they behave as
  controls.
- [x] Compact buttons and scan controls preserve tokenized minimum touch
  targets.

## Policy

### Spacing

`AsterSpacing` is only for layout distance. Do not add component dimensions to
spacing, even if the number matches the spacing scale.

Use these systems instead:

- Icons: `context.icons`
- Strokes: `context.strokes`
- Component dimensions/ratios: `context.metrics`
- Radii: `context.radii`
- Art composition: `context.art`

### Typography

Feature UI should use `context.type` roles. Do not locally set
`fontWeight`, `fontSize`, `letterSpacing`, or raw `TextStyle` in product UI.
If a visual role is missing, add it to `AsterTypeRoles` and migrate call sites.

Use `NumericText` only for fully numeric strings. Use `AmountText` for mixed
values such as `0.000 BTC`, `7 sats/vbyte`, percentages with labels, or fiat
amounts with units.

### Colors

Feature UI should use:

- `context.colorScheme` for Material surface/content/control roles.
- `context.appColors` for app-specific semantic roles.
- `context.gradients` for authored reusable gradients.

Do not expose primitive palette names outside `color_tokens.dart`. Do not use
raw `Color(0x...)`, `Colors.*`, or `AsterColors.*` primitives in feature UI.

### State, Effects, And Opacity

Do not create opacity ramps such as `opacity10`, `opacity20`, or `opacity30`.
Add semantic alpha roles only when the value expresses a reusable product state
or visual treatment.

- Use `context.stateLayers` for interaction states.
- Use `context.effects` for authored visual effects.
- Painter math may keep local computed opacity when it is part of a drawing
  algorithm rather than reusable UI language.

### Motion

Reusable durations and curves belong in `AsterMotion`. Prefer choreography
phase names, not generic timing ramps. Local painter interpolation math may stay
inside the painter.

## Allowed Exceptions

- Generated files such as `*.g.dart` and ObjectBox generated metadata.
- Data, repository, service, provider, validator, and network layers, unless
  they expose presentation colors or metrics.
- Direct `Color(0x...)` inside token/theme implementation files.
- Direct `BoxShadow` inside `AsterShadows`.
- Local geometry in custom painters when it defines drawing math rather than
  reusable product geometry.

## Verification Checklist

- [x] `fvm dart format` on changed files.
- [x] `fvm flutter analyze --no-fatal-warnings --no-fatal-infos`.
- [x] `fvm flutter test` after code changes that affect widget behavior.
- [x] Non-opacity design-token audits.
- [x] Primitive color and model-presentation leakage audits.
- [x] Fake dark-theme audit.

## Audit Commands

```sh
rg -n "context\\.colors|context\\.radius|spacing\\.spacing\\d+|radius\\.radius\\d+|brand[0-9]|fill[0-9]|text[0-9]|ColorTokens|SpacingTokens|RadiusTokens|ShadowTokens|TypographyTokens" lib

rg -n "spacing\\.(icon|bottomNav|sheet|keypad|navOffset|heroInset|chartHeight|dividerThickness|hairline|focusRing|collapsedMessageHeight)" lib --glob '*.dart'

rg -n "fontWeight:\\s*FontWeight" lib/features lib/shared/widgets lib/shared/screens --glob '*.dart'

rg -n "context\\.textTheme|final textTheme = context\\.textTheme|textTheme\\." lib/features lib/shared/widgets lib/shared/screens --glob '*.dart'

rg -n "size:\\s*(context\\.)?spacing\\.|CircleFlag\\([^\\n]*size:\\s*(context\\.)?spacing\\." lib/features lib/shared/widgets lib/shared/screens --glob '*.dart'

rg -n "\\bColors\\.|\\bColor\\(0x|Color\\.fromARGB|Color\\.fromRGBO|asset\\.themedColor|widget\\.asset\\.themedColor|themedColor\\(" lib/features lib/shared/widgets lib/shared/screens lib/core/bootstrap --glob '*.dart'

rg -n "AsterColors\\.(blue|white|black|transparent|surface|ink|mesh|homeGradient|splashGradient)|\\.homeGradient|\\.splashGradient|\\.mesh[A-Z]" lib test --glob '*.dart'

rg -n "darkTheme|AppTheme\\.dark|dark\\(\\)" lib --glob '*.dart'
```

Expected result: no matches in product UI. Matches inside token/theme
implementation files are allowed only when they are the source-of-truth
definitions.
