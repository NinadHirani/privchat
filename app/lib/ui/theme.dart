import 'package:flutter/material.dart';

class AppTheme {
  static const teal = Color(0xFF008069);
  static const tealDark = Color(0xFF1F2C34);
  static const green = Color(0xFF25D366);
  static const bubbleOut = Color(0xFFD9FDD3);
  static const bubbleOutDark = Color(0xFF005C4B);
  static const bubbleIn = Colors.white;
  static const bubbleInDark = Color(0xFF1F2C34);
  static const chatBg = Color(0xFFEFEAE2);
  static const chatBgDark = Color(0xFF0B141A);
  static const tickBlue = Color(0xFF53BDEB);

  static ThemeData get light => ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: teal, primary: teal, secondary: green),
        appBarTheme: const AppBarTheme(backgroundColor: teal, foregroundColor: Colors.white, elevation: 0),
        floatingActionButtonTheme: const FloatingActionButtonThemeData(backgroundColor: green, foregroundColor: Colors.white),
        tabBarTheme: const TabBarThemeData(labelColor: Colors.white, unselectedLabelColor: Colors.white70, indicatorColor: Colors.white),
      );

  static ThemeData get dark => ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(seedColor: teal, brightness: Brightness.dark, primary: green, secondary: green),
        scaffoldBackgroundColor: const Color(0xFF111B21),
        appBarTheme: const AppBarTheme(backgroundColor: tealDark, foregroundColor: Colors.white, elevation: 0),
        floatingActionButtonTheme: const FloatingActionButtonThemeData(backgroundColor: green, foregroundColor: Colors.black),
        tabBarTheme: const TabBarThemeData(labelColor: green, unselectedLabelColor: Colors.white60, indicatorColor: green),
      );

  static bool isDark(BuildContext c) => Theme.of(c).brightness == Brightness.dark;
}
