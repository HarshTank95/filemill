import 'package:flutter/material.dart';

/// FileMill design system.
///
/// Type: Space Grotesk (display) + Manrope (body), both bundled as variable
/// fonts — weights must be driven through [FontVariation], not FontWeight
/// alone, or the variable axis is ignored.
class AppTheme {
  AppTheme._();

  static const Color seed = Color(0xFF4353FF);

  /// Accent used for the privacy/offline branding moments.
  static const Color offlineGreen = Color(0xFF1DB954);

  static TextStyle grotesk(
    double weight, {
    double? size,
    double? height,
    double? spacing,
    Color? color,
  }) {
    return TextStyle(
      fontFamily: 'SpaceGrotesk',
      fontVariations: [FontVariation('wght', weight)],
      fontWeight: _nearestWeight(weight),
      fontSize: size,
      height: height,
      letterSpacing: spacing,
      color: color,
    );
  }

  static TextStyle manrope(
    double weight, {
    double? size,
    double? height,
    double? spacing,
    Color? color,
  }) {
    return TextStyle(
      fontFamily: 'Manrope',
      fontVariations: [FontVariation('wght', weight)],
      fontWeight: _nearestWeight(weight),
      fontSize: size,
      height: height,
      letterSpacing: spacing,
      color: color,
    );
  }

  static FontWeight _nearestWeight(double w) {
    const weights = FontWeight.values;
    return weights[(w / 100).round().clamp(1, 9) - 1];
  }

  static ThemeData light() => _build(Brightness.light);
  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final scheme = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: brightness,
    );
    final isDark = brightness == Brightness.dark;

    final textTheme = TextTheme(
      displayLarge: grotesk(700, size: 56, height: 1.05, spacing: -1.5),
      displayMedium: grotesk(700, size: 44, height: 1.08, spacing: -1),
      displaySmall: grotesk(700, size: 36, height: 1.1, spacing: -0.5),
      headlineLarge: grotesk(650, size: 32, height: 1.15, spacing: -0.5),
      headlineMedium: grotesk(650, size: 28, height: 1.18, spacing: -0.25),
      headlineSmall: grotesk(600, size: 24, height: 1.2),
      titleLarge: grotesk(600, size: 20, height: 1.25),
      titleMedium: manrope(700, size: 16, height: 1.3, spacing: 0.1),
      titleSmall: manrope(700, size: 14, height: 1.3, spacing: 0.1),
      bodyLarge: manrope(500, size: 16, height: 1.45),
      bodyMedium: manrope(500, size: 14, height: 1.45),
      bodySmall: manrope(500, size: 12, height: 1.4),
      labelLarge: manrope(700, size: 14, spacing: 0.2),
      labelMedium: manrope(700, size: 12, spacing: 0.3),
      labelSmall: manrope(700, size: 11, spacing: 0.4),
    ).apply(
      bodyColor: scheme.onSurface,
      displayColor: scheme.onSurface,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      textTheme: textTheme,
      scaffoldBackgroundColor:
          isDark ? const Color(0xFF0E1013) : const Color(0xFFF6F7FB),
      splashFactory: InkSparkle.splashFactory,
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: grotesk(650, size: 22, color: scheme.onSurface),
        iconTheme: IconThemeData(color: scheme.onSurface),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: scheme.surfaceContainerLow,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        margin: EdgeInsets.zero,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(64, 56),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          textStyle: manrope(750, size: 16, spacing: 0.2),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(64, 56),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          textStyle: manrope(700, size: 16, spacing: 0.2),
          side: BorderSide(color: scheme.outlineVariant),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          textStyle: manrope(700, size: 14, spacing: 0.2),
        ),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: SegmentedButton.styleFrom(
          textStyle: manrope(650, size: 13),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerLow,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: scheme.primary, width: 2),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        contentTextStyle: manrope(600, size: 14, color: scheme.onInverseSurface),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: scheme.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        showDragHandle: true,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: scheme.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      ),
      chipTheme: ChipThemeData(
        labelStyle: manrope(650, size: 13, color: scheme.onSurface),
        shape: const StadiumBorder(),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      listTileTheme: ListTileThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        titleTextStyle: manrope(700, size: 15, color: scheme.onSurface),
        subtitleTextStyle:
            manrope(550, size: 13, color: scheme.onSurfaceVariant),
      ),
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant.withValues(alpha: 0.5),
        thickness: 1,
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: PredictiveBackPageTransitionsBuilder(),
        },
      ),
    );
  }
}

/// Per-tool identity: gradient + icon, used on cards, headers and results.
class ToolStyle {
  final List<Color> gradient;
  final IconData icon;
  const ToolStyle(this.gradient, this.icon);

  Color get base => gradient.first;
}
