// lib/theme/app_theme.dart (Built from user-verified solution)

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  static ThemeData get lightTheme {
    const seedColor = Color(0xFFA3D7FF); // Our Soft Blue

    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: seedColor,
        background: const Color(0xFFF6F5EE), 
        secondary: const Color(0xFFB5EAD7),  
        surface: Colors.white,
      ),
      
      textTheme: GoogleFonts.muktaTextTheme(),
      
      // --- THIS IS YOUR VERIFIED FIX ---
      // We are now using CardThemeData as you correctly identified.
      cardTheme: const CardThemeData(
        elevation: 1.0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(12.0)),
        ),
        color: Colors.white,
        surfaceTintColor: Colors.transparent,
      ),
      
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: seedColor,
          foregroundColor: Colors.black87,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10.0),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        ),
      ),
      
      appBarTheme: const AppBarTheme(
        backgroundColor: seedColor,
        foregroundColor: Colors.black87,
        elevation: 0,
        centerTitle: true,
      ),
    );
  }
}