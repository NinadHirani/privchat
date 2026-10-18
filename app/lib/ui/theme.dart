import 'package:flutter/material.dart';

class AppTheme {
  // Signature Palette: Cadet Grey + Mustard Brown + Warm Ivory
  static const cadetGrey = Color(0xFF8F9FA9);
  static const cadetGreyLight = Color(0xFFA5B4BD);
  static const cadetGreyDark = Color(0xFF1C2429);
  static const cadetGreyDeeper = Color(0xFF131A1E);

  static const mustardBrown = Color(0xFF9E6B20);
  static const mustardBrownLight = Color(0xFFB57D29);
  static const mustardBrownDark = Color(0xFF7E5214);
  static const amberAccent = Color(0xFFD49B38);

  static const warmIvory = Color(0xFFFFFDF5);
  static const warmIvoryDark = Color(0xFF263238);
  static const deepCarbon = Color(0xFF1A1D20);

  // Status & indicators
  static const tickBlue = Color(0xFF53BDEB);
  static const onlineGreen = Color(0xFF2EC4B6);

  // Aliases for backward compatibility
  static const teal = mustardBrown;
  static const tealDark = cadetGreyDark;
  static const green = amberAccent;
  static const bubbleOut = mustardBrown;
  static const bubbleOutDark = mustardBrownDark;
  static const bubbleIn = warmIvory;
  static const bubbleInDark = warmIvoryDark;
  static const chatBg = cadetGrey;
  static const chatBgDark = cadetGreyDark;

  static ThemeData get light => ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        colorScheme: ColorScheme.fromSeed(
          seedColor: mustardBrown,
          primary: mustardBrown,
          secondary: amberAccent,
          surface: Colors.white,
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: const Color(0xFFF4F6F8),
        appBarTheme: const AppBarTheme(
          backgroundColor: cadetGreyDark,
          foregroundColor: Colors.white,
          elevation: 0,
          centerTitle: false,
        ),
        drawerTheme: const DrawerThemeData(
          backgroundColor: Colors.white,
        ),
        floatingActionButtonTheme: const FloatingActionButtonThemeData(
          backgroundColor: mustardBrown,
          foregroundColor: Colors.white,
        ),
      );

  static ThemeData get dark => ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: mustardBrown,
          brightness: Brightness.dark,
          primary: amberAccent,
          secondary: mustardBrownLight,
          surface: cadetGreyDark,
        ),
        scaffoldBackgroundColor: cadetGreyDeeper,
        appBarTheme: const AppBarTheme(
          backgroundColor: cadetGreyDark,
          foregroundColor: Colors.white,
          elevation: 0,
          centerTitle: false,
        ),
        drawerTheme: const DrawerThemeData(
          backgroundColor: cadetGreyDark,
        ),
        floatingActionButtonTheme: const FloatingActionButtonThemeData(
          backgroundColor: amberAccent,
          foregroundColor: Colors.black,
        ),
      );

  static bool isDark(BuildContext c) => Theme.of(c).brightness == Brightness.dark;
}
