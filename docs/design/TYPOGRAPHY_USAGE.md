# Typography System Usage Guide

This guide shows you how to use the typography design tokens in your widgets.

## Available Typography Styles

### Material Design 3 Text Styles (via Theme)
All Material Design 3 text styles are available through `Theme.of(context).textTheme`:

- `displayLarge`, `displayMedium`, `displaySmall` - Hero sections
- `headlineLarge`, `headlineMedium`, `headlineSmall` - Section headers
- `titleLarge`, `titleMedium`, `titleSmall` - Card titles, subsection headers
- `labelLarge`, `labelMedium`, `labelSmall` - UI element labels
- `bodyLarge`, `bodyMedium`, `bodySmall` - Main content text

These styles are built from design tokens and automatically use the correct font family, sizes, weights, line heights, and letter spacing.

## Usage Examples

### Method 1: Using Material TextTheme (Recommended for most cases)

This is the simplest and most common way to use typography:

```dart
// In any widget with BuildContext
Text(
  'Hello World',
  style: Theme.of(context).textTheme.headlineLarge,
)

// Or with color override
Text(
  'Hello World',
  style: Theme.of(context).textTheme.headlineLarge?.copyWith(
    color: Colors.blue,
  ),
)
```

### Method 2: Using Direct Tokens (For custom combinations)

When you need a custom style that doesn't match any Material Design 3 style:

```dart
import 'package:aster/shared/theme/typography.dart';
import 'package:aster/shared/theme/theme_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class MyWidget extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appTheme = ref.watch(appThemeProvider);
    final typography = appTheme.typography;
    final colorScheme = Theme.of(context).colorScheme;
    
    return Text(
      'Custom Text',
      style: TypographySystem.buildStyle(
        tokens: typography,
        fontSize: typography.size05, // 20px
        fontWeight: typography.weightSemiBold,
        lineHeight: typography.lineHeightNormal,
        letterSpacing: typography.letterSpacingNormal,
        color: colorScheme.onSurface,
      ),
    );
  }
}
```

## Common Use Cases

### Asset Row (like in your AssetRow widget)

```dart
class AssetRow extends ConsumerWidget {
  final String name;
  final String fiatBalance;
  
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appTheme = ref.watch(appThemeProvider);
    final typography = appTheme.typography;
    final colorScheme = Theme.of(context).colorScheme;
    
    return Row(
      children: [
        Expanded(
          child: Text(
            name,
            style: TypographySystem.buildStyle(
              tokens: typography,
              fontSize: typography.size03, // 16px
              fontWeight: typography.weightSemiBold,
              lineHeight: typography.lineHeightNormal,
              letterSpacing: typography.letterSpacingNormal,
              color: colorScheme.onSurface,
            ),
          ),
        ),
        Text(
          fiatBalance,
          style: TypographySystem.buildStyle(
            tokens: typography,
            fontSize: typography.size03, // 16px
            fontWeight: typography.weightMedium,
            lineHeight: typography.lineHeightNormal,
            letterSpacing: typography.letterSpacingNormal,
            color: colorScheme.onSurface,
          ),
        ),
      ],
    );
  }
}
```

### App Bar Title

```dart
AppBar(
  title: Text(
    'My App',
    style: Theme.of(context).textTheme.titleMedium?.copyWith(
      fontSize: 18,
      letterSpacing: 0.15,
    ),
  ),
)
```

Or using tokens:

```dart
AppBar(
  title: Consumer(
    builder: (context, ref, _) {
      final appTheme = ref.watch(appThemeProvider);
      return Text(
        'My App',
        style: TypographySystem.buildStyle(
          tokens: appTheme.typography,
          fontSize: appTheme.typography.size04, // 18px
          fontWeight: appTheme.typography.weightBold,
          lineHeight: appTheme.typography.lineHeightNormal,
          letterSpacing: appTheme.typography.letterSpacingNormal,
          color: Theme.of(context).colorScheme.onSurface,
        ),
      );
    },
  ),
)
```

### Button Text

Buttons typically use the theme's button styles, but you can customize:

```dart
ElevatedButton(
  onPressed: () {},
  style: ElevatedButton.styleFrom(
    textStyle: Theme.of(context).textTheme.labelLarge,
  ),
  child: Text('Click Me'),
)
```

Or with custom styling:

```dart
ElevatedButton(
  onPressed: () {},
  child: Consumer(
    builder: (context, ref, _) {
      final appTheme = ref.watch(appThemeProvider);
      return Text(
        'Click Me',
        style: TypographySystem.buildStyle(
          tokens: appTheme.typography,
          fontSize: appTheme.typography.size03, // 16px
          fontWeight: appTheme.typography.weightSemiBold,
          lineHeight: appTheme.typography.lineHeightNormal,
          letterSpacing: appTheme.typography.letterSpacingWide,
          color: Theme.of(context).colorScheme.onPrimary,
        ),
      );
    },
  ),
)
```

### Card with Title and Body

```dart
Card(
  child: Padding(
    padding: EdgeInsets.all(16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Card Title',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        SizedBox(height: 8),
        Text(
          'Card body content goes here...',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ],
    ),
  ),
)
```

### Statistics/Numbers

```dart
Consumer(
  builder: (context, ref, _) {
    final appTheme = ref.watch(appThemeProvider);
    return Text(
      '\$1,234.56',
      style: TypographySystem.buildStyle(
        tokens: appTheme.typography,
        fontSize: appTheme.typography.size09, // 32px
        fontWeight: appTheme.typography.weightBold,
        lineHeight: appTheme.typography.lineHeightTight,
        letterSpacing: appTheme.typography.letterSpacingTight,
        color: Theme.of(context).colorScheme.primary,
      ),
    );
  },
)
```

### Secondary Text / Metadata

```dart
Text(
  'BTC',
  style: TypographySystem.buildStyle(
    tokens: appTheme.typography,
    fontSize: appTheme.typography.size01, // 12px
    fontWeight: appTheme.typography.weightMedium,
    lineHeight: appTheme.typography.lineHeightNormal,
    letterSpacing: appTheme.typography.letterSpacingNormal,
    color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
  ),
)
```

Or using Material TextTheme:

```dart
Text(
  'BTC',
  style: Theme.of(context).textTheme.bodySmall?.copyWith(
    color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
  ),
)
```

## Quick Reference: Available Tokens

### Font Sizes
- `size01` - 12px
- `size02` - 14px
- `size03` - 16px
- `size04` - 18px
- `size05` - 20px
- `size06` - 22px
- `size07` - 24px
- `size08` - 28px
- `size09` - 32px
- `size10` - 36px
- `size11` - 45px
- `size12` - 57px

### Font Weights
- `weightThin` - 100
- `weightExtraLight` - 200
- `weightLight` - 300
- `weightRegular` - 400
- `weightMedium` - 500
- `weightSemiBold` - 600
- `weightBold` - 700
- `weightExtraBold` - 800
- `weightBlack` - 900

### Line Heights
- `lineHeightTight` - 1.0
- `lineHeightSnug` - 1.2
- `lineHeightNormal` - 1.4
- `lineHeightRelaxed` - 1.5
- `lineHeightLoose` - 1.6

### Letter Spacing
- `letterSpacingTight` - -0.025em
- `letterSpacingNormal` - 0em
- `letterSpacingWide` - 0.05em
- `letterSpacingWider` - 0.1em
- `letterSpacingWidest` - 0.15em

## Best Practices

1. **Prefer Material TextTheme** for standard text (body, headlines, titles, labels)
2. **Use TypographySystem.buildStyle()** only when you need a custom combination that doesn't match any Material style
3. **Always use tokens** - never hardcode font sizes, weights, line heights, or letter spacing
4. **Access colors from ColorScheme** for proper theming support
5. **Use copyWith()** on Material text styles when you only need to change color or other properties

## Material Design 3 Style Mapping

Here's how Material styles map to common use cases:

- **Hero sections**: `displayLarge`, `displayMedium`, `displaySmall`
- **Page/section headers**: `headlineLarge`, `headlineMedium`, `headlineSmall`
- **Card titles**: `titleLarge`
- **Subsection headers**: `titleMedium`, `titleSmall`
- **Button labels**: `labelLarge` (already configured in button themes)
- **Form field labels**: `labelMedium`, `labelSmall`
- **Main content**: `bodyLarge`, `bodyMedium`
- **Secondary text**: `bodySmall`
- **Captions/metadata**: `bodySmall` or `labelSmall`

## Migration from Old Code

### Before (hardcoded):
```dart
Text(
  'Asset Name',
  style: GoogleFonts.dmSans(
    fontSize: 16,
    fontWeight: FontWeight.w600,
    color: Colors.black,
  ),
)
```

### After (using Material TextTheme - Recommended):
```dart
Text(
  'Asset Name',
  style: Theme.of(context).textTheme.titleMedium,
)
```

### After (using tokens - For custom styles):
```dart
Consumer(
  builder: (context, ref, _) {
    final appTheme = ref.watch(appThemeProvider);
    return Text(
      'Asset Name',
      style: TypographySystem.buildStyle(
        tokens: appTheme.typography,
        fontSize: appTheme.typography.size03,
        fontWeight: appTheme.typography.weightSemiBold,
        lineHeight: appTheme.typography.lineHeightNormal,
        letterSpacing: appTheme.typography.letterSpacingNormal,
        color: Theme.of(context).colorScheme.onSurface,
      ),
    );
  },
)
```

## Summary

- **Use `Theme.of(context).textTheme.*`** for 90% of your text styling needs
- **Use `TypographySystem.buildStyle()`** only when you need custom combinations
- **All styles are built from design tokens** ensuring consistency across the app
- **Never hardcode typography values** - always use tokens
