// lib/screens/journal_screen.dart

import 'package:flutter/material.dart';
import 'package:sahara_app/models/journal_entry.dart';
import 'package:sahara_app/screens/journal_entry_screen.dart';
import 'package:sahara_app/services/database_service.dart';
import 'package:sahara_app/services/api_service.dart';
import 'package:sahara_app/services/session_service.dart';
import 'package:intl/intl.dart';
import 'package:logger/logger.dart';

class JournalScreen extends StatefulWidget {
  const JournalScreen({super.key});

  @override
  State<JournalScreen> createState() => _JournalScreenState();
}

class _JournalScreenState extends State<JournalScreen> {
  late Future<List<JournalEntry>> _entriesFuture;
  final _localLogger = Logger();

  @override
  void initState() {
    super.initState();
    _loadEntries();
  }

  void _loadEntries() async {
    setState(() {
      _entriesFuture = Future.value([]);
    });

    final userId = await SessionService().getUserId();
    _localLogger.i('JournalScreen: loading entries for user: $userId');

    try {
      final future = ApiService.getJournalEntries(userId);

      if (!mounted) return;
      setState(() {
        _entriesFuture = future;
      });

      final loaded = await future;
      _localLogger.i('JournalScreen: loaded ${loaded.length} entries from backend.');
      return;
    } catch (e, st) {
      _localLogger.e('JournalScreen: getJournalEntries failed: $e\n$st');
    }

    try {
      final dbFuture = DatabaseService.instance.getJournalEntries();
      if (!mounted) return;
      setState(() {
        _entriesFuture = dbFuture;
      });
      final dbLoaded = await dbFuture;
      _localLogger.i('JournalScreen: loaded ${dbLoaded.length} entries from local DB (fallback).');
    } catch (e, st) {
      _localLogger.e('JournalScreen: fallback DatabaseService failed: $e\n$st');
    }
  }

  void _navigateToNewEntryScreen() async {
    final created = await Navigator.of(context).push(
      MaterialPageRoute(builder: (context) => const JournalEntryScreen()),
    );
    if (created == true) {
      _loadEntries(); // Refresh only if entry was saved
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Your Journal'),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _navigateToNewEntryScreen,
        backgroundColor: Theme.of(context).colorScheme.secondary,
        child: const Icon(Icons.add),
      ),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
        child: FutureBuilder<List<JournalEntry>>(
          future: _entriesFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return Center(child: Text('Error: ${snapshot.error}'));
            }
            final entries = snapshot.data;
            if (entries == null || entries.isEmpty) {
              return const Center(
                child: Padding(
                  padding: EdgeInsets.all(24.0),
                  child: Text(
                    'Your journal is empty.\nTap the + button to add your first entry.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 18, color: Colors.grey),
                  ),
                ),
              );
            }
            return ListView.builder(
              padding: const EdgeInsets.only(top: 8.0),
              itemCount: entries.length,
              itemBuilder: (context, index) {
                final entry = entries[index];
                return Card(
                  margin: const EdgeInsets.only(bottom: 12.0),
                  child: ListTile(
                    title: Text(entry.title),
                    subtitle: Text(
                      DateFormat.yMMMMd().add_jm().format(entry.date),
                    ),
                    onTap: () {
                      // Future enhancement: navigate to detail view
                    },
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}
