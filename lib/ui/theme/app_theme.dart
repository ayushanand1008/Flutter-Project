import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  static const Color backgroundCream = Color(0xFFFDE3C6);
  static const Color earthyBrown = Color(0xFF5D4037);
  static const Color burntOrange = Color(0xFFE64A19);
  static const Color hazyPink = Color(0xFFF48FB1); // For ripples

  static ThemeData get theme {
    return ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: burntOrange,
        surface: backgroundCream,
        primary: burntOrange,
        onPrimary: Colors.white,
        secondary: earthyBrown,
        onSurface: earthyBrown,
      ),
      scaffoldBackgroundColor: backgroundCream,
      useMaterial3: true,
      
      textTheme: GoogleFonts.nunitoTextTheme().apply(
        bodyColor: earthyBrown,
        displayColor: earthyBrown,
      ).copyWith(
        displayLarge: GoogleFonts.sniglet(color: earthyBrown),
        displayMedium: GoogleFonts.sniglet(color: earthyBrown),
        displaySmall: GoogleFonts.sniglet(color: earthyBrown),
        headlineLarge: GoogleFonts.sniglet(color: earthyBrown),
        headlineMedium: GoogleFonts.sniglet(color: earthyBrown),
        titleLarge: GoogleFonts.sniglet(color: earthyBrown),
      ),
      
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: earthyBrown),
        titleTextStyle: GoogleFonts.sniglet(
          color: earthyBrown,
          fontSize: 24,
        ),
      ),
      
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: burntOrange,
          foregroundColor: Colors.white,
          textStyle: GoogleFonts.sniglet(fontSize: 16),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      
      drawerTheme: const DrawerThemeData(
        backgroundColor: backgroundCream,
      ),
      
      iconTheme: const IconThemeData(
        color: earthyBrown,
      ),
    );
  }
}
