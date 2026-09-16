import 'package:flutter/material.dart';

class AppTheme {
  // Ana renk (seed color)
  static const Color seedColor = Color.fromARGB(117, 41, 202, 44); // mustard

  // Palette extracted from reference image
  static const Color plumDark = Color.fromARGB(255, 0, 0, 0);
  static const Color plumLight = Colors.white;
  static const Color lavender = Color(0xFFA892C7); // light purple
  static const Color mustard = seedColor; // golden mustard
  static const Color orange = Color(0xFFF19A1A); // warm orange
  static const Color coral = Color(0xFFE74B58); // coral red

  // Ekstra renkler
  static const Color accent = Color(0xFFFF6F61);
  static const Color success = Color(0xFF4CAF50);
  static const Color warning = Color(0xFFFFC107);
  static const Color error = Color(0xFFF44336);

  // Yazı tipi (önce pubspec.yaml'da tanımlamalısın)
  static const String fontFamily = 'Roboto';

  // Light Theme
  static ThemeData lightTheme = ThemeData(
    useMaterial3: true,
    fontFamily: fontFamily,
    colorScheme:
        ColorScheme.fromSeed(
          seedColor: mustard,
          brightness: Brightness.light,
        ).copyWith(
          primary: mustard,
          secondary: orange,
          tertiary: coral,
          surface: plumLight,
          onSurface: const Color(0xFF1E1320),
        ),
    textTheme: const TextTheme(
      headlineLarge: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
      headlineMedium: TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
      bodyLarge: TextStyle(fontSize: 16),
      bodyMedium: TextStyle(fontSize: 14, color: Color(0x89000000)),
    ),
    scaffoldBackgroundColor: Colors.white,
    appBarTheme: const AppBarTheme(centerTitle: true, elevation: 0),
    dividerTheme: const DividerThemeData(
      color: Color(0x1A000000),
      thickness: 0.5,
      space: 1,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
  );

  // Dark Theme
  static ThemeData darkTheme = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    fontFamily: fontFamily,
    colorScheme:
        ColorScheme.fromSeed(
          seedColor: mustard,
          brightness: Brightness.dark,
        ).copyWith(
          primary: mustard,
          secondary: orange,
          tertiary: coral,
          surface: plumDark,
          onSurface: Colors.white,
        ),
    textTheme: const TextTheme(
      headlineLarge: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
      headlineMedium: TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
      bodyLarge: TextStyle(fontSize: 16, color: Colors.white),
      bodyMedium: TextStyle(fontSize: 14, color: Colors.white70),
    ),
    scaffoldBackgroundColor: plumDark,
    appBarTheme: const AppBarTheme(centerTitle: true, elevation: 0),
    dividerTheme: const DividerThemeData(
      color: Color(0x1FFFFFFF),
      thickness: 0.5,
      space: 1,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
  );
}

/// Lightweight theme mode bridge without changing any colors.
/// Main uses ThemeBridge.themeMode to rebuild MaterialApp.
class ThemeBridge {
  static final ValueNotifier<ThemeMode> themeMode = ValueNotifier<ThemeMode>(
    ThemeMode.system,
  );
}
