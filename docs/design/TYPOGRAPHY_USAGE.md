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

Do not use old primitive names in feature code:

```dart
// Avoid
context.appColors.brandArtMain;
context.spacing.xxl; // Only use when it is truly a component gap.

// Prefer
context.colorScheme.primary;
context.spacing.screenPadding;
```

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
