import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:logger/logger.dart';
import 'package:sahara_app/models/article.dart';
import 'package:sahara_app/models/journal_entry.dart';
import 'package:sahara_app/services/session_service.dart';

class ApiService {
  static const String _baseUrl = 'https://sahara-backend-service-78116732933.asia-south1.run.app';
  static final Logger _logger = Logger();

  // --- CHAT ENDPOINT ---
  static Future<String> sendMessage(String message, {String? userId}) async {
    try {
      final body = {
        'message': message,
        if (userId != null) 'userId': userId,
      };
      final response = await http.post(
        Uri.parse('$_baseUrl/chat'),
        headers: {'Content-Type': 'application/json; charset=UTF-8'},
        body: jsonEncode(body),
      ).timeout(const Duration(seconds: 60)); // Increased timeout for AI

      if (response.statusCode == 200) {
        final map = jsonDecode(response.body);
        // If the server returns a new userId, persist it on the client
        if (map['userId'] != null && map['userId'] is String) {
          await SessionService.setUserId(map['userId']);
        }
        return map['reply'] ?? "Sorry, no reply was received from the server.";
      } else {
        _logger.e('API Error: ${response.statusCode} - ${response.body}');
        return "Sorry, there was an error with the server.";
      }
    } on SocketException {
      return "Please check your internet connection.";
    } catch (e) {
      _logger.e('Error sending message: $e');
      return "Sorry, I am having trouble connecting right now.";
    }
  }

  // --- JOURNAL SYNC ENDPOINT ---
  static Future<void> syncJournalEntry(String userId, JournalEntry entry) async {
    try {
      await http.post(
        Uri.parse('$_baseUrl/journal/sync'),
        headers: {
          'Content-Type': 'application/json; charset=UTF-8',
        },
        body: jsonEncode({
          'userId': userId,
          'entry': entry.toMap(),
        }),
      ).timeout(const Duration(seconds: 15));
      _logger.i('Journal entry synced successfully.');
    } catch (e) {
      _logger.e('Error syncing journal entry: $e');
    }
  }

  // --- RESOURCE FETCH ENDPOINT ---
  static Future<List<Article>> getResources() async {
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/resources'),
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        List<dynamic> jsonList = jsonDecode(response.body);
        return jsonList.map((json) {
          return Article(
            title: json['title'] ?? '',
            snippet: json['snippet'] ?? '',
            content: json['content'] ?? json['snippet'] ?? '',
            icon: Icons.article_outlined,
          );
        }).toList();
      } else {
        throw Exception('Failed to load resources. Status code: ${response.statusCode}');
      }
    } catch (e) {
      _logger.e('Error fetching resources: $e');
      return [];
    }
  }
}
