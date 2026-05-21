import 'package:flutter/material.dart';

import 'tokens/tokens.dart';
import 'typography.dart';

class AppTheme {
  AppTheme._();

  static const _colors = AsterColors.light;
  static const _spacing = AsterSpacing();
  static const _radii = AsterRadii();
  static const _shadows = AsterShadows();
  static const _typography = AsterTypography();
  static const _metrics = AsterComponentMetrics();
  static const _motion = AsterMotion();
  static const _effects = AsterEffects();

  static ThemeData light() {
    final scheme = _colorScheme();
    final textTheme = TypographySystem.buildTextTheme(
      onSurface: scheme.onSurface,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: scheme,
      scaffoldBackgroundColor: scheme.surface,
      textTheme: textTheme,
      primaryTextTheme: textTheme,
      extensions: const <ThemeExtension<dynamic>>[
        _colors,
        _spacing,
        _radii,
        _shadows,
        _typography,
        _metrics,
        _motion,
        _effects,
      ],
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        elevation: 0,
        surfaceTintColor: AsterColors.transparent,
        iconTheme: IconThemeData(
          color: scheme.onSurface,
          size: _spacing.iconMd,
        ),
        titleTextStyle: textTheme.titleMedium?.copyWith(
          color: scheme.onSurface,
        ),
      ),
      cardTheme: CardThemeData(
        color: _colors.surfaceRaised,
        surfaceTintColor: AsterColors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_radii.card),
          side: BorderSide(color: _colors.borderSubtle),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: _colors.surfaceSubtle,
        contentPadding: EdgeInsets.symmetric(
          horizontal: _spacing.lg,
          vertical: _spacing.md,
        ),
        border: _outlineBorder(_colors.borderSubtle),
        enabledBorder: _outlineBorder(_colors.borderSubtle),
        focusedBorder: _outlineBorder(
          scheme.primary,
          width: _metrics.focusBorderWidth,
        ),
        errorBorder: _outlineBorder(scheme.error),
        focusedErrorBorder: _outlineBorder(
          scheme.error,
          width: _metrics.focusBorderWidth,
        ),
        labelStyle: textTheme.bodyMedium?.copyWith(
          color: _colors.textSecondary,
        ),
        hintStyle: textTheme.bodyMedium?.copyWith(color: _colors.textTertiary),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: _buttonStyle(
          background: scheme.primary,
          foreground: scheme.onPrimary,
          textTheme: textTheme,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: _buttonStyle(
          background: AsterColors.transparent,
          foreground: scheme.onSurface,
          textTheme: textTheme,
          side: BorderSide(color: _colors.borderSubtle),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: scheme.primary,
          padding: EdgeInsets.symmetric(
            horizontal: _spacing.lg,
            vertical: _spacing.md,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(_radii.button),
          ),
          textStyle: textTheme.labelLarge,
        ),
      ),
      iconTheme: IconThemeData(color: scheme.onSurface, size: _spacing.iconMd),
      dividerTheme: DividerThemeData(
        color: _colors.borderSubtle,
        thickness: 1,
        space: 1,
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: _colors.surfaceRaised,
        selectedItemColor: scheme.primary,
        unselectedItemColor: _colors.textTertiary,
        selectedLabelStyle: textTheme.labelSmall,
        unselectedLabelStyle: textTheme.labelSmall,
        type: BottomNavigationBarType.fixed,
        elevation: 0,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: _colors.surfaceRaised,
        surfaceTintColor: AsterColors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_radii.card),
        ),
        titleTextStyle: textTheme.headlineSmall?.copyWith(
          color: scheme.onSurface,
        ),
        contentTextStyle: textTheme.bodyMedium?.copyWith(
          color: _colors.textSecondary,
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AsterColors.ink,
        contentTextStyle: textTheme.bodyMedium?.copyWith(
          color: scheme.onInverseSurface,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_radii.md),
        ),
        behavior: SnackBarBehavior.floating,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: _colors.surfaceSubtle,
        deleteIconColor: _colors.textSecondary,
        disabledColor: _colors.surfaceSubtle,
        selectedColor: scheme.primaryContainer,
        secondarySelectedColor: scheme.primaryContainer,
        padding: EdgeInsets.symmetric(
          horizontal: _spacing.md,
          vertical: _spacing.sm,
        ),
        labelStyle: textTheme.labelMedium?.copyWith(color: scheme.onSurface),
        secondaryLabelStyle: textTheme.labelMedium?.copyWith(
          color: scheme.onPrimaryContainer,
        ),
        brightness: Brightness.light,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_radii.badge),
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          return states.contains(WidgetState.selected)
              ? scheme.primary
              : _colors.textDisabled;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          return states.contains(WidgetState.selected)
              ? scheme.primaryContainer
              : _colors.surfaceSubtle;
        }),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) {
          return states.contains(WidgetState.selected)
              ? scheme.primary
              : AsterColors.transparent;
        }),
        checkColor: WidgetStateProperty.all(scheme.onPrimary),
        side: BorderSide(
          color: _colors.borderSubtle,
          width: _metrics.focusBorderWidth,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_radii.xs),
        ),
      ),
      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) {
          return states.contains(WidgetState.selected)
              ? scheme.primary
              : _colors.textTertiary;
        }),
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: scheme.primary,
        inactiveTrackColor: _colors.surfaceSubtle,
        thumbColor: scheme.primary,
        overlayColor: scheme.primary.withValues(
          alpha: _effects.primaryOverlayOpacity,
        ),
        valueIndicatorColor: scheme.primary,
        valueIndicatorTextStyle: textTheme.labelSmall?.copyWith(
          color: scheme.onPrimary,
        ),
        trackShape: const RoundedRectSliderTrackShape(),
        thumbShape: RoundSliderThumbShape(
          enabledThumbRadius: _metrics.sliderThumbRadius,
        ),
        overlayShape: RoundSliderOverlayShape(
          overlayRadius: _metrics.sliderOverlayRadius,
        ),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: scheme.primary,
        linearTrackColor: _colors.surfaceSubtle,
        circularTrackColor: _colors.surfaceSubtle,
      ),
      listTileTheme: ListTileThemeData(
        tileColor: AsterColors.transparent,
        selectedTileColor: _colors.surfaceSubtle,
        iconColor: _colors.textSecondary,
        textColor: scheme.onSurface,
        contentPadding: EdgeInsets.symmetric(
          horizontal: _spacing.lg,
          vertical: _spacing.sm,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_radii.input),
        ),
      ),
      drawerTheme: DrawerThemeData(
        backgroundColor: scheme.surface,
        surfaceTintColor: AsterColors.transparent,
        elevation: 0,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: _colors.surfaceRaised,
        surfaceTintColor: AsterColors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(_radii.sheet),
          ),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_radii.lg),
        ),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: AsterColors.ink,
          borderRadius: BorderRadius.circular(_radii.badge),
        ),
        textStyle: textTheme.labelSmall?.copyWith(color: AsterColors.white),
        padding: EdgeInsets.symmetric(
          horizontal: _spacing.md,
          vertical: _spacing.sm,
        ),
      ),
      expansionTileTheme: ExpansionTileThemeData(
        backgroundColor: AsterColors.transparent,
        collapsedBackgroundColor: AsterColors.transparent,
        textColor: scheme.onSurface,
        iconColor: _colors.textSecondary,
        collapsedTextColor: _colors.textSecondary,
        collapsedIconColor: _colors.textSecondary,
      ),
    );
  }

  static ThemeData dark() => light();

  static ColorScheme _colorScheme() {
    return const ColorScheme.light(
      primary: AsterColors.blueBase,
      onPrimary: AsterColors.white,
      primaryContainer: AsterColors.blue200,
      onPrimaryContainer: AsterColors.blue900,
      secondary: AsterColors.blue600,
      onSecondary: AsterColors.white,
      secondaryContainer: AsterColors.blue300,
      onSecondaryContainer: AsterColors.blue900,
      tertiary: AsterColors.blue800,
      onTertiary: AsterColors.white,
      tertiaryContainer: AsterColors.blue500,
      onTertiaryContainer: AsterColors.blue900,
      error: Color(0xFFF53F3F),
      onError: AsterColors.white,
      errorContainer: Color(0xFFFFECE8),
      onErrorContainer: AsterColors.ink,
      surface: AsterColors.surface,
      onSurface: AsterColors.ink,
      surfaceContainerLowest: AsterColors.white,
      surfaceContainerLow: Color(0xFFF7F8FA),
      surfaceContainer: Color(0xFFF2F3F5),
      surfaceContainerHigh: Color(0xFFE5E6EB),
      surfaceContainerHighest: Color(0xFFC9CDD4),
      onSurfaceVariant: Color(0xFF86909C),
      outline: Color(0xFFE5E6EB),
      outlineVariant: Color(0xFFF2F3F5),
      inverseSurface: AsterColors.ink,
      onInverseSurface: AsterColors.white,
      inversePrimary: AsterColors.blue600,
      shadow: AsterColors.ink,
      scrim: AsterColors.ink,
    );
  }

  static OutlineInputBorder _outlineBorder(Color color, {double? width}) {
    return OutlineInputBorder(
      borderRadius: BorderRadius.circular(_radii.input),
      borderSide: BorderSide(
        color: color,
        width: width ?? _metrics.borderWidth,
      ),
    );
  }

  static ButtonStyle _buttonStyle({
    required Color background,
    required Color foreground,
    required TextTheme textTheme,
    BorderSide? side,
  }) {
    return ElevatedButton.styleFrom(
      backgroundColor: background,
      foregroundColor: foreground,
      elevation: 0,
      shadowColor: AsterColors.transparent,
      padding: EdgeInsets.symmetric(
        horizontal: _spacing.xxl,
        vertical: _spacing.md,
      ),
      side: side,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(_radii.button),
      ),
      textStyle: textTheme.labelLarge,
    );
  }
}
