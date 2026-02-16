import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class ScribeTheme {
  // Refined palette with blue accent
  static const Color _sand = Color(0xFFF0F2F5);
  static const Color _sandLight = Color(0xFFF7F8FA);
  static const Color _sandDark = Color(0xFFE4E7EC);
  static const Color _warmGray = Color(0xFF5F6570);
  static const Color _warmGrayLight = Color(0xFF8E939C);
  static const Color _charcoal = Color(0xFF1E2228);
  static const Color _blue = Color(0xFF3B7DD8);
  static const Color _blueLight = Color(0xFFD0E0F5);
  static const Color _cream = Color(0xFFFAFBFD);

  // Dark mode palette
  static const Color _darkBg = Color(0xFF151719);
  static const Color _darkSurface = Color(0xFF1E2024);
  static const Color _darkSurfaceVariant = Color(0xFF282A2E);
  static const Color _darkOnSurface = Color(0xFFDDE1E8);
  static const Color _darkOnSurfaceVariant = Color(0xFF9298A4);
  static const Color _darkBlue = Color(0xFF5A9AEF);

  static TextTheme _buildTextTheme(TextTheme base, Brightness brightness) {
    final color = brightness == Brightness.light ? _charcoal : _darkOnSurface;
    final secondaryColor =
        brightness == Brightness.light ? _warmGray : _darkOnSurfaceVariant;

    return base.copyWith(
      displayLarge: GoogleFonts.instrumentSerif(
        fontSize: 36,
        fontWeight: FontWeight.w400,
        color: color,
      ),
      displayMedium: GoogleFonts.instrumentSerif(
        fontSize: 28,
        fontWeight: FontWeight.w400,
        color: color,
      ),
      headlineLarge: GoogleFonts.instrumentSerif(
        fontSize: 24,
        fontWeight: FontWeight.w400,
        color: color,
      ),
      headlineMedium: GoogleFonts.instrumentSerif(
        fontSize: 20,
        fontWeight: FontWeight.w400,
        color: color,
      ),
      titleLarge: GoogleFonts.inter(
        fontSize: 18,
        fontWeight: FontWeight.w600,
        color: color,
      ),
      titleMedium: GoogleFonts.inter(
        fontSize: 15,
        fontWeight: FontWeight.w600,
        color: color,
      ),
      titleSmall: GoogleFonts.inter(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: color,
      ),
      bodyLarge: GoogleFonts.inter(
        fontSize: 15,
        fontWeight: FontWeight.w400,
        color: color,
        height: 1.6,
      ),
      bodyMedium: GoogleFonts.inter(
        fontSize: 14,
        fontWeight: FontWeight.w400,
        color: color,
        height: 1.5,
      ),
      bodySmall: GoogleFonts.inter(
        fontSize: 12,
        fontWeight: FontWeight.w400,
        color: secondaryColor,
        height: 1.4,
      ),
      labelLarge: GoogleFonts.inter(
        fontSize: 14,
        fontWeight: FontWeight.w500,
        color: color,
      ),
      labelMedium: GoogleFonts.inter(
        fontSize: 12,
        fontWeight: FontWeight.w500,
        color: secondaryColor,
      ),
      labelSmall: GoogleFonts.inter(
        fontSize: 11,
        fontWeight: FontWeight.w500,
        color: secondaryColor,
        letterSpacing: 0.5,
      ),
    );
  }

  static ThemeData light() {
    final base = ThemeData.light(useMaterial3: true);
    final textTheme = _buildTextTheme(base.textTheme, Brightness.light);

    return base.copyWith(
      brightness: Brightness.light,
      scaffoldBackgroundColor: _cream,
      textTheme: textTheme,
      colorScheme: const ColorScheme.light(
        primary: _blue,
        onPrimary: Colors.white,
        primaryContainer: _blueLight,
        onPrimaryContainer: _charcoal,
        secondary: _warmGray,
        onSecondary: Colors.white,
        secondaryContainer: _sandDark,
        onSecondaryContainer: _charcoal,
        tertiary: Color(0xFF6B7B5E),
        tertiaryContainer: Color(0xFFE0E8D6),
        onTertiaryContainer: Color(0xFF2D3628),
        surface: _cream,
        onSurface: _charcoal,
        surfaceContainerLowest: Colors.white,
        surfaceContainerLow: _sandLight,
        surfaceContainer: _sand,
        surfaceContainerHigh: _sandDark,
        onSurfaceVariant: _warmGray,
        outline: Color(0xFFD4CCC0),
        outlineVariant: Color(0xFFE8E0D4),
        error: Color(0xFFBF3B30),
        errorContainer: Color(0xFFF9E0DE),
        onError: Colors.white,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: _cream,
        elevation: 0,
        scrolledUnderElevation: 0,
        titleTextStyle: textTheme.titleLarge,
        iconTheme: const IconThemeData(color: _charcoal),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Color(0xFFE8E0D4), width: 1),
        ),
        margin: EdgeInsets.zero,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: _charcoal,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          textStyle: GoogleFonts.inter(
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: _charcoal,
          side: const BorderSide(color: Color(0xFFD4CCC0)),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          textStyle: GoogleFonts.inter(
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: _charcoal,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: GoogleFonts.inter(
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFD4CCC0)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFD4CCC0)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _blue, width: 1.5),
        ),
        labelStyle: GoogleFonts.inter(
          fontSize: 13,
          fontWeight: FontWeight.w500,
          color: _warmGrayLight,
        ),
        isDense: true,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return _blue;
          return _warmGrayLight;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return _blueLight;
          return _sandDark;
        }),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: _sandLight,
        labelStyle: GoogleFonts.inter(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          color: _warmGray,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: const BorderSide(color: Color(0xFFE8E0D4)),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      ),
      dividerTheme: const DividerThemeData(
        color: Color(0xFFE8E0D4),
        thickness: 1,
        space: 1,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: _charcoal,
        contentTextStyle: GoogleFonts.inter(
          fontSize: 14,
          color: Colors.white,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        behavior: SnackBarBehavior.floating,
      ),
      dialogTheme: DialogThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        backgroundColor: Colors.white,
        titleTextStyle: GoogleFonts.inter(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: _charcoal,
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        color: Colors.white,
        elevation: 4,
        textStyle: GoogleFonts.inter(fontSize: 14, color: _charcoal),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: _blue,
        linearTrackColor: _sandDark,
      ),
      listTileTheme: ListTileThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
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
      colorScheme: const ColorScheme.dark(
        primary: _darkBlue,
        onPrimary: Colors.white,
        primaryContainer: Color(0xFF1E3350),
        onPrimaryContainer: _darkOnSurface,
        secondary: _darkOnSurfaceVariant,
        onSecondary: Colors.white,
        secondaryContainer: _darkSurfaceVariant,
        onSecondaryContainer: _darkOnSurface,
        tertiary: Color(0xFF8B9B7E),
        tertiaryContainer: Color(0xFF2E3828),
        onTertiaryContainer: Color(0xFFD0DCC6),
        surface: _darkBg,
        onSurface: _darkOnSurface,
        surfaceContainerLowest: Color(0xFF141210),
        surfaceContainerLow: Color(0xFF1E1C1A),
        surfaceContainer: _darkSurface,
        surfaceContainerHigh: _darkSurfaceVariant,
        onSurfaceVariant: _darkOnSurfaceVariant,
        outline: Color(0xFF4A4640),
        outlineVariant: Color(0xFF363330),
        error: Color(0xFFE06050),
        errorContainer: Color(0xFF3D2220),
        onError: Colors.white,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: _darkBg,
        elevation: 0,
        scrolledUnderElevation: 0,
        titleTextStyle: textTheme.titleLarge,
        iconTheme: const IconThemeData(color: _darkOnSurface),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: _darkSurface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Color(0xFF363330), width: 1),
        ),
        margin: EdgeInsets.zero,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: _darkOnSurface,
          foregroundColor: _darkBg,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          textStyle: GoogleFonts.inter(
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: _darkOnSurface,
          side: const BorderSide(color: Color(0xFF4A4640)),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          textStyle: GoogleFonts.inter(
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: _darkOnSurface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: GoogleFonts.inter(
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: _darkSurfaceVariant,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF4A4640)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF4A4640)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _darkBlue, width: 1.5),
        ),
        labelStyle: GoogleFonts.inter(
          fontSize: 13,
          fontWeight: FontWeight.w500,
          color: _darkOnSurfaceVariant,
        ),
        isDense: true,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return _darkBlue;
          return _darkOnSurfaceVariant;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const Color(0xFF1E3350);
          }
          return _darkSurfaceVariant;
        }),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: _darkSurfaceVariant,
        labelStyle: GoogleFonts.inter(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          color: _darkOnSurfaceVariant,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: const BorderSide(color: Color(0xFF363330)),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      ),
      dividerTheme: const DividerThemeData(
        color: Color(0xFF363330),
        thickness: 1,
        space: 1,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: _darkOnSurface,
        contentTextStyle: GoogleFonts.inter(
          fontSize: 14,
          color: _darkBg,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        behavior: SnackBarBehavior.floating,
      ),
      dialogTheme: DialogThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        backgroundColor: _darkSurface,
        titleTextStyle: GoogleFonts.inter(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: _darkOnSurface,
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        color: _darkSurface,
        elevation: 4,
        textStyle: GoogleFonts.inter(fontSize: 14, color: _darkOnSurface),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: _darkBlue,
        linearTrackColor: _darkSurfaceVariant,
      ),
      listTileTheme: ListTileThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      ),
    );
  }

  // Sidebar colors (not part of standard ColorScheme)
  static Color sidebarBackground(BuildContext context) {
    return Theme.of(context).brightness == Brightness.light
        ? _sandDark
        : _darkSurface;
  }

  static Color sidebarSelectedItem(BuildContext context) {
    return Theme.of(context).brightness == Brightness.light
        ? const Color(0xFFDDD4C6)
        : _darkSurfaceVariant;
  }
}
