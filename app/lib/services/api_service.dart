// lib/services/api_service.dart

import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:logger/logger.dart';
import 'package:sahara_app/models/article.dart';
import 'package:sahara_app/models/journal_entry.dart';
import 'package:sahara_app/models/action_item.dart';
import 'package:sahara_app/services/session_service.dart';



class AppConfig {
  static const String apiKey =
      String.fromEnvironment('SAHARA_API_KEY', defaultValue: '');

  static const String baseUrl = String.fromEnvironment(
    'SAHARA_BASE_URL',
    defaultValue: 'https://sahara-gateway-zvwoow5.an.gateway.dev',
  );
}

class ApiService {
  ApiService._();

  static final String _baseUrl = AppConfig.baseUrl;
  static final http.Client _client = http.Client();
  static final Logger _logger = Logger();

  

  /// Update an existing journal entry by id. Returns true on success.
static Future<bool> updateJournalEntry(String userId, JournalEntry entry) async {
  try {
    // Make a copy map — ensure `id` is not required in body (backend uses path param)
    final body = entry.toMap(); // adjust if your model's toMap includes 'id' remove it
    body.remove('id');

    final response = await _client.put(
      Uri.parse('$_baseUrl/users/$userId/entries/${entry.id}'),
      headers: _secureHeaders,
      body: jsonEncode(body),
    ).timeout(const Duration(seconds: 10));

    _handleResponse(response); // will throw on non-2xx
    _logger.i('Journal entry update successful: ${entry.id}');
    return true;
  } catch (e) {
    _logger.e('updateJournalEntry failed: $e');
    return false;
  }
}


  static Map<String, String> get _secureHeaders {
    final key = AppConfig.apiKey;
    if (key.isEmpty) {
      throw Exception(
          'FATAL ERROR: SAHARA_API_KEY was not provided. Please run with --dart-define=SAHARA_API_KEY=your-key');
    }
    return {
      'Content-Type': 'application/json; charset=UTF-8',
      'x-api-key': key,
    };
  }

  static dynamic _handleResponse(http.Response response) {
    if (response.statusCode >= 200 && response.statusCode < 300) {
      if (response.body.isEmpty) return null;
      try {
        return jsonDecode(response.body);
      } catch (e) {
        return response.body;
      }
    } else {
      String errorMessage = 'API Error ${response.statusCode}';
      try {
        final parsed = jsonDecode(response.body);
        if (parsed is Map) {
          errorMessage = parsed['error']?.toString() ??
              parsed['message']?.toString() ??
              response.body;
        }
      } catch (_) {}
      throw Exception(errorMessage);
    }
  }

  static Future<Map<String, dynamic>> sendMessage(String message, {String? userId}) async {
    try {
      final localUserId = userId ?? await SessionService().getUserId();
      final payload = {'message': message, 'userId': localUserId};

      final response = await _client.post(
        Uri.parse('$_baseUrl/chat'),
        headers: _secureHeaders,
        body: jsonEncode(payload),
      ).timeout(const Duration(seconds: 60));

      final data = _handleResponse(response) as Map<String, dynamic>;

      if (data['userId'] is String) {
        await SessionService().setUserId(data['userId']);
      }

      return data;
    } catch (e) {
      _logger.e('sendMessage failed: $e');
      return {'reply': "Sorry, an unexpected error occurred. Please try again."};
    }
  }

  static Future<List<Article>> getResources() async {
    try {
      final response = await _client.get(
        Uri.parse('$_baseUrl/resources'),
        headers: _secureHeaders,
      );

      final data = _handleResponse(response) as List<dynamic>;

      return data.map((json) {
        final item = json as Map<String, dynamic>;
        final String id = (item['id'] ?? item['resourceId'] ?? item['slug'] ?? item['title'])?.toString() ?? '';

        return Article(
          id: id,
          title: item['title'] ?? '',
          snippet: item['snippet'] ?? '',
          content: item['content'] ?? item['snippet'] ?? '',
          icon: Icons.article_outlined,
        );
      }).toList();
    } catch (e) {
      _logger.e('getResources failed: $e');
      return [];
    }
  }

  /// ✅ Updated: Sync journal entry and return success/failure
  static Future<bool> syncJournalEntry(String userId, JournalEntry entry) async {
    try {
      final payload = {'userId': userId, 'entry': entry.toMap()};
      final response = await _client.post(
        Uri.parse('$_baseUrl/journal/sync'),
        headers: _secureHeaders,
        body: jsonEncode(payload),
      ).timeout(const Duration(seconds: 10));

      _handleResponse(response); // throws on error
      _logger.i('Journal entry sync successful.');
      return true;
    } catch (e) {
      _logger.e('syncJournalEntry failed: $e');
      return false;
    }
  }

  /// ✅ New: Fetch journal entries for a user
  static Future<List<JournalEntry>> getJournalEntries(String userId) async {
    try {
      final response = await _client.get(
        Uri.parse('$_baseUrl/users/$userId/entries'),
        headers: _secureHeaders,
      ).timeout(const Duration(seconds: 10));

      final data = _handleResponse(response) as List<dynamic>;
      return data.map((m) => JournalEntry.fromMap(m as Map<String, dynamic>)).toList();
    } catch (e) {
      _logger.e('getJournalEntries failed: $e');
      return [];
    }
  }

  // ✅ Existing journey methods remain unchanged
  static Future<List<ActionItem>> getJourneyItems(String userId) async {
    final response = await _client.get(
      Uri.parse('$_baseUrl/users/$userId/journey'),
      headers: _secureHeaders,
    );
    final data = _handleResponse(response) as List<dynamic>;
    return data.map((json) => ActionItem.fromJson(json as Map<String, dynamic>)).toList();
  }

  static Future<void> addJourneyItem(String userId, ActionItem item) async {
    final payload = {
      'title': item.title,
      'description': item.description,
      'resourceId': item.resourceId,
      'isCompleted': item.isCompleted,
      'dateAdded': item.dateAdded.toIso8601String(),
    };
    await _client.post(
      Uri.parse('$_baseUrl/users/$userId/journey'),
      headers: _secureHeaders,
      body: jsonEncode(payload),
    );
  }

  static Future<void> updateActionItem(String userId, ActionItem item) async {
    final payload = {
      'title': item.title,
      'description': item.description,
      'resourceId': item.resourceId,
      'isCompleted': item.isCompleted,
      'dateAdded': item.dateAdded.toIso8601String(),
    };
    await _client.put(
      Uri.parse('$_baseUrl/users/$userId/journey/${item.id}'),
      headers: _secureHeaders,
      body: jsonEncode(payload),
    );
  }
}

