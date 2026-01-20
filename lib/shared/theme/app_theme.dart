import 'package:flutter/material.dart';

import 'tokens/color_tokens.dart';
import 'tokens/typography_tokens.dart';
import 'typography.dart';

/// App theme configuration with light and dark mode support
///
/// This class provides comprehensive ThemeData for both light and dark modes,
///
/// using design tokens for consistency across the application.
class AppTheme {
  AppTheme._();

  /// Typography tokens used across the app
  static const TypographyTokens _typographyTokens = TypographyTokens();

  /// Light theme configuration
  static ThemeData light() {
    final colors = ColorTokens.light;
    final textTheme = TypographySystem.buildTextTheme(
      tokens: _typographyTokens,
      onBackground: colors.text1,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,

      // Color Scheme - Material 3 color system
      colorScheme: ColorScheme.light(
        // Primary colors
        primary: colors.brand6,
        onPrimary: colors.text5,
        primaryContainer: colors.brand1,
        onPrimaryContainer: colors.brand7,

        // Secondary colors
        secondary: colors.brand4,
        onSecondary: colors.text5,
        secondaryContainer: colors.brand2,
        onSecondaryContainer: colors.brand7,

        // Tertiary colors
        tertiary: colors.brand5,
        onTertiary: colors.text5,
        tertiaryContainer: colors.brand3,
        onTertiaryContainer: colors.brand7,

        // Error colors
        error: colors.danger6,
        onError: colors.text5,
        errorContainer: colors.danger1,
        onErrorContainer: colors.danger7,

        // Success colors (using custom colors)
        // Note: Material 3 doesn't have success in ColorScheme, but we can use tertiary

        // Surface colors
        surface: colors.fill1, // White background
        onSurface: colors.text1,
        surfaceContainerHighest: colors.fill3,
        onSurfaceVariant: colors.text3,

        // Outline colors
        outline: colors.border2,
        outlineVariant: colors.border1,

        // Inverse colors
        inverseSurface: colors.fill5,
        onInverseSurface: colors.text5,
        inversePrimary: colors.brand4,

        // Shadow
        shadow: colors.text1.withValues(alpha: 0.1),
        scrim: colors.text1.withValues(alpha: 0.3),
      ),

      // Scaffold background
      scaffoldBackgroundColor: colors.fill1, // White
      // AppBar theme
      appBarTheme: AppBarTheme(
        backgroundColor: colors.fill1,
        foregroundColor: colors.text1,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        iconTheme: IconThemeData(color: colors.text1),
        titleTextStyle: textTheme.titleLarge?.copyWith(
          color: colors.text1,
          fontWeight: FontWeight.w600,
        ),
      ),

      // Card theme
      cardTheme: CardThemeData(
        color: colors.fill1,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: BorderSide(color: colors.border2, width: 1),
        ),
      ),

      // Input decoration theme
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colors.fill2,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: colors.border2),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: colors.border2),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: colors.brand6, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: colors.danger6),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: colors.danger6, width: 2),
        ),
        labelStyle: textTheme.bodyMedium?.copyWith(color: colors.text2),
        hintStyle: textTheme.bodyMedium?.copyWith(color: colors.text3),
      ),

      // Button themes
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: colors.brand6,
          foregroundColor: colors.text5,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          textStyle: textTheme.labelLarge,
        ),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: colors.text1,
          side: BorderSide(color: colors.border2),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          textStyle: textTheme.labelLarge,
        ),
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: colors.brand6,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: textTheme.labelLarge,
        ),
      ),

      // Icon theme
      iconTheme: IconThemeData(color: colors.text1, size: 24),

      // Divider theme
      dividerTheme: DividerThemeData(
        color: colors.border2,
        thickness: 1,
        space: 1,
      ),

      // Text theme
      textTheme: textTheme,

      // Primary text theme (for AppBar, etc.)
      primaryTextTheme: textTheme,

      // Bottom navigation bar theme
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: colors.fill1,
        selectedItemColor: colors.brand6,
        unselectedItemColor: colors.text3,
        selectedLabelStyle: textTheme.labelSmall,
        unselectedLabelStyle: textTheme.labelSmall,
        type: BottomNavigationBarType.fixed,
        elevation: 8,
      ),

      // Dialog theme
      dialogTheme: DialogThemeData(
        backgroundColor: colors.fill1,
        surfaceTintColor: Colors.transparent,
        elevation: 24,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        titleTextStyle: textTheme.headlineSmall?.copyWith(color: colors.text1),
        contentTextStyle: textTheme.bodyMedium?.copyWith(color: colors.text2),
      ),

      // Snackbar theme
      snackBarTheme: SnackBarThemeData(
        backgroundColor: colors.fill5,
        contentTextStyle: textTheme.bodyMedium?.copyWith(color: colors.text5),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        behavior: SnackBarBehavior.floating,
      ),

      // Chip theme
      chipTheme: ChipThemeData(
        backgroundColor: colors.fill2,
        deleteIconColor: colors.text2,
        disabledColor: colors.fill3,
        selectedColor: colors.brand1,
        secondarySelectedColor: colors.brand2,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        labelStyle: textTheme.labelMedium?.copyWith(color: colors.text1),
        secondaryLabelStyle: textTheme.labelMedium?.copyWith(
          color: colors.brand7,
        ),
        brightness: Brightness.light,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),

      // Switch theme
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return colors.brand6;
          }
          return colors.fill4;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return colors.brand1;
          }
          return colors.fill3;
        }),
      ),

      // Checkbox theme
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return colors.brand6;
          }
          return Colors.transparent;
        }),
        checkColor: WidgetStateProperty.all(colors.text5),
        side: BorderSide(color: colors.border3, width: 2),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      ),

      // Radio theme
      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return colors.brand6;
          }
          return colors.border3;
        }),
      ),

      // Slider theme
      sliderTheme: SliderThemeData(
        activeTrackColor: colors.brand6,
        inactiveTrackColor: colors.fill3,
        thumbColor: colors.brand6,
        overlayColor: colors.brand1,
        valueIndicatorColor: colors.brand6,
        valueIndicatorTextStyle: textTheme.labelSmall?.copyWith(
          color: colors.text5,
        ),
        trackShape: const RoundedRectSliderTrackShape(),
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
        overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
      ),

      // Progress indicator theme
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: colors.brand6,
        linearTrackColor: colors.fill3,
        circularTrackColor: colors.fill3,
      ),

      // List tile theme
      listTileTheme: ListTileThemeData(
        tileColor: Colors.transparent,
        selectedTileColor: colors.fill2,
        iconColor: colors.text2,
        textColor: colors.text1,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),

      // Drawer theme
      drawerTheme: DrawerThemeData(
        backgroundColor: colors.fill1,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
      ),

      // Bottom sheet theme
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: colors.fill1,
        surfaceTintColor: Colors.transparent,
        elevation: 8,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
      ),

      // Floating action button theme
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: colors.brand6,
        foregroundColor: colors.text5,
        elevation: 4,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),

      // Tooltip theme
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: colors.fill5,
          borderRadius: BorderRadius.circular(8),
        ),
        textStyle: textTheme.labelSmall?.copyWith(color: colors.text5),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),

      // Expansion tile theme
      expansionTileTheme: ExpansionTileThemeData(
        backgroundColor: Colors.transparent,
        collapsedBackgroundColor: Colors.transparent,
        textColor: colors.text1,
        iconColor: colors.text2,
        collapsedTextColor: colors.text2,
        collapsedIconColor: colors.text2,
      ),
    );
  }

  /// Dark theme configuration
  static ThemeData dark() {
    final colors = ColorTokens.dark;
    final textTheme = TypographySystem.buildTextTheme(
      tokens: _typographyTokens,
      onBackground: colors.text1,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,

      // Color Scheme - Material 3 color system
      colorScheme: ColorScheme.dark(
        // Primary colors
        primary: colors.brand6,
        onPrimary: colors.text5,
        primaryContainer: colors.brand7,
        onPrimaryContainer: colors.brand1,

        // Secondary colors
        secondary: colors.brand4,
        onSecondary: colors.text5,
        secondaryContainer: colors.brand7,
        onSecondaryContainer: colors.brand2,

        // Tertiary colors
        tertiary: colors.brand5,
        onTertiary: colors.text5,
        tertiaryContainer: colors.brand7,
        onTertiaryContainer: colors.brand3,

        // Error colors
        error: colors.danger6,
        onError: colors.text5,
        errorContainer: colors.danger7,
        onErrorContainer: colors.danger1,

        // Surface colors
        surface: colors.fill1, // Black background
        onSurface: colors.text1,
        surfaceContainerHighest: colors.fill3,
        onSurfaceVariant: colors.text3,

        // Outline colors
        outline: colors.border2,
        outlineVariant: colors.border1,

        // Inverse colors
        inverseSurface: colors.fill5,
        onInverseSurface: colors.text5,
        inversePrimary: colors.brand4,

        // Shadow
        shadow: colors.text5.withValues(alpha: 0.1),
        scrim: colors.text5.withValues(alpha: 0.3),
      ),

      // Scaffold background
      scaffoldBackgroundColor: colors.fill1, // Black
      // AppBar theme
      appBarTheme: AppBarTheme(
        backgroundColor: colors.fill1,
        foregroundColor: colors.text1,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        iconTheme: IconThemeData(color: colors.text1),
        titleTextStyle: textTheme.titleLarge?.copyWith(
          color: colors.text1,
          fontWeight: FontWeight.w600,
        ),
      ),

      // Card theme
      cardTheme: CardThemeData(
        color: colors.fill2,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: BorderSide(color: colors.border2, width: 1),
        ),
      ),

      // Input decoration theme
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colors.fill2,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: colors.border2),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: colors.border2),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: colors.brand6, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: colors.danger6),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: colors.danger6, width: 2),
        ),
        labelStyle: textTheme.bodyMedium?.copyWith(color: colors.text2),
        hintStyle: textTheme.bodyMedium?.copyWith(color: colors.text3),
      ),

      // Button themes
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: colors.brand6,
          foregroundColor: colors.text5,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          textStyle: textTheme.labelLarge,
        ),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: colors.text1,
          side: BorderSide(color: colors.border2),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          textStyle: textTheme.labelLarge,
        ),
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: colors.brand6,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: textTheme.labelLarge,
        ),
      ),

      // Icon theme
      iconTheme: IconThemeData(color: colors.text1, size: 24),

      // Divider theme
      dividerTheme: DividerThemeData(
        color: colors.border2,
        thickness: 1,
        space: 1,
      ),

      // Text theme
      textTheme: textTheme,

      // Primary text theme
      primaryTextTheme: textTheme,

      // Bottom navigation bar theme
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: colors.fill2,
        selectedItemColor: colors.brand6,
        unselectedItemColor: colors.text3,
        selectedLabelStyle: textTheme.labelSmall,
        unselectedLabelStyle: textTheme.labelSmall,
        type: BottomNavigationBarType.fixed,
        elevation: 8,
      ),

      // Dialog theme
      dialogTheme: DialogThemeData(
        backgroundColor: colors.fill2,
        surfaceTintColor: Colors.transparent,
        elevation: 24,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        titleTextStyle: textTheme.headlineSmall?.copyWith(color: colors.text1),
        contentTextStyle: textTheme.bodyMedium?.copyWith(color: colors.text2),
      ),

      // Snackbar theme
      snackBarTheme: SnackBarThemeData(
        backgroundColor: colors.fill4,
        contentTextStyle: textTheme.bodyMedium?.copyWith(color: colors.text5),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        behavior: SnackBarBehavior.floating,
      ),

      // Chip theme
      chipTheme: ChipThemeData(
        backgroundColor: colors.fill3,
        deleteIconColor: colors.text3,
        disabledColor: colors.fill4,
        selectedColor: colors.brand7,
        secondarySelectedColor: colors.brand6,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        labelStyle: textTheme.labelMedium?.copyWith(color: colors.text1),
        secondaryLabelStyle: textTheme.labelMedium?.copyWith(
          color: colors.brand1,
        ),
        brightness: Brightness.dark,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),

      // Switch theme
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return colors.brand6;
          }
          return colors.fill4;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return colors.brand7;
          }
          return colors.fill3;
        }),
      ),

      // Checkbox theme
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return colors.brand6;
          }
          return Colors.transparent;
        }),
        checkColor: WidgetStateProperty.all(colors.text5),
        side: BorderSide(color: colors.border3, width: 2),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      ),

      // Radio theme
      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return colors.brand6;
          }
          return colors.border3;
        }),
      ),

      // Slider theme
      sliderTheme: SliderThemeData(
        activeTrackColor: colors.brand6,
        inactiveTrackColor: colors.fill3,
        thumbColor: colors.brand6,
        overlayColor: colors.brand7,
        valueIndicatorColor: colors.brand6,
        valueIndicatorTextStyle: textTheme.labelSmall?.copyWith(
          color: colors.text5,
        ),
        trackShape: const RoundedRectSliderTrackShape(),
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
        overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
      ),

      // Progress indicator theme
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: colors.brand6,
        linearTrackColor: colors.fill3,
        circularTrackColor: colors.fill3,
      ),

      // List tile theme
      listTileTheme: ListTileThemeData(
        tileColor: Colors.transparent,
        selectedTileColor: colors.fill3,
        iconColor: colors.text2,
        textColor: colors.text1,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),

      // Drawer theme
      drawerTheme: DrawerThemeData(
        backgroundColor: colors.fill2,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
      ),

      // Bottom sheet theme
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: colors.fill2,
        surfaceTintColor: Colors.transparent,
        elevation: 8,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
      ),

      // Floating action button theme
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: colors.brand6,
        foregroundColor: colors.text5,
        elevation: 4,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),

      // Tooltip theme
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: colors.fill4,
          borderRadius: BorderRadius.circular(8),
        ),
        textStyle: textTheme.labelSmall?.copyWith(color: colors.text5),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),

      // Expansion tile theme
      expansionTileTheme: ExpansionTileThemeData(
        backgroundColor: Colors.transparent,
        collapsedBackgroundColor: Colors.transparent,
        textColor: colors.text1,
        iconColor: colors.text2,
        collapsedTextColor: colors.text2,
        collapsedIconColor: colors.text2,
      ),
    );
  }
}
