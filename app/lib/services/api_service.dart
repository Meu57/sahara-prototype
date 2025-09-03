import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:logger/logger.dart';
import 'package:sahara_app/models/article.dart';
import 'package:sahara_app/models/journal_entry.dart';
import 'package:sahara_app/services/session_service.dart';

class AppConfig {
  /// Build-time API key
  static const String apiKey =
      String.fromEnvironment('SAHARA_API_KEY', defaultValue: '');

  /// Build-time base URL (useful for switching between local backend / cloud).
  /// Example: --dart-define=SAHARA_BASE_URL=http://10.0.2.2:8080
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

  static Future<String> sendMessage(String message, {String? userId}) async {
    try {
      final localUserId = userId ?? await SessionService().getUserId();
      final payload = {'message': message, 'userId': localUserId};

      final response = await _client
          .post(
            Uri.parse('$_baseUrl/chat'),
            headers: _secureHeaders,
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 60));

      final data = _handleResponse(response) as Map<String, dynamic>;

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
        headers: _secureHeaders,
      );

      final data = _handleResponse(response) as List<dynamic>;

      return data.map((json) {
        final item = json as Map<String, dynamic>;
        return Article(
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

  static Future<void> syncJournalEntry(String userId, JournalEntry entry) async {
    try {
      final payload = {'userId': userId, 'entry': entry.toMap()};
      await _client.post(
        Uri.parse('$_baseUrl/journal/sync'),
        headers: _secureHeaders,
        body: jsonEncode(payload),
      );
      _logger.i('Journal entry sync successful.');
    } catch (e) {
      _logger.e('syncJournalEntry failed: $e');
    }
  }
}
