// lib/screens/journal_entry_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // Required for HapticFeedback
import 'package:sahara_app/models/journal_entry.dart';
import 'package:sahara_app/services/database_service.dart';
import 'package:sahara_app/services/api_service.dart'; // Import ApiService
import 'package:sahara_app/services/session_service.dart'; // ✅ Import SessionService

class JournalEntryScreen extends StatefulWidget {
  const JournalEntryScreen({super.key});

  @override
  State<JournalEntryScreen> createState() => _JournalEntryScreenState();
}

class _JournalEntryScreenState extends State<JournalEntryScreen> {
  final _titleController = TextEditingController();
  final _bodyController = TextEditingController();

  @override
  void dispose() {
    _titleController.dispose();
    _bodyController.dispose();
    super.dispose();
  }

  Future<void> _saveJournalEntry() async {
    if (_titleController.text.isEmpty || _bodyController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill out both title and body.')),
      );
      return;
    }

    final newEntry = JournalEntry(
      title: _titleController.text,
      body: _bodyController.text,
      date: DateTime.now(),
    );

    // Save locally
    await DatabaseService.instance.createJournalEntry(newEntry);

    // --- NEW LIVE LOGIC ---
    print('Attempting to sync journal entry to the cloud...');

    // ✅ Get the real, persistent user ID
    final String userId = await SessionService().getUserId();

    // ✅ Sync to backend using the user ID and entry map
    ApiService.syncJournalEntry(userId, newEntry);

    // Fire-and-forget: no await, no error handling for now
    // --- END OF NEW LOGIC ---

    HapticFeedback.lightImpact();

    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('New Journal Entry'),
        actions: [
          IconButton(
            icon: const Icon(Icons.save_outlined),
            onPressed: _saveJournalEntry,
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            TextField(
              controller: _titleController,
              decoration: const InputDecoration(
                labelText: 'Title',
                border: InputBorder.none,
              ),
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const Divider(),
            Expanded(
              child: TextField(
                controller: _bodyController,
                decoration: const InputDecoration(
                  hintText: 'Write what\'s on your mind...',
                  border: InputBorder.none,
                ),
                maxLines: null,
                expands: true,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
