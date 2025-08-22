// lib/main.dart (UPDATED FOR DESKTOP COMPATIBILITY)

import 'dart:io'; // Needed to check the platform

import 'package:flutter/material.dart';
import 'package:sahara_app/screens/welcome_screen.dart';
import 'package:sahara_app/theme/app_theme.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart'; // Import the new package

Future<void> main() async {
  // --- THIS IS THE FIX ---
  // This is the required initialization for sqflite on desktop platforms.
  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    // Initialize the ffi factory
    sqfliteFfiInit();
    // Change the default factory for sqflite to use the ffi factory
    databaseFactory = databaseFactoryFfi;
  }
  // We also need to ensure that the Flutter app is initialized before running.
  WidgetsFlutterBinding.ensureInitialized();
  // --- END OF FIX ---

  runApp(const SaharaApp());
}

class SaharaApp extends StatelessWidget {
  const SaharaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Sahara',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      home: const WelcomeScreen(),
    );
  }
}