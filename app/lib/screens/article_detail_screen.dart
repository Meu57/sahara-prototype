// lib/screens/article_detail_screen.dart
import 'package:flutter/material.dart';
import 'package:sahara_app/models/article.dart';

class ArticleDetailScreen extends StatelessWidget {
  final Article article;

  const ArticleDetailScreen({super.key, required this.article});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Article Detail'),
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                article.title,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 24),
              Text(
                article.content,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  fontSize: 17,
                  height: 1.6, // Increased line spacing for readability
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
