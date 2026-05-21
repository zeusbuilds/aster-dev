# Design System Usage Guide

Aster uses Flutter `ThemeData` as the runtime design contract.

- Material surfaces, content colors, controls, and text styles come from `ColorScheme` and `TextTheme`.
- App-specific product decisions come from compact `ThemeExtension`s.
- Feature UI should use semantic roles, not primitive token names or raw hex values.

## Access

```dart
final scheme = context.colorScheme;
final app = context.appColors;
final spacing = context.spacing;
final radii = context.radii;
final shadows = context.shadows;
final effects = context.effects;
final motion = context.motion;
final metrics = context.metrics;
```

## Colors

Use Material roles for ordinary UI:

```dart
Container(
  color: context.colorScheme.surface,
  child: Text(
    'Wallet',
    style: context.textTheme.titleMedium?.copyWith(
      color: context.colorScheme.onSurface,
    ),
  ),
);
```

Use `AsterColors` roles for app-only meaning:

```dart
Text(
  '+2.4%',
  style: context.textTheme.labelMedium?.copyWith(
    color: context.appColors.chartPositive,
  ),
);
```

Do not use primitive or art-specific names for ordinary product UI:

```dart
// Avoid
context.appColors.brandArtMain;
AsterColors.blueBase;

// Prefer
context.colorScheme.primary;
context.appColors.chartPositive;
```

Art-only roles such as `brandArtMain`, mesh colors, scan overlay colors, and
market tile colors should stay inside the widgets that render that visual
system.

## Typography

Text uses DM Sans through `TextTheme`. Numbers use Public Sans by calling `toNumeric(context)`.

```dart
Text(
  amount,
  style: context.textTheme.displaySmall?.toNumeric(context),
);
```

Prefer Material text roles:

- `display*` for large balances and hero prices.
- `headline*` for page-level titles.
- `title*` for cards and sections.
- `body*` for normal copy.
- `label*` for controls, nav, buttons, and metadata.

Avoid feature-level `fontSize` unless the UI is intentionally bespoke.

## Spacing

Use the named scale:

```dart
EdgeInsets.symmetric(
  horizontal: context.spacing.screenPadding,
  vertical: context.spacing.lg,
);
```

Use semantic helpers for layout:

- `screenPadding`
- `sectionGap`
- `controlGap`
- `topSafe(context)`
- `bottomSafe(context)`

Do not add `spacing20`, `spacing46`, or other every-value APIs.

## Radius

Use component decisions:

```dart
BorderRadius.circular(context.radii.card);
BorderRadius.circular(context.radii.input);
BorderRadius.circular(context.radii.pill);
```

The radius scale is intentionally small. Real design systems expose decisions, not every possible pixel value.

## Shadows

Prefer surfaces and borders. Use shadows only when elevation is meaningful:

```dart
BoxDecoration(
  color: context.appColors.surfaceRaised,
  borderRadius: BorderRadius.circular(context.radii.card),
  boxShadow: context.shadows.raised,
);
```

Available shadows are `none`, `raised`, `sheet`, and `modal`.

## Effects

Use `context.effects` for reusable visual treatments that are not colors:

```dart
Opacity(
  opacity: context.effects.disabledOpacity,
  child: child,
);
```

Effects include disabled states, translucent surfaces, overlay opacity, market
tile treatments, scan scrims, and brand-art glass/noise opacity. Do not create
new `withValues(alpha: 0.12)` decisions in feature code. If an opacity has
product meaning and appears more than once, add a semantic effect.

Painter math may keep local computed opacity when the opacity is part of the
drawing algorithm rather than a reusable design decision.

## Motion

Use `context.motion` for component timing, interaction feedback, and screen
choreography:

```dart
AnimatedContainer(
  duration: context.motion.selectionTransitionDuration,
  curve: context.motion.fastEase,
  child: child,
);
```

Available motion roles cover button press feedback, selection commits, bottom
nav movement, toast entrance/exit, skeleton/loading cycles, startup reveal,
splash reveal timing, chart loading/transition timing, and the swap screen
choreography. Do not add raw `Duration(milliseconds: 300)` or
`Curves.easeOutCubic` to product UI. Custom painters may keep local geometry,
phase offsets, and interpolation math, but reusable timing and curves should
come from `context.motion` or `AsterMotion`.

Keep choreography tokenized as semantic phases, not as generic ramps. Prefer
names like `swapKeyboardTransitionDuration` over `duration300`.

## Component Metrics

Use `context.metrics` for component measurements that are not layout spacing:

```dart
SizedBox(height: context.metrics.buttonHeight);
```

Metrics include button heights, border widths, slider radii, chart/art ratios,
scan frame ratios, market texture sizing, and swap animation distance. Use
`context.spacing` for layout gaps and padding; use `context.metrics` when the
number belongs to a component's physical shape or behavior.

## Migration Examples

```dart
// Before
color: context.colors.fill1;
borderRadius: BorderRadius.circular(context.radius.radius24);
padding: EdgeInsets.all(context.spacing.spacing20);

// After
color: context.colorScheme.surface;
borderRadius: BorderRadius.circular(context.radii.card);
padding: EdgeInsets.all(context.spacing.screenPadding);
```

```dart
// Before
color: context.colors.brand6;

// After
color: context.colorScheme.primary;
```

Keep primitives inside the theme implementation. Product screens should read like intent.
