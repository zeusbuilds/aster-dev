# Design System Normalization Tracker

This tracker records the remaining UI normalization work after the design-system
refactor. The goal is that feature UI uses semantic APIs from `ThemeData`,
`ColorScheme`, `TextTheme`, and Aster `ThemeExtension`s, instead of leaking raw
primitive colors, dimensions, opacity values, radii, shadows, or typography.

## Status

- Last audit: 2026-05-21
- Scope audited:
  - `lib/features/**/presentation/**`
  - `lib/shared/widgets/**`
  - `lib/shared/screens/**`
  - `lib/shared/routing/**`
  - `lib/core/bootstrap/**`
- Clean:
  - No `context.colors` usage.
  - No old `brand6`, `fill1`, `text1` style token usage.
  - No old `spacing24` or `radius24` style token usage.
  - No `Colors.*` usage in audited UI code.
  - No raw `Color(0x...)` usage in audited feature UI.
  - No `asset.color` or `Color(asset.color)` usage.
  - No direct `Theme.of(context)` usage in audited UI code.
  - No direct `fontSize`, `TextStyle`, positive `letterSpacing`, or raw text
    height usage in audited UI code.
  - Non-opacity primitive color, component metric, and component motion skips
    have been normalized.
  - Reusable opacity/effect semantics use `AsterEffects`.
  - Reusable component timing and screen choreography use `AsterMotion`.
  - Theme-level component measurements use `AsterComponentMetrics`.
  - Remaining dynamic opacity values are painter or animation math.

## Token Policy

### Opacity

Do not add a numeric opacity ramp such as `opacity10`, `opacity20`, `opacity30`.
That recreates the primitive-token problem in another form.

Add semantic opacity/effect tokens only when the value expresses a repeatable UI
decision:

- `disabledOpacity`
- `pressedScale`
- `brandContentStrong`
- `brandContentMuted`
- `brandGlassSurface`
- `brandGlassBorder`
- `scanScrimStrong`
- `scanScrimMedium`
- `scanControlSurface`
- `marketTileShadowOpacity`
- `selectedContainerOpacity`

It is acceptable for custom painters and one-off art algorithms to keep local
opacity constants when the number is part of drawing math rather than reusable
UI language. Examples: candle interpolation opacity and loader phase opacity.

### Other Token Categories

- Added: `AsterEffects` for reusable blur, overlay, glass, and state opacity
  decisions.
- Added: `AsterMotion` for reusable animation durations, curves, and pressed-scale
  behavior for components and screen choreography. Tokenize shared component
  motion, selection handoff delays, loading cycles, and multi-step product
  choreography. Splash and chart timing/curves are token-backed; their geometry
  and painter math remain local.
- Added: `AsterComponentMetrics` for sizes and layout ratios that are not general
  spacing, such as button heights, scan frame ratio, market artwork size, and
  grid tile aspect ratios. Theme-only control measurements such as border
  widths and slider radii also live here.
- Keep `AsterSpacing` for layout distance, not every component dimension.
- Keep `AsterColors` semantic. Do not expose `white`, `black`, or
  `transparent` to feature UI unless the code is a low-level shared primitive or
  unavoidable platform/system styling.

## P0: Contract Decisions

- [x] Add `AsterEffects` as a `ThemeExtension`.
  - Include semantic alpha/effect values for brand-on-art content, glass
    surfaces, selected containers, scan overlays, and disabled state.
  - Add `context.effects` in `theme_context.dart`.

- [x] Add `AsterMotion` as a `ThemeExtension`.
  - Include button press duration, selection handoff delay, toast lifecycle,
    nav indicator duration, loading/skeleton cycles, startup reveal delay, swap
    choreography phases, splash reveal timing, chart transition timing, default
    ease curves, and pressed scale.
  - Add `context.motion` in `theme_context.dart`.

- [x] Add component metrics without bloating the base spacing scale.
  - Either extend `AsterSpacing` with named component values or add
    `AsterComponentMetrics`.
  - Required values: button heights, scan frame ratio, home hero ratio,
    onboarding icon grid gap, recovery word grid aspect ratio, blur sigma,
    market texture size, market badge dot size.
  - Added theme control metrics for border widths and slider radii.
  - Added choreography distance for the swap details reveal.

- [x] Define the primitive-color rule.
  - Feature UI should use `context.colorScheme` and `context.appColors`.
  - Shared low-level primitives may use `AsterColors.transparent`.
  - Brand/art screens should use semantic names like `onBrandArt`,
    `onBrandArtMuted`, `brandGlassSurface`, `scanOverlayBase`, and not
    `AsterColors.white` or `AsterColors.black` directly.

## P1: Primitive Color Leakage

- [x] Replace direct white usage in home art/header.
  - `lib/features/home/presentation/widgets/home_header.dart`
    - logo color filter
    - wallet text color
    - wallet icon color
  - `lib/features/home/presentation/widgets/price_card.dart`
    - title color
    - price color
    - chart foreground color references
  - Suggested tokens:
    - `appColors.onBrandArt`
    - `appColors.onBrandArtMuted`
    - `effects.brandContentMutedOpacity`

- [x] Replace direct black/transparent usage in mesh background.
  - `lib/features/home/presentation/widgets/mesh_gradient_background.dart`
    - backdrop transparent filler
    - noise overlay color and opacity
  - Suggested tokens:
    - `appColors.artBackdropClear`
    - `appColors.artNoiseTint`
    - `effects.artNoiseOpacity`

- [x] Replace direct white usage in onboarding welcome/import art.
  - `lib/features/onboarding/presentation/screens/onboarding_welcome_screen.dart`
  - `lib/features/onboarding/presentation/screens/onboarding_import_wallet_screen.dart`
  - `lib/features/onboarding/presentation/widgets/onboarding_welcome_header.dart`
  - `lib/features/onboarding/presentation/widgets/onboarding_import_wallet_word_grid.dart`
  - `lib/features/onboarding/presentation/widgets/onboarding_import_wallet_word_page.dart`
  - Suggested tokens:
    - `appColors.onBrandArt`
    - `appColors.onBrandArtMuted`
    - `appColors.brandGlassSurface`
    - `appColors.brandGlassBorder`

- [x] Replace direct white/black usage in scan UI.
  - `lib/features/scan/presentation/widgets/scan_background.dart`
  - `lib/features/scan/presentation/widgets/scan_camera.dart`
  - `lib/features/scan/presentation/widgets/scan_control_button.dart`
  - `lib/features/scan/presentation/widgets/scan_enter_address_button.dart`
  - `lib/features/scan/presentation/widgets/scan_frame.dart`
  - `lib/features/scan/presentation/widgets/scan_wallet_header.dart`
  - `lib/features/scan/presentation/screens/scan_screen.dart`
  - Suggested tokens:
    - `appColors.scanOverlayBase`
    - `appColors.scanOverlayStrong`
    - `appColors.scanOverlayMedium`
    - `appColors.scanControlSurface`
    - `appColors.onScan`
    - `appColors.onScanMuted`

- [x] Replace direct white/opacity usage in market tiles.
  - `lib/features/market/presentation/widgets/market_tile.dart`
  - Suggested tokens:
    - `appColors.onMarketTile`
    - `appColors.onMarketTileMuted`
    - `appColors.marketPillSurface`
    - `appColors.marketPillDot`

- [x] Replace direct transparent usage in feature widgets where it is not a
  shared primitive.
  - `lib/features/home/presentation/screens/home_screen.dart`
  - `lib/features/scan/presentation/screens/scan_screen.dart`
  - `lib/features/swap/presentation/widgets/asset_selector_sheet.dart`
  - `lib/features/swap/presentation/widgets/swap_pair.dart`
  - Suggested approach:
    - Use `AsterColors.transparent` only for platform/system overlay cases.
    - Use `appColors.transparentSurface` or component-specific color when it is
      part of UI styling.

## P1: Raw Layout Ratios

- [x] Use the home hero ratio token.
  - `lib/features/home/presentation/screens/home_screen.dart`
  - Replaced raw `0.4` with `metrics.homeHeroHeightFactor`.

- [x] Use the scan frame ratio token.
  - `lib/features/scan/presentation/widgets/scan_frame.dart`
  - Replaced raw `0.7` with `metrics.scanFrameSizeFactor`.

- [x] Decide whether these ratios belong in `AsterSpacing` or a new
  `AsterComponentMetrics`.
  - Moved ratios to `AsterComponentMetrics`, because they are not spacing.

## P2: Button System

- [x] Remove the unresolved button TODO.
  - `lib/shared/widgets/custom_button.dart`
  - Current TODO: "fix button variant colors and also match grid loader variant
    colors".

- [x] Tokenize button component metrics.
  - `lib/shared/widgets/custom_button.dart`
  - Current local values:
    - normal height `48`
    - compact height `40`
    - secondary border width `1`
    - pressed scale `0.95`
    - press duration `100ms`
  - Suggested tokens:
    - `componentMetrics.buttonHeight`
    - `componentMetrics.compactButtonHeight`
    - `spacing.dividerThickness`
    - `effects.disabledOpacity`
    - `motion.buttonPressedScale`
    - `motion.buttonPressDuration`

- [x] Align loading indicator color with button variant.
  - `lib/shared/widgets/custom_button.dart`
  - Ensure `GridLoader` receives semantic color style based on foreground color,
    not an internal default that happens to work.

## P2: Motion And Choreography

- [x] Move shared toast lifecycle to motion tokens.
  - `lib/shared/widgets/custom_toast.dart`
  - Uses `motion.toastVisibleDuration`, `motion.toastTransitionDuration`, and
    `motion.toastCurve`.

- [x] Move shared loading cycles to motion tokens.
  - `lib/shared/widgets/app_skeletonizer.dart`
  - `lib/shared/widgets/grid_loader.dart`
  - Keeps loader drawing phase math local, but cycle duration comes from
    `motion.loadingCycleDuration` / `motion.skeletonShimmerDuration`.

- [x] Move selection handoff delays to motion tokens.
  - `lib/features/swap/presentation/widgets/asset_selector_sheet.dart`
  - `lib/features/wallet/presentation/pages/wallet_selection_screen.dart`
  - Uses `motion.selectionCommitDelay` so tap feedback and sheet/pop handoff
    stay coordinated.

- [x] Move swap screen choreography to semantic motion tokens.
  - `lib/features/swap/presentation/screens/swap_screen.dart`
  - Uses named keyboard, message, detail reveal, detail dismiss, cancel stagger,
    fade, and choreography curve tokens.
  - Detail row travel distance lives in `AsterComponentMetrics`.

- [x] Move bootstrap reveal delay to motion tokens.
  - `lib/core/bootstrap/app_loader.dart`
  - Uses `motion.bootstrapRevealDelay`.

- [x] Move Material theme effect/metric constants to tokens.
  - `lib/shared/theme/app_theme.dart`
  - Slider overlay opacity uses `effects.primaryOverlayOpacity`.
  - Input/checkbox border widths and slider radii use `AsterComponentMetrics`.

- [x] Move splash reveal timing and curves to motion tokens.
  - `lib/shared/screens/animated_splash_screen.dart`
  - Uses `AsterMotion.splashRevealDuration`, `choreographyCurve`,
    `splashSplitCurve`, and `splashRevealMoveCurve`.
  - Keeps logo/path geometry and timeline offsets local to the art component.

- [x] Move chart loading/transition timing and curve to motion tokens.
  - `lib/features/home/presentation/widgets/candle_chart.dart`
  - Uses chart loading, transition, pause, settle-delay, and transition-curve
    tokens.
  - Keeps candle count, wave math, and price interpolation local to the chart.

## P2: Brand Glass And Onboarding Art

- [x] Tokenize onboarding icon grid metrics.
  - `lib/features/onboarding/presentation/widgets/onboarding_welcome_icon_grid.dart`
  - Current local values:
    - rows `4`
    - columns `7`
    - grid gap `6`
    - blur sigma `14`
    - opacity matrix values
  - Recommendation:
    - Keep rows/columns local because they define the art composition.
    - Move grid gap and blur sigma to component metrics/effects.
    - Repeated glass opacity values moved to `AsterEffects`.

- [x] Tokenize recovery phrase grid aspect ratio and glass opacity values.
  - `lib/features/onboarding/presentation/widgets/onboarding_import_wallet_word_grid.dart`
  - Current local value:
    - `childAspectRatio: 4.5`
  - Current repeated alpha values:
    - surface alpha `0.15`
    - border alpha `0.1`
    - muted text alpha `0.7`
  - Alpha values moved to `AsterEffects`.

- [x] Tokenize word page glass opacity values.
  - `lib/features/onboarding/presentation/widgets/onboarding_import_wallet_word_page.dart`
  - Current repeated alpha values:
    - surface alpha `0.15`
    - border alpha `0.1`
    - muted text alpha `0.75`

## P2: Market Tile Styling

- [x] Move market tile shadow alpha to an effect token.
  - `lib/features/market/presentation/screens/market_screen.dart`
  - Current repeated alpha:
    - `0.16`

- [x] Move market tile foreground alpha values to semantic tokens.
  - `lib/features/market/presentation/widgets/market_tile.dart`
  - Current repeated alpha values:
    - text alpha `0.75`
    - pill surface alpha `0.15`
    - dot alpha `0.5`

- [x] Tokenize market texture sizing.
  - `lib/features/market/presentation/widgets/market_tile.dart`
  - Current value:
    - `spacing.giant * 2`
  - This is better as `componentMetrics.marketTextureSize`.

## P2: Scan Surface Styling

- [x] Move scan overlay gradient colors/effects to semantic tokens.
  - `lib/features/scan/presentation/widgets/scan_background.dart`
  - Current values:
    - black
    - black at `0.75`
    - black at `0.65`

- [x] Move scan control surface color to semantic color.
  - `lib/features/scan/presentation/widgets/scan_control_button.dart`
  - Current value:
    - black

- [x] Move scan frame border/content colors to semantic colors.
  - `lib/features/scan/presentation/widgets/scan_frame.dart`
  - Current values:
    - white frame border
    - black at `0.4` control tray
    - white icons/text

- [x] Move scan enter-address color to semantic muted scan text.
  - `lib/features/scan/presentation/widgets/scan_enter_address_button.dart`
  - Current value:
    - white at `0.75`

- [x] Move scan wallet avatar opacity to semantic glass token.
  - `lib/features/scan/presentation/widgets/scan_wallet_header.dart`
  - Current value:
    - surface at `0.25`

## P3: Painter And Art Constants

These are lower priority because they are drawing algorithms, not regular UI
composition. They should not be forced into general spacing/color tokens. Move
them only if they represent app-wide visual language.

- [x] Review splash animation constants.
  - `lib/shared/screens/animated_splash_screen.dart`
  - Current local values:
    - animation duration and interval timings
    - logo width
    - line height values
    - handoff threshold
  - Recommendation:
    - Move duration/curve values to `AsterMotion` only if splash motion should
      be governed by the system.
    - Keep path geometry local.
  - Decision: splash timing and curves are now token-backed; path geometry and
    timeline offsets remain local because they define the art composition. Base
    colors come from semantic app colors.

- [x] Review `GridLoader` animation constants.
  - `lib/shared/widgets/grid_loader.dart`
  - Current local values:
    - cycle duration
    - row/column count
    - opacity phase values
    - virtual border lengths
  - Recommendation:
    - Move cycle duration to `AsterMotion`.
    - Keep drawing path math local.
  - Decision: keep loader drawing and phase math local. Button usage now passes
    the semantic foreground color.

- [x] Review candle chart constants.
  - `lib/features/home/presentation/widgets/candle_chart.dart`
  - Current local values:
    - candle count
    - animation durations
    - opacity and height amplitude values
    - stroke widths
  - Recommendation:
    - Keep chart math local unless reused by another chart.
    - Move chart height and surface colors to existing tokens, already mostly
      done.
  - Decision: chart timing and transition curve are now token-backed; candle
    count, wave math, and price interpolation remain local. Base chart
    foreground comes from semantic app colors.

- [x] Review price card noise painter constants.
  - `lib/features/home/presentation/widgets/price_card.dart`
  - Current local values:
    - grid stroke alpha calculation
    - grid spacing loop value from painter inputs
  - Recommendation:
    - Keep painter math local.
    - Ensure base colors come from semantic tokens.
  - Decision: keep painter math local.

- [x] Review mesh background blur/noise opacity constants.
  - `lib/features/home/presentation/widgets/mesh_gradient_background.dart`
  - Current local values:
    - blur sigma `20`
    - noise opacity `0.05`
    - black tint alpha `0.5`
  - Recommendation:
    - Move blur/noise alpha to `AsterEffects`.
  - Decision: move noise opacity/tint opacity to `AsterEffects`; keep blur
    sigma in the local art component for now.

## P3: Allowed Exceptions To Preserve

- Generated files:
  - `*.g.dart`
  - ObjectBox generated metadata
  - Generated `*.g.dart` files are excluded from analyzer linting; compile/build
    still covers them.
- Routing constants and route names are not design-system concerns.
- Data models, repositories, services, providers, validators, and network code
  are out of scope unless they expose colors or UI metrics.
- Direct `Divider` is allowed only inside `AsterDivider`.
- Direct `BoxShadow` is allowed only inside `AsterShadows`.
- Direct `Color(0x...)` is allowed inside token/theme implementation files:
  - `lib/shared/theme/app_theme.dart`
  - `lib/shared/theme/tokens/color_tokens.dart`
  - `lib/shared/theme/tokens/shadow_tokens.dart`

## Verification Checklist

- [x] Run `fvm dart format lib`.
- [x] Run `fvm flutter analyze --no-fatal-warnings --no-fatal-infos`.
- [x] Run `fvm flutter test`.
- [x] Rebuild and run iOS simulator.
- [x] Re-run non-opacity audits.
- [x] Re-run opacity/effect audit.

```sh
rg -n "context\\.colors|context\\.radius|spacing\\.spacing\\d+|radius\\.radius\\d+|brand[0-9]|fill[0-9]|text[0-9]|ColorTokens|SpacingTokens|RadiusTokens|ShadowTokens|TypographyTokens" lib
rg -n "\\bColors\\.|\\bColor\\(0x|Color\\.fromARGB|Color\\.fromRGBO|Color\\(asset\\.color|asset\\.color|widget\\.asset\\.color" lib/features lib/shared/widgets lib/shared/screens lib/core/bootstrap lib/shared/routing
rg -n "fontSize:\\s*[0-9]|TextStyle\\(|letterSpacing:\\s*[-0-9]|height:\\s*[0-9]\\.?[0-9]*|Theme\\.of\\(" lib/features lib/shared/widgets lib/shared/screens lib/core/bootstrap lib/shared/routing
rg -n "AsterColors\\.(white|black|transparent|surface)|withValues\\(alpha:\\s*[0-9]|opacity:\\s*[0-9]|mainAxisSpacing:\\s*[0-9]|crossAxisSpacing:\\s*[0-9]|childAspectRatio:\\s*[0-9]|MediaQuery\\.of\\(context\\)\\.size\\.(width|height) \\* [0-9]" lib/features lib/shared/widgets lib/shared/screens lib/core/bootstrap lib/shared/routing
```
