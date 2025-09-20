// lib/services/session_service.dart

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'package:logger/logger.dart';

final logger = Logger();


class SessionService {
  // Singleton boilerplate
  static final SessionService _instance = SessionService._internal();
  factory SessionService() => _instance;
  SessionService._internal();

  // Key used in SharedPreferences
  static const String _keyUserId = 'anonymous_user_id';

  // In-memory cache for speed
  String? _userId;

  // A guard to prevent multiple simultaneous initializations (race condition)
  Future<void>? _initFuture;

  /// Simple cross-screen notifier: increment .value to signal a refresh is needed.
  static final ValueNotifier<int> journeyRefresh = ValueNotifier<int>(0);

  /// Returns the cached userId; if not cached, loads from disk.
  /// If no ID exists, generates a new one, persists it, and caches it.
  Future<String> getUserId() async {
    // Fast path: ID is already loaded in memory.
    if (_userId != null) return _userId!;

    // If another part of the app is already initializing the ID, wait for it.
    if (_initFuture != null) {
      await _initFuture;
      return _userId!;
    }

    // Start the one-time initialization.
    _initFuture = _loadOrCreateUserId();
    await _initFuture;

    // Reset the future so it can be run again if needed.
    _initFuture = null;
    return _userId!;
  }

  /// Saves an externally-provided userId (e.g., from the server).
  Future<void> setUserId(String id) async {
    _userId = id; // Update the in-memory cache
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyUserId, id);
    logger.i('SessionService: Saved server-provided userId: $id');  }

  // Internal helper that does the actual work.
  Future<void> _loadOrCreateUserId() async {
    final prefs = await SharedPreferences.getInstance();
    final storedId = prefs.getString(_keyUserId);

    if (storedId != null && storedId.isNotEmpty) {
      _userId = storedId;
    } else {
      // No stored ID — create one, persist it, and cache it.
      final newId =  Uuid().v4();
      _userId = newId;
      await prefs.setString(_keyUserId, newId);
      logger.i('SessionService: Created new anonymous id: $newId');
    }
  }

  /// Optional helper for testing.
  Future<void> clearUserIdForTesting() async {
    _userId = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyUserId);
  }
}