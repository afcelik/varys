import 'package:flutter/material.dart';

/// Varys application theme configuration.
///
/// Implements a minimalist dark theme with Material 3 design system.
/// Color palette:
/// - Background: #141517 (deep dark)
/// - Surface: #1C1D20 (elevated surfaces)
/// - Accent: #5DCAA5 (teal accent for primary actions)
class AppTheme {
  static const Color _background = Color(0xFF141517);
  static const Color _surface = Color(0xFF1C1D20);
  static const Color _accent = Color(0xFF5DCAA5);
  static const Color _onBackground = Color(0xFFFFFFFF);
  static const Color _onSurface = Color(0xFFFFFFFF);
  static const Color _onAccent = Color(0xFF000000);
  static const Color _outline = Color(0xFF3A3B3E);
  static const Color _outlineVariant = Color(0xFF2A2B2E);

  static ThemeData get darkTheme {
    final ColorScheme colorScheme = ColorScheme(
      brightness: Brightness.dark,
      primary: _accent,
      onPrimary: _onAccent,
      primaryContainer: _accent.withValues(alpha: 0.15),
      onPrimaryContainer: _accent,
      secondary: _accent.withValues(alpha: 0.8),
      onSecondary: _onAccent,
      secondaryContainer: _accent.withValues(alpha: 0.1),
      onSecondaryContainer: _accent,
      tertiary: _accent.withValues(alpha: 0.6),
      onTertiary: _onAccent,
      tertiaryContainer: _accent.withValues(alpha: 0.08),
      onTertiaryContainer: _accent,
      error: const Color(0xFFCF6679),
      onError: const Color(0xFF000000),
      errorContainer: const Color(0xFFCF6679).withValues(alpha: 0.15),
      onErrorContainer: const Color(0xFFCF6679),
      surface: _surface,
      onSurface: _onSurface,
      surfaceContainerHighest: _surface,
      surfaceContainerHigh: _surface,
      surfaceContainer: _surface,
      surfaceContainerLow: _surface,
      surfaceContainerLowest: _background,
      onSurfaceVariant: _onSurface.withValues(alpha: 0.7),
      outline: _outline,
      outlineVariant: _outlineVariant,
      shadow: Colors.black.withValues(alpha: 0.4),
      scrim: Colors.black.withValues(alpha: 0.6),
      inverseSurface: _onBackground,
      onInverseSurface: _background,
      inversePrimary: _accent,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: _background,
      canvasColor: _background,

      // AppBar theme
      appBarTheme: AppBarTheme(
        backgroundColor: _surface,
        foregroundColor: _onSurface,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: _onSurface,
          fontSize: 20,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.15,
        ),
        iconTheme: IconThemeData(color: _onSurface),
        actionsIconTheme: IconThemeData(color: _onSurface),
      ),

      // Card theme
      cardTheme: CardThemeData(
        color: _surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: _outlineVariant, width: 1),
        ),
        margin: const EdgeInsets.all(8),
      ),

      // Elevated button theme
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: _accent,
          foregroundColor: _onAccent,
          elevation: 0,
          shadowColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          textStyle: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.1,
          ),
        ),
      ),

      // Outlined button theme
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: _accent,
          side: BorderSide(color: _accent, width: 1.5),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          textStyle: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.1,
          ),
        ),
      ),

      // Text button theme
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: _accent,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          textStyle: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.1,
          ),
        ),
      ),

      // Input decoration theme
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: _background,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: _outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: _outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: _accent, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xFFCF6679)),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xFFCF6679), width: 2),
        ),
        labelStyle: TextStyle(color: _onSurface.withValues(alpha: 0.6)),
        hintStyle: TextStyle(color: _onSurface.withValues(alpha: 0.38)),
        floatingLabelStyle: TextStyle(color: _accent),
      ),

      // Text theme
      textTheme: TextTheme(
        displayLarge: TextStyle(
          color: _onBackground,
          fontSize: 57,
          fontWeight: FontWeight.w400,
          letterSpacing: -0.25,
        ),
        displayMedium: TextStyle(
          color: _onBackground,
          fontSize: 45,
          fontWeight: FontWeight.w400,
          letterSpacing: 0,
        ),
        displaySmall: TextStyle(
          color: _onBackground,
          fontSize: 36,
          fontWeight: FontWeight.w400,
          letterSpacing: 0,
        ),
        headlineLarge: TextStyle(
          color: _onBackground,
          fontSize: 32,
          fontWeight: FontWeight.w600,
          letterSpacing: 0,
        ),
        headlineMedium: TextStyle(
          color: _onBackground,
          fontSize: 28,
          fontWeight: FontWeight.w600,
          letterSpacing: 0,
        ),
        headlineSmall: TextStyle(
          color: _onBackground,
          fontSize: 24,
          fontWeight: FontWeight.w600,
          letterSpacing: 0,
        ),
        titleLarge: TextStyle(
          color: _onSurface,
          fontSize: 22,
          fontWeight: FontWeight.w600,
          letterSpacing: 0,
        ),
        titleMedium: TextStyle(
          color: _onSurface,
          fontSize: 16,
          fontWeight: FontWeight.w500,
          letterSpacing: 0.15,
        ),
        titleSmall: TextStyle(
          color: _onSurface,
          fontSize: 14,
          fontWeight: FontWeight.w500,
          letterSpacing: 0.1,
        ),
        bodyLarge: TextStyle(
          color: _onSurface,
          fontSize: 16,
          fontWeight: FontWeight.w400,
          letterSpacing: 0.5,
        ),
        bodyMedium: TextStyle(
          color: _onSurface,
          fontSize: 14,
          fontWeight: FontWeight.w400,
          letterSpacing: 0.25,
        ),
        bodySmall: TextStyle(
          color: _onSurface.withValues(alpha: 0.6),
          fontSize: 12,
          fontWeight: FontWeight.w400,
          letterSpacing: 0.4,
        ),
        labelLarge: TextStyle(
          color: _onSurface,
          fontSize: 14,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.1,
        ),
        labelMedium: TextStyle(
          color: _onSurface,
          fontSize: 12,
          fontWeight: FontWeight.w500,
          letterSpacing: 0.5,
        ),
        labelSmall: TextStyle(
          color: _onSurface.withValues(alpha: 0.6),
          fontSize: 11,
          fontWeight: FontWeight.w500,
          letterSpacing: 0.5,
        ),
      ),

      // Icon theme
      iconTheme: IconThemeData(
        color: _onSurface,
        size: 24,
      ),

      // Divider theme
      dividerTheme: DividerThemeData(
        color: _outlineVariant,
        thickness: 1,
        space: 1,
      ),

      // List tile theme
      listTileTheme: ListTileThemeData(
        tileColor: Colors.transparent,
        selectedTileColor: _accent.withValues(alpha: 0.1),
        iconColor: _onSurface.withValues(alpha: 0.7),
        textColor: _onSurface,
        titleTextStyle: TextStyle(
          color: _onSurface,
          fontSize: 16,
          fontWeight: FontWeight.w500,
        ),
        subtitleTextStyle: TextStyle(
          color: _onSurface.withValues(alpha: 0.6),
          fontSize: 14,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      ),

      // Navigation bar theme (for bottom navigation)
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: _surface,
        surfaceTintColor: Colors.transparent,
        elevation: 8,
        height: 72,
        indicatorColor: _accent.withValues(alpha: 0.15),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return TextStyle(
              color: _accent,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            );
          }
          return TextStyle(
            color: _onSurface.withValues(alpha: 0.6),
            fontSize: 12,
            fontWeight: FontWeight.w500,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return IconThemeData(color: _accent, size: 24);
          }
          return IconThemeData(
            color: _onSurface.withValues(alpha: 0.6),
            size: 24,
          );
        }),
      ),

      // Navigation rail theme (for side navigation)
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: _surface,
        elevation: 0,
        indicatorColor: _accent.withValues(alpha: 0.15),
        selectedIconTheme: IconThemeData(color: _accent, size: 24),
        unselectedIconTheme: IconThemeData(
          color: _onSurface.withValues(alpha: 0.6),
          size: 24,
        ),
        selectedLabelTextStyle: TextStyle(
          color: _accent,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
        unselectedLabelTextStyle: TextStyle(
          color: _onSurface.withValues(alpha: 0.6),
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
        labelType: NavigationRailLabelType.all,
        minWidth: 72,
        minExtendedWidth: 200,
      ),

      // Floating action button theme
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: _accent,
        foregroundColor: _onAccent,
        elevation: 4,
        focusElevation: 6,
        hoverElevation: 6,
        highlightElevation: 8,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),

      // Bottom sheet theme
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: _surface,
        surfaceTintColor: Colors.transparent,
        elevation: 16,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        modalBackgroundColor: _surface,
      ),

      // Dialog theme
      dialogTheme: DialogThemeData(
        backgroundColor: _surface,
        surfaceTintColor: Colors.transparent,
        elevation: 24,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        titleTextStyle: TextStyle(
          color: _onSurface,
          fontSize: 20,
          fontWeight: FontWeight.w600,
        ),
        contentTextStyle: TextStyle(
          color: _onSurface.withValues(alpha: 0.8),
          fontSize: 16,
        ),
      ),

      // Snack bar theme
      snackBarTheme: SnackBarThemeData(
        backgroundColor: _surface,
        contentTextStyle: TextStyle(color: _onSurface),
        actionTextColor: _accent,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        elevation: 8,
      ),

      // Tooltip theme
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: _surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: _outlineVariant),
        ),
        textStyle: TextStyle(color: _onSurface, fontSize: 12),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),

      // Progress indicator theme
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: _accent,
        linearTrackColor: _outlineVariant,
        circularTrackColor: _outlineVariant,
      ),

      // Chip theme
      chipTheme: ChipThemeData(
        backgroundColor: _surface,
        selectedColor: _accent.withValues(alpha: 0.2),
        disabledColor: _surface.withValues(alpha: 0.5),
        labelStyle: TextStyle(color: _onSurface),
        secondaryLabelStyle: TextStyle(color: _accent),
        side: BorderSide(color: _outlineVariant),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        showCheckmark: false,
      ),

      // Tab bar theme
      tabBarTheme: TabBarThemeData(
        labelColor: _accent,
        unselectedLabelColor: _onSurface.withValues(alpha: 0.6),
        indicatorColor: _accent,
        indicatorSize: TabBarIndicatorSize.label,
        labelStyle: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
        unselectedLabelStyle: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
        dividerColor: _outlineVariant,
      ),
    );
  }
}