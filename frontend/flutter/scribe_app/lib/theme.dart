import 'package:flutter/material.dart';

class ScribeTheme {
  static const Color _lightBg = Color(0xFF1A1D23);
  static const Color _lightSurface = Color(0xFF21252D);
  static const Color _lightSurfaceLow = Color(0xFF2A303A);
  static const Color _lightSurfaceHigh = Color(0xFF343C49);
  static const Color _lightText = Color(0xFFF6F8FB);
  static const Color _lightTextMuted = Color(0xFFAAB2BF);
  static const Color _lightPrimary = Color(0xFFCCD3DD);
  static const Color _lightPrimaryContainer = Color(0xFF3B4453);

  static const Color _darkBg = Color(0xFF111318);
  static const Color _darkSurface = Color(0xFF181C22);
  static const Color _darkSurfaceLow = Color(0xFF20262F);
  static const Color _darkSurfaceHigh = Color(0xFF2B3340);
  static const Color _darkText = Color(0xFFF6F8FB);
  static const Color _darkTextMuted = Color(0xFFA7AFBC);
  static const Color _darkPrimary = Color(0xFFD1D7E0);
  static const Color _darkPrimaryContainer = Color(0xFF3D4656);

  static const List<String> _sansFallback = [
    '.SF Pro Text',
    'SF Pro Text',
    'Inter',
    'Segoe UI',
    'Roboto',
    'Helvetica Neue',
    'Arial',
  ];

  static const List<String> _monoFallback = [
    '.SF Mono',
    'SF Mono',
    'JetBrains Mono',
    'Consolas',
    'monospace',
  ];

  static TextStyle _textStyle(
    double size,
    FontWeight weight,
    Color color, {
    double? height,
    double? letterSpacing,
  }) {
    return TextStyle(
      fontSize: size,
      fontWeight: weight,
      color: color,
      height: height,
      letterSpacing: letterSpacing,
      fontFamilyFallback: _sansFallback,
    );
  }

  static TextTheme _buildTextTheme(TextTheme base, Brightness brightness) {
    final color = brightness == Brightness.light ? _lightText : _darkText;
    final secondaryColor = brightness == Brightness.light
        ? _lightTextMuted
        : _darkTextMuted;

    return base.copyWith(
      displayLarge: _textStyle(34, FontWeight.w700, color, height: 1.12),
      displayMedium: _textStyle(28, FontWeight.w700, color, height: 1.14),
      headlineLarge: _textStyle(24, FontWeight.w700, color, height: 1.2),
      headlineMedium: _textStyle(20, FontWeight.w700, color, height: 1.25),
      titleLarge: _textStyle(18, FontWeight.w600, color, height: 1.25),
      titleMedium: _textStyle(15, FontWeight.w600, color, height: 1.3),
      titleSmall: _textStyle(13, FontWeight.w600, color, height: 1.3),
      bodyLarge: _textStyle(15, FontWeight.w400, color, height: 1.5),
      bodyMedium: _textStyle(14, FontWeight.w400, color, height: 1.45),
      bodySmall: _textStyle(12, FontWeight.w400, secondaryColor, height: 1.4),
      labelLarge: _textStyle(14, FontWeight.w600, color, height: 1.3),
      labelMedium: _textStyle(12, FontWeight.w600, secondaryColor, height: 1.3),
      labelSmall: _textStyle(
        11,
        FontWeight.w600,
        secondaryColor,
        height: 1.25,
        letterSpacing: 0.2,
      ),
    );
  }

  static ThemeData light() {
    final base = ThemeData.light(useMaterial3: true);
    final textTheme = _buildTextTheme(base.textTheme, Brightness.light);

    return base.copyWith(
      brightness: Brightness.light,
      scaffoldBackgroundColor: _lightBg,
      textTheme: textTheme,
      primaryTextTheme: textTheme,
      colorScheme: const ColorScheme.light(
        primary: _lightPrimary,
        onPrimary: Color(0xFF111419),
        primaryContainer: _lightPrimaryContainer,
        onPrimaryContainer: _lightText,
        secondary: _lightTextMuted,
        onSecondary: _lightText,
        secondaryContainer: _lightSurfaceHigh,
        onSecondaryContainer: _lightText,
        tertiary: _lightPrimary,
        tertiaryContainer: _lightPrimaryContainer,
        onTertiaryContainer: _lightText,
        surface: _lightBg,
        onSurface: _lightText,
        surfaceContainerLowest: _lightSurface,
        surfaceContainerLow: _lightSurfaceLow,
        surfaceContainer: _lightSurfaceLow,
        surfaceContainerHigh: _lightSurfaceHigh,
        onSurfaceVariant: _lightTextMuted,
        outline: Color(0xFF4B5564),
        outlineVariant: Color(0xFF3B4453),
        error: Color(0xFFFF8E98),
        errorContainer: Color(0xFF4D2D32),
        onError: Colors.white,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: _lightBg,
        elevation: 0,
        scrolledUnderElevation: 0,
        titleTextStyle: textTheme.titleLarge,
        iconTheme: const IconThemeData(color: _lightText),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: _lightSurface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: const BorderSide(color: Color(0xFF3B4453), width: 1),
        ),
        margin: EdgeInsets.zero,
      ),
      textSelectionTheme: const TextSelectionThemeData(
        cursorColor: _lightPrimary,
        selectionColor: Color(0x446C7687),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: _lightPrimary,
          foregroundColor: const Color(0xFF111419),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          textStyle: textTheme.labelLarge,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: _lightText,
          side: const BorderSide(color: Color(0xFF4B5564)),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          textStyle: textTheme.labelLarge,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: _lightPrimary,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          textStyle: textTheme.labelLarge,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: _lightSurface,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 12,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFF4B5564)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFF4B5564)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: _lightPrimary, width: 1.5),
        ),
        labelStyle: textTheme.labelMedium,
        isDense: true,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return _lightPrimary;
          return _lightTextMuted;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return _lightPrimaryContainer;
          }
          return _lightSurfaceHigh;
        }),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: _lightSurfaceLow,
        labelStyle: textTheme.labelMedium,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(9),
          side: const BorderSide(color: Color(0xFF3B4453)),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      ),
      dividerTheme: const DividerThemeData(
        color: Color(0xFF3B4453),
        thickness: 1,
        space: 1,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: _lightSurfaceHigh,
        contentTextStyle: textTheme.bodyMedium,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        behavior: SnackBarBehavior.floating,
      ),
      dialogTheme: DialogThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        backgroundColor: _lightSurface,
        titleTextStyle: textTheme.titleLarge,
      ),
      popupMenuTheme: PopupMenuThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        color: _lightSurface,
        elevation: 4,
        textStyle: textTheme.bodyMedium,
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: _lightPrimary,
        linearTrackColor: _lightSurfaceHigh,
      ),
      listTileTheme: ListTileThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      ),
    );
  }

  static ThemeData dark() {
    final base = ThemeData.dark(useMaterial3: true);
    final textTheme = _buildTextTheme(base.textTheme, Brightness.dark);

    return base.copyWith(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: _darkBg,
      textTheme: textTheme,
      primaryTextTheme: textTheme,
      colorScheme: const ColorScheme.dark(
        primary: _darkPrimary,
        onPrimary: Color(0xFF111419),
        primaryContainer: _darkPrimaryContainer,
        onPrimaryContainer: _darkText,
        secondary: _darkTextMuted,
        onSecondary: _darkText,
        secondaryContainer: _darkSurfaceHigh,
        onSecondaryContainer: _darkText,
        tertiary: _darkPrimary,
        tertiaryContainer: _darkPrimaryContainer,
        onTertiaryContainer: _darkText,
        surface: _darkBg,
        onSurface: _darkText,
        surfaceContainerLowest: _darkSurface,
        surfaceContainerLow: _darkSurfaceLow,
        surfaceContainer: _darkSurface,
        surfaceContainerHigh: _darkSurfaceHigh,
        onSurfaceVariant: _darkTextMuted,
        outline: Color(0xFF4D5767),
        outlineVariant: Color(0xFF3D4656),
        error: Color(0xFFFF8B8B),
        errorContainer: Color(0xFF402628),
        onError: Colors.white,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: _darkBg,
        elevation: 0,
        scrolledUnderElevation: 0,
        titleTextStyle: textTheme.titleLarge,
        iconTheme: const IconThemeData(color: _darkText),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: _darkSurface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: const BorderSide(color: Color(0xFF3D4656), width: 1),
        ),
        margin: EdgeInsets.zero,
      ),
      textSelectionTheme: const TextSelectionThemeData(
        cursorColor: _darkPrimary,
        selectionColor: Color(0x446C7687),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: _darkPrimary,
          foregroundColor: const Color(0xFF111419),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          textStyle: textTheme.labelLarge,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: _darkText,
          side: const BorderSide(color: Color(0xFF4D5767)),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          textStyle: textTheme.labelLarge,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: _darkPrimary,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          textStyle: textTheme.labelLarge,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: _darkSurfaceLow,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 12,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFF4D5767)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFF4D5767)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: _darkPrimary, width: 1.5),
        ),
        labelStyle: textTheme.labelMedium,
        isDense: true,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return _darkPrimary;
          return _darkTextMuted;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return _darkPrimaryContainer;
          }
          return _darkSurfaceHigh;
        }),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: _darkSurfaceLow,
        labelStyle: textTheme.labelMedium,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(9),
          side: const BorderSide(color: Color(0xFF3D4656)),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      ),
      dividerTheme: const DividerThemeData(
        color: Color(0xFF3D4656),
        thickness: 1,
        space: 1,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: _darkSurfaceHigh,
        contentTextStyle: textTheme.bodyMedium,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        behavior: SnackBarBehavior.floating,
      ),
      dialogTheme: DialogThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        backgroundColor: _darkSurface,
        titleTextStyle: textTheme.titleLarge,
      ),
      popupMenuTheme: PopupMenuThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        color: _darkSurface,
        elevation: 4,
        textStyle: textTheme.bodyMedium,
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: _darkPrimary,
        linearTrackColor: _darkSurfaceHigh,
      ),
      listTileTheme: ListTileThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      ),
    );
  }

  static Color sidebarBackground(BuildContext context) {
    return Theme.of(context).brightness == Brightness.light
        ? _lightSurfaceLow
        : _darkSurfaceLow;
  }

  static Color sidebarSelectedItem(BuildContext context) {
    return Theme.of(context).brightness == Brightness.light
        ? _lightPrimaryContainer
        : _darkPrimaryContainer;
  }

  static TextStyle monoStyle(
    BuildContext context, {
    double fontSize = 12,
    Color? color,
    FontWeight fontWeight = FontWeight.w500,
  }) {
    final theme = Theme.of(context);
    return TextStyle(
      fontSize: fontSize,
      fontWeight: fontWeight,
      color: color ?? theme.colorScheme.onSurfaceVariant,
      fontFamilyFallback: _monoFallback,
    );
  }
}
