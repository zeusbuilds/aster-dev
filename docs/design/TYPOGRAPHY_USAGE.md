# Design System Usage Guide

UTEXO uses Flutter `ThemeData` as the runtime design contract. Feature UI should
read like product intent: Material roles for standard Flutter surfaces, and
the deliberately named `Aster*` semantic extensions for app-specific decisions.

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
final icons = context.icons;
final strokes = context.strokes;
final state = context.stateLayers;
final gradients = context.gradients;
final art = context.art;
final type = context.type;
```

## Colors

Use `ColorScheme` for Material meaning:

```dart
Container(
  color: context.colorScheme.surface,
  child: Text('Wallet', style: context.type.title),
);
```

Use `AsterColors` only for app-specific meaning:

```dart
AmountText(
  '+2.4%',
  style: context.type.rowValue.copyWith(
    color: context.appColors.chartPositive,
  ),
);
```

Primitive colors are private to the theme implementation. Do not expose or use
names like `blueBase`, `white`, `black`, `transparent`, `fill1`, or `brand6` in
feature UI. Brand-art colors such as `brandArtMain` belong only in widgets that
render that art system.

## Typography

Material `TextTheme` defines the scale. `AsterTypeRoles` defines product roles
and emphasis so widgets do not locally choose weights.

```dart
Text('Recent activity', style: context.type.sectionTitle);
Text('Recipient address', style: context.type.addressLabel);
Text(versionLabel, style: context.type.versionLabel);
```

Use `NumericText` for numbers and ordinary numeric metadata. Use `AmountText`
only for monetary values where surrounding currency symbols, asset labels, or
units must remain DM Sans:

```dart
NumericText('7 sats/vbyte', style: context.type.rowValue);
AmountText('0.001 BTC', style: context.type.amountLarge);
```

Avoid feature-level `fontSize`, `fontWeight`, `letterSpacing`, and raw
`TextStyle` creation. Add or tune a semantic type role when the product needs a
repeatable typographic decision.

Common support roles include `toastMessage`, `supportingMeta`, `errorMessage`,
`statusMessage`, `versionLabel`, `scanCta`, and `scanWalletId`. Use
`statusMessage` for neutral failure, unavailable, and empty-state body copy;
use the more specific roles when their semantic emphasis differs. Never reach
back into `context.textTheme` from feature UI.

## Spacing

`AsterSpacing` is only layout distance: gaps and layout padding. Window insets
belong to `SafeArea` and `context.windowInsets`, not the spacing scale.

```dart
Padding(
  padding: EdgeInsets.symmetric(
    horizontal: context.spacing.screenPadding,
    vertical: context.spacing.lg,
  ),
  child: child,
);
```

Do not put icon sizes, button heights, stroke widths, chart heights, sheet
handles, or nav dimensions in spacing.

## Geometry

Use the dedicated token family for the kind of geometry being expressed:

```dart
Icon(icon, size: context.icons.md);
SizedBox(height: context.metrics.buttonHeight);
Divider(thickness: context.strokes.divider);
Squircle(borderRadius: context.radii.card, child: child);
```

- `context.icons`: icon glyph sizes.
- `context.strokes`: divider, border, focus, and hairline widths.
- `context.metrics`: component dimensions, ratios, and fixed control geometry.
- `context.radii`: corner decisions.
- `context.spacing`: layout gaps and padding only.

Radius roles name components, not a generic size ramp: `card`, `sheet`,
`button`, `input`, `badge`, `checkbox`, `snackbar`, and
`floatingActionButton`. Add another role only when a repeated component shape
cannot truthfully use one of these decisions.

Examples of component metrics include flag sizes, wallet avatar size, brand mark
size, selection indicators, keypad sizing, sheet handles, and minimum touch
targets. Use `context.icons.xxs` for tiny trend arrows rather than borrowing a
spacing value.

Interactive controls should maintain at least `context.metrics.minTouchTarget`
as their hit area even when the visual is intentionally compact.

## State And Effects

State-layer opacity belongs in `context.stateLayers`:

```dart
Opacity(
  opacity: enabled
      ? context.stateLayers.visible
      : context.stateLayers.disabled,
  child: child,
);
```

`visible` and `hidden` are the only neutral endpoints and exist for APIs such
as `Opacity`/`AnimatedOpacity` that require both states. They are not the start
of a numeric opacity ramp. Custom-painter interpolation may retain local zero
and one endpoints because those values are rendering math rather than product
state treatment.

Visual treatments that are not interaction states belong in `context.effects`:
brand glass, scan scrims, art noise, market tile treatment, and similar
authored effects. Do not add generic `opacity10` style ramps; add a semantic
role only when the value is a repeatable design decision.

## Motion

Use `context.motion` for reusable component timing and screen choreography:

```dart
AnimatedContainer(
  duration: context.motionPolicy.duration(
    context.motion.selectionTransitionDuration,
  ),
  curve: context.motion.fastEase,
  child: child,
);
```

Prefer semantic motion names such as `swapKeyboardTransitionDuration` over
generic duration names. Authored choreography phases belong in the motion
system; only mathematical interpolation remains local to a painter.

## Gradients And Art

Use `context.gradients` for authored gradient recipes and `context.art` for
brand-art composition metrics. Do not hand-roll reusable gradient lists in
feature UI.

```dart
DecoratedBox(
  decoration: BoxDecoration(
    gradient: context.gradients.splashBackdrop.toLinearGradient(),
  ),
);
```

## Migration Examples

```dart
// Before
color: context.colors.fill1;
borderRadius: BorderRadius.circular(context.radius.radius24);
padding: EdgeInsets.all(context.spacing.spacing20);

// After
color: context.colorScheme.surface;
shape: RoundedSuperellipseBorder(
  borderRadius: BorderRadius.circular(context.radii.card),
);
padding: EdgeInsets.all(context.spacing.screenPadding);
```

```dart
// Before
Text(value, style: style.toNumeric(context));

// After
AmountText(value, style: context.type.rowValue);
```

Keep primitives inside the theme implementation. Product screens should express
what the UI means, not how many pixels or alpha points it happens to use today.
`make verify-design-system` enforces this boundary with an analyzer-AST policy;
its isolated fixtures must change with any deliberate policy change.
