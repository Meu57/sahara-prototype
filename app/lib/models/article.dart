// lib/models/article.dart
import 'package:flutter/widgets.dart'; // for IconData

class Article {
  final String id;        // NEW: unique identifier for lookup/navigation
  final String title;
  final String snippet;
  final String content;
  final IconData icon;

  Article({
    required this.id,
    required this.title,
    required this.snippet,
    required this.content,
    required this.icon,
  });
}
