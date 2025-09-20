import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sahara_app/models/journal_entry.dart';
import 'package:sahara_app/services/api_service.dart';
import 'package:sahara_app/services/session_service.dart';
import 'package:logger/logger.dart';

class JournalEntryScreen extends StatefulWidget {
  /// New-style: pass a JournalEntry object when available.
  final JournalEntry? initialEntry;

  /// Backwards-compatible old-style named params (kept to avoid changing many call sites).
  final String? initialTitle;
  final String? initialContent;

  const JournalEntryScreen({
    super.key,
    this.initialEntry,
    this.initialTitle,
    this.initialContent,
  });

  @override
  State<JournalEntryScreen> createState() => _JournalEntryScreenState();
}

class _JournalEntryScreenState extends State<JournalEntryScreen> {
  final _titleController = TextEditingController();
  final _bodyController = TextEditingController();
  final _logger = Logger();
  bool _saving = false;

  @override
  void initState() {
    super.initState();

    // Priority:
    // 1. widget.initialEntry (new API)
    // 2. widget.initialTitle / widget.initialContent (legacy API)
    // 3. default empty
    _titleController.text =
        widget.initialEntry?.title ?? widget.initialTitle ?? '';
    _bodyController.text =
        widget.initialEntry?.body ?? widget.initialContent ?? '';
  }

  @override
  void dispose() {
    _titleController.dispose();
    _bodyController.dispose();
    super.dispose();
  }

  Future<void> _saveJournalEntry() async {
    final title = _titleController.text.trim();
    final body = _bodyController.text.trim();

    if (title.isEmpty || body.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill out both title and body.')),
      );
      return;
    }

    final entry = JournalEntry(
      // id left null to create a new doc (backend currently lacks update endpoint)
      id: null,
      title: title,
      body: body,
      date: DateTime.now(),
    );

    // If user opened the screen with an existing entry, warn that save will create a new one
    final openedWithExisting = widget.initialEntry != null ||
        (widget.initialTitle != null && widget.initialTitle!.isNotEmpty) ||
        (widget.initialContent != null && widget.initialContent!.isNotEmpty);

    if (openedWithExisting) {
      final proceed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Save as new entry?'),
          content: const Text(
            'Your server does not currently support updating an existing journal entry. '
            'Saving here will create a new entry instead of modifying the one you tapped. '
            'Do you want to continue?',
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('Cancel')),
            ElevatedButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: const Text('Continue')),
          ],
        ),
      );
      if (proceed != true) return;
    }

    setState(() => _saving = true);

    final userId = await SessionService().getUserId();

    try {
      final ok = await ApiService.syncJournalEntry(userId, entry);
      setState(() => _saving = false);

      if (ok) {
        HapticFeedback.lightImpact();
        if (mounted) Navigator.of(context).pop(true); // signal success
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Save failed. Please try again.')),
          );
        }
      }
    } catch (e, st) {
      _logger.e('saveJournalEntry failed: $e\n$st');
      setState(() => _saving = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Save failed. Please try again.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.initialEntry != null ||
        (widget.initialTitle != null && widget.initialTitle!.isNotEmpty) ||
        (widget.initialContent != null && widget.initialContent!.isNotEmpty);

    return Scaffold(
      appBar: AppBar(
        title: Text(isEditing ? 'Edit Journal Entry' : 'New Journal Entry'),
        actions: [
          IconButton(
            onPressed: _saving ? null : _saveJournalEntry,
            icon: _saving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save_outlined),
            tooltip: 'Save',
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            if (isEditing)
              Padding(
                padding: const EdgeInsets.only(bottom: 8.0),
                child: Row(
                  children: const [
                    Icon(Icons.info_outline, size: 18, color: Colors.grey),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Editing will create a new entry on the server (no update endpoint available).',
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    ),
                  ],
                ),
              ),
            TextField(
              controller: _titleController,
              decoration:
                  const InputDecoration(labelText: 'Title', border: InputBorder.none),
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const Divider(),
            Expanded(
              child: TextField(
                controller: _bodyController,
                decoration: const InputDecoration(
                    hintText: 'Write what\'s on your mind...', border: InputBorder.none),
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
