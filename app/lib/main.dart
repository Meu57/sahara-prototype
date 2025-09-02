// lib/main.dart (Definitive, Platform-Aware Version)

import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:sahara_app/screens/welcome_screen.dart';
import 'package:sahara_app/services/session_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sahara_app/theme/app_theme.dart';

Future<void> main() async {
  // 1. Make sure Flutter binding is initialized first. This is a best practice.
  WidgetsFlutterBinding.ensureInitialized();

  // 2. This is the critical fix: Only run desktop-specific database 
  //    initialization when NOT running in a browser.
  if (!kIsWeb) {
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }
  }

  // 3. Warm up the session cache.
  await SessionService().getUserId();

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