// lib/screens/journal_screen.dart (CORRECTED & REFACTORED)

import 'package:flutter/material.dart';
import 'package:sahara_app/models/journal_entry.dart';
import 'package:sahara_app/screens/journal_entry_screen.dart';
import 'package:sahara_app/services/database_service.dart';
import 'package:intl/intl.dart';

class JournalScreen extends StatefulWidget {
  const JournalScreen({super.key});

  @override
  State<JournalScreen> createState() => _JournalScreenState();
}

class _JournalScreenState extends State<JournalScreen> {
  late Future<List<JournalEntry>> _entriesFuture;

  @override
  void initState() {
    super.initState();
    _loadEntries();
  }

  // A helper function to load entries from our service
  void _loadEntries() {
    setState(() {
      // --- THIS IS THE FIX ---
      // The method call was incomplete.
      _entriesFuture = DatabaseService.instance.getJournalEntries();
    });
  }

  void _navigateToNewEntryScreen() async {
    // We navigate to a page that DOES have a Scaffold.
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (context) => const JournalEntryScreen()),
    );
    // After returning from the new entry screen, reload the list.
    _loadEntries();
  }

  @override
  Widget build(BuildContext context) {
    // This screen is now just the BODY content. The Scaffold is in AppShell.
    // It will be wrapped in a Scaffold when presented via Navigator, but doesn't need its own.
    // However, to add the FloatingActionButton, it is better to have a Scaffold.
    // Let's add it back but WITHOUT an AppBar, so it works seamlessly.
    return Scaffold(
      floatingActionButton: FloatingActionButton(
        onPressed: _navigateToNewEntryScreen,
        backgroundColor: Theme.of(context).colorScheme.secondary, // Our gentle green
        child: const Icon(Icons.add),
      ),
      body: FutureBuilder<List<JournalEntry>>(
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
            padding: const EdgeInsets.all(8.0),
            itemCount: entries.length,
            itemBuilder: (context, index) {
              final entry = entries[index];
              return Card(
                child: ListTile(
                  title: Text(entry.title),
                  subtitle: Text(
                    DateFormat.yMMMMd().add_jm().format(entry.date),
                  ),
                  onTap: () {
                    // Later, this could navigate to a detail view of the entry.
                  },
                ),
              );
            },
          );
        },
      ),
    );
  }
}