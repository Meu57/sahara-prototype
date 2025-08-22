// lib/models/article.dart
import 'package:flutter/widgets.dart'; // We need this for IconData
class Article {
  final String title;
  final String snippet;
  final String content;
   final IconData icon; // NEW FIELD

  Article({
    required this.title,
    required this.snippet,
    required this.content,
    required this.icon, // NEW FIELD
  });
}