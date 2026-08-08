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
  static const _icons = AsterIconography();
  static const _strokes = AsterStrokes();
  static const _stateLayers = AsterStateLayers();
  static const _gradients = AsterGradients.light;
  static const _art = AsterArt();

  static ThemeData light() {
    final scheme = AsterColors.lightColorScheme();
    final textTheme = TypographySystem.buildTextTheme(
      onSurface: scheme.onSurface,
    );
    final typeRoles = AsterTypeRoles.fromTheme(
      textTheme: textTheme,
      colorScheme: scheme,
      colors: _colors,
      effects: _effects,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: scheme,
      scaffoldBackgroundColor: scheme.surface,
      textTheme: textTheme,
      primaryTextTheme: textTheme,
      extensions: <ThemeExtension<dynamic>>[
        _colors,
        _spacing,
        _radii,
        _shadows,
        _typography,
        _metrics,
        _motion,
        _effects,
        _icons,
        _strokes,
        _stateLayers,
        _gradients,
        _art,
        typeRoles,
      ],
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        elevation: 0,
        surfaceTintColor: _colors.transparentSurface,
        iconTheme: IconThemeData(color: scheme.onSurface, size: _icons.md),
        titleTextStyle: typeRoles.appBarTitle,
      ),
      cardTheme: CardThemeData(
        color: _colors.surfaceRaised,
        surfaceTintColor: _colors.transparentSurface,
        elevation: 0,
        shape: RoundedSuperellipseBorder(
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
          width: _strokes.focusBorder,
        ),
        errorBorder: _outlineBorder(scheme.error),
        focusedErrorBorder: _outlineBorder(
          scheme.error,
          width: _strokes.focusBorder,
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
          textStyle: typeRoles.buttonLabel,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: _buttonStyle(
          background: _colors.transparentSurface,
          foreground: scheme.onSurface,
          textStyle: typeRoles.buttonLabel,
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
          shape: RoundedSuperellipseBorder(
            borderRadius: BorderRadius.circular(_radii.button),
          ),
          textStyle: typeRoles.buttonLabel,
        ),
      ),
      iconTheme: IconThemeData(color: scheme.onSurface, size: _icons.md),
      dividerTheme: DividerThemeData(
        color: _colors.borderSubtle,
        thickness: _strokes.divider,
        space: _strokes.divider,
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
        surfaceTintColor: _colors.transparentSurface,
        elevation: 0,
        shape: RoundedSuperellipseBorder(
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
        backgroundColor: scheme.inverseSurface,
        contentTextStyle: textTheme.bodyMedium?.copyWith(
          color: scheme.onInverseSurface,
        ),
        shape: RoundedSuperellipseBorder(
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
        shape: RoundedSuperellipseBorder(
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
              : _colors.transparentSurface;
        }),
        checkColor: WidgetStateProperty.all(scheme.onPrimary),
        side: BorderSide(
          color: _colors.borderSubtle,
          width: _strokes.focusBorder,
        ),
        shape: RoundedSuperellipseBorder(
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
          alpha: _stateLayers.primaryOverlay,
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
        tileColor: _colors.transparentSurface,
        selectedTileColor: _colors.surfaceSubtle,
        iconColor: _colors.textSecondary,
        textColor: scheme.onSurface,
        contentPadding: EdgeInsets.symmetric(
          horizontal: _spacing.lg,
          vertical: _spacing.sm,
        ),
        shape: RoundedSuperellipseBorder(
          borderRadius: BorderRadius.circular(_radii.input),
        ),
      ),
      drawerTheme: DrawerThemeData(
        backgroundColor: scheme.surface,
        surfaceTintColor: _colors.transparentSurface,
        elevation: 0,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: _colors.surfaceRaised,
        surfaceTintColor: _colors.transparentSurface,
        elevation: 0,
        shape: RoundedSuperellipseBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(_radii.sheet),
          ),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        elevation: 0,
        shape: RoundedSuperellipseBorder(
          borderRadius: BorderRadius.circular(_radii.lg),
        ),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: ShapeDecoration(
          color: scheme.inverseSurface,
          shape: RoundedSuperellipseBorder(
            borderRadius: BorderRadius.circular(_radii.badge),
          ),
        ),
        textStyle: textTheme.labelSmall?.copyWith(
          color: scheme.onInverseSurface,
        ),
        padding: EdgeInsets.symmetric(
          horizontal: _spacing.md,
          vertical: _spacing.sm,
        ),
      ),
      expansionTileTheme: ExpansionTileThemeData(
        backgroundColor: _colors.transparentSurface,
        collapsedBackgroundColor: _colors.transparentSurface,
        textColor: scheme.onSurface,
        iconColor: _colors.textSecondary,
        collapsedTextColor: _colors.textSecondary,
        collapsedIconColor: _colors.textSecondary,
      ),
    );
  }

  static ShapedInputBorder _outlineBorder(Color color, {double? width}) {
    return ShapedInputBorder(
      borderSide: BorderSide(color: color, width: width ?? _strokes.border),
      shape: RoundedSuperellipseBorder(
        borderRadius: BorderRadius.circular(_radii.input),
      ),
    );
  }

  static ButtonStyle _buttonStyle({
    required Color background,
    required Color foreground,
    required TextStyle textStyle,
    BorderSide? side,
  }) {
    return ElevatedButton.styleFrom(
      backgroundColor: background,
      foregroundColor: foreground,
      elevation: 0,
      shadowColor: _colors.transparentSurface,
      padding: EdgeInsets.symmetric(
        horizontal: _spacing.xxl,
        vertical: _spacing.md,
      ),
      side: side,
      shape: RoundedSuperellipseBorder(
        borderRadius: BorderRadius.circular(_radii.button),
      ),
      textStyle: textStyle,
    );
  }
}
