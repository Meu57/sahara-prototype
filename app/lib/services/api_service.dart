// lib/services/api_service.dart
// Definitive version: Secure, Web-Compatible, and Robust.

import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:logger/logger.dart';
import 'package:sahara_app/models/article.dart';
import 'package:sahara_app/models/journal_entry.dart';
import 'package:sahara_app/services/session_service.dart';

// This is a clean way to handle our build-time secrets.
class AppConfig {
  /// The API Key must be supplied when you run the app like this:
  /// flutter run --dart-define=SAHARA_API_KEY=your_key_here
  static const String apiKey = String.fromEnvironment('SAHARA_API_KEY', defaultValue: '');
}

class ApiService {
  // Private constructor to prevent instantiation
  ApiService._();

  // Our secure, public-facing API Gateway URL
  static const String _baseUrl = 'https://sahara-gateway-zvwoow5.an.gateway.dev';

  static final http.Client _client = http.Client();
  static final Logger _logger = Logger();

  // This private helper creates our secure headers for every single request.
  // It includes the "fail-fast" safety check your friend recommended.
  static Map<String, String> get _secureHeaders {
    final key = AppConfig.apiKey;
    if (key.isEmpty) {
      // This will cause a clear error during development if you forget the --dart-define flag.
      throw Exception('FATAL ERROR: SAHARA_API_KEY was not provided. Please run with --dart-define=SAHARA_API_KEY=your-key');
    }
    return {
      'Content-Type': 'application/json; charset=UTF-8',
      'x-api-key': key,
    };
  }
  
  // This is a safer way to handle potential non-JSON error responses from the server.
  static dynamic _handleResponse(http.Response response) {
    if (response.statusCode >= 200 && response.statusCode < 300) {
      if (response.body.isEmpty) return null;
      try {
        return jsonDecode(response.body);
      } catch (e) {
        // If the server returns something that isn't JSON, return the raw text.
        return response.body; 
      }
    } else {
      String errorMessage = 'API Error ${response.statusCode}';
      try {
          final parsed = jsonDecode(response.body);
          if (parsed is Map) {
              errorMessage = parsed['error']?.toString() ?? parsed['message']?.toString() ?? response.body;
          }
      } catch (_) {}
      throw Exception(errorMessage);
    }
  }

  // --- PUBLIC API METHODS ---

  static Future<String> sendMessage(String message, {String? userId}) async {
    try {
      final localUserId = userId ?? await SessionService().getUserId();
      final payload = {'message': message, 'userId': localUserId};
      
      final response = await _client.post(
          Uri.parse('$_baseUrl/chat'),
          headers: _secureHeaders, 
          body: jsonEncode(payload)
      ).timeout(const Duration(seconds: 60));

      final data = _handleResponse(response) as Map<String, dynamic>;

      // Handle the server providing a userId for the first time.
      if (data['userId'] is String) {
          await SessionService().setUserId(data['userId']);
      }
      return data['reply'] ?? "Sorry, no valid reply was found.";
    } catch (e) {
      _logger.e('sendMessage failed: $e');
      return "Sorry, an unexpected error occurred. Please try again.";
    }
  }
  
  static Future<List<Article>> getResources() async {
    try {
      final response = await _client.get(
        Uri.parse('$_baseUrl/resources'), 
        headers: _secureHeaders
      );
      final data = _handleResponse(response) as List<dynamic>;
      // We will assume the Article model has a .fromJson constructor.
      // return data.map((json) => Article.fromJson(json)).toList();
      
      // Let's use the old, safer mapping for now.
      return data.map((json) {
        final item = json as Map<String, dynamic>;
        return Article(
          title: (item['title'] as String?) ?? '',
          snippet: (item['snippet'] as String?) ?? '',
          content: (item['content'] as String?) ?? (item['snippet'] as String?) ?? '',
          icon: Icons.article_outlined,
        );
      }).toList();

    } catch (e) {
      _logger.e('getResources failed: $e');
      return []; // Return an empty list on failure
    }
  }

  static Future<void> syncJournalEntry(String userId, JournalEntry entry) async {
    try {
      final payload = {'userId': userId, 'entry': entry.toMap()};
      await _client.post(
        Uri.parse('$_baseUrl/journal/sync'), 
        headers: _secureHeaders, 
        body: jsonEncode(payload)
      );
      _logger.i('Journal entry sync successful.');
    } catch (e) {
      _logger.e('syncJournalEntry failed: $e');
    }
  }
}