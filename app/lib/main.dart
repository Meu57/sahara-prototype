// lib/main.dart

import 'dart:io'; // Needed to check the platform

import 'package:flutter/material.dart';
import 'package:sahara_app/screens/welcome_screen.dart';
import 'package:sahara_app/services/session_service.dart'; // ✅ Import SessionService
import 'package:sahara_app/theme/app_theme.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart'; // ✅ Import for desktop compatibility

Future<void> main() async {
  // --- DESKTOP DATABASE FIX ---
  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }

  // --- FLUTTER INIT + SESSION WARM-UP ---
  WidgetsFlutterBinding.ensureInitialized();
  await SessionService().getUserId(); // ✅ Warm up session cache

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
