// lib/services/api_service.dart

import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:sahara_app/models/article.dart'; // We will use our Article model
import 'package:flutter/material.dart';

class ApiService {
  // --- CRITICAL STEP ---
  // Replace this placeholder with the real URL you just copied from Cloud Run.
  static const String _baseUrl = 'https://sahara-backend-service-78116732933.asia-south1.run.app';
  // Use http://YOUR_IPV4_ADDRESS:5000 (Flask's default port)
  // static const String _baseUrl = 'http://127.0.0.1:5000';


  // Method to fetch the resource articles
  static Future<List<Article>> getResources() async {
    try {
      final response = await http.get(Uri.parse('$_baseUrl/resources'));

      if (response.statusCode == 200) {
        // If the server returns a 200 OK response, parse the JSON.
        List<dynamic> jsonList = jsonDecode(response.body);
        List<Article> articles = jsonList.map((json) {
          return Article(
            // For now, content can be the same as the snippet since our model needs it
            title: json['title'] ?? '',
            snippet: json['snippet'] ?? '',
            content: json['content'] ?? json['snippet'] ?? '',
            // Use a default icon
            icon: Icons.article_outlined,
          );
        }).toList();
        return articles;
      } else {
        // If the server did not return a 200 OK response,
        // then throw an exception.
        throw Exception('Failed to load resources');
      }
    } catch (e) {
      // Handle any errors that occur during the fetch
      print('Error fetching resources: $e');
      // Return an empty list or re-throw the exception as needed
      return [];
    }
  }
  
  // lib/services/api_service.dart

// ... class ApiService { ... getResources() ...

  // Method to send a chat message and get a reply
  static Future<String> sendMessage(String message) async {
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/chat'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'message': message}),
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body)['reply'];
      } else {
        return "Sorry, I'm having trouble connecting.";
      }
    } catch (e) {
      print('Error sending message: $e');
      return "It seems I'm offline right now. Let's talk later.";
    }
  }

  // Method to sync a journal entry
  // This is a "fire and forget" call, so it doesn't need to return much.
  static Future<void> syncJournalEntry(String userId, Map<String, dynamic> entry) async {
    try {
      await http.post(
        Uri.parse('$_baseUrl/journal/sync'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'userId': userId, 'entry': entry}),
      );
    } catch (e) {
      // In a real app, we would add logic to retry this later
      print('Error syncing journal entry: $e');
    }
  }
// ... }
}