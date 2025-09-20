// lib/screens/resource_library_screen.dart
import 'package:flutter/material.dart';
import 'package:sahara_app/models/article.dart';
import 'package:sahara_app/screens/article_detail_screen.dart';
import 'package:sahara_app/services/api_service.dart';

class ResourceLibraryScreen extends StatefulWidget {
  final String? initialResourceId;
  const ResourceLibraryScreen({super.key, this.initialResourceId});

  @override
  State<ResourceLibraryScreen> createState() => _ResourceLibraryScreenState();
}

class _ResourceLibraryScreenState extends State<ResourceLibraryScreen> {
  late Future<List<Article>> _articlesFuture;
  bool _hasConsumedInitialResource = false;

  @override
  void initState() {
    super.initState();
    _articlesFuture = ApiService.getResources();
  }

  void _navigateToArticle(BuildContext context, Article article) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (context) => ArticleDetailScreen(article: article)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Article>>(
      future: _articlesFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return Center(child: Text('Could not load resources. Error: ${snapshot.error}'));
        }

        if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return const Center(child: Text('No resources available at the moment.'));
        }

        final articles = snapshot.data!;

        // If an initialResourceId was provided, open that resource immediately (only once).
        if (!_hasConsumedInitialResource && widget.initialResourceId != null) {
          final match = articles.firstWhere(
            (a) => a.id == widget.initialResourceId,
            // Provide a valid fallback Article object (with a default icon).
            orElse: () => Article(
              id: '',
              title: 'Resource not found',
              snippet: '',
              content: '',
              icon: Icons.article_outlined,
            ),
          );

          if (match.id.isNotEmpty) {
            // Schedule navigation after the build is complete.
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) {
                _navigateToArticle(context, match);
              }
            });
          }
          // Mark consumed regardless of whether we found it to avoid repeated lookups.
          _hasConsumedInitialResource = true;
        }

        return ListView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 24.0),
          itemCount: articles.length,
          itemBuilder: (context, index) {
            final article = articles[index];
            return Card(
              margin: const EdgeInsets.only(bottom: 16.0),
              elevation: 2.0,
              child: ListTile(
                leading: Icon(article.icon, color: Theme.of(context).colorScheme.secondary, size: 40),
                title: Text(article.title, style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text(article.snippet),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                onTap: () => _navigateToArticle(context, article),
              ),
            );
          },
        );
      },
    );
  }
}
