import 'package:flutter/material.dart';
import 'package:sahara_app/models/article.dart';
import 'package:sahara_app/screens/article_detail_screen.dart';
import 'package:sahara_app/services/api_service.dart';

class ResourceLibraryScreen extends StatefulWidget {
  const ResourceLibraryScreen({super.key});

  @override
  State<ResourceLibraryScreen> createState() => _ResourceLibraryScreenState();
}

class _ResourceLibraryScreenState extends State<ResourceLibraryScreen> {
  late Future<List<Article>> _articlesFuture;

  @override
  void initState() {
    super.initState();
    _articlesFuture = ApiService.getResources();
  }

  void _navigateToArticle(BuildContext context, Article article) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => ArticleDetailScreen(article: article),
      ),
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
          return Center(
            child: Text('Could not load resources. Error: ${snapshot.error}'),
          );
        }

        if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return const Center(
            child: Text('No resources available at the moment.'),
          );
        }

        final articles = snapshot.data!;
        return ListView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 24.0),
          itemCount: articles.length,
          itemBuilder: (context, index) {
            final article = articles[index];
            return Card(
  margin: const EdgeInsets.only(bottom: 16.0),
  elevation: 2.0,
  shadowColor: const Color.fromARGB(25, 0, 0, 0), // ~10% opacity black
  child: ListTile(
    leading: Icon(
      Icons.article_outlined,
      color: Theme.of(context).colorScheme.secondary,
      size: 40,
    ),
    title: Text(
      article.title,
      style: const TextStyle(fontWeight: FontWeight.bold),
    ),
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
