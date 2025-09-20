// lib/screens/journey_screen.dart

import 'package:flutter/material.dart';
import 'package:sahara_app/models/action_item.dart';
import 'package:sahara_app/services/api_service.dart';
import 'package:sahara_app/services/session_service.dart';

class JourneyScreen extends StatefulWidget {
  // Expects the full navigation function from the parent (AppShell).
  final void Function(
    int index, {
    String? completedTaskTitle,
    String? resourceId,
    String? journalTitle,
    String? journalContent,
  }) onNavigate;

  const JourneyScreen({
    super.key,
    required this.onNavigate,
  });

  @override
  State<JourneyScreen> createState() => _JourneyScreenState();
}

class _JourneyScreenState extends State<JourneyScreen> {
  late Future<List<ActionItem>> _actionItemsFuture;
  late VoidCallback _journeyListener;

  @override
  void initState() {
    super.initState();
    _loadActionItems();

    _journeyListener = () {
      if (mounted) _loadActionItems();
    };
    SessionService.journeyRefresh.addListener(_journeyListener);
  }

  @override
  void dispose() {
    SessionService.journeyRefresh.removeListener(_journeyListener);
    super.dispose();
  }

  Future<void> _loadActionItems() async {
    final userId = await SessionService().getUserId();
    final future = ApiService.getJourneyItems(userId);

    if (!mounted) return;
    setState(() {
      _actionItemsFuture = future;
    });

    try {
      await future;
    } catch (_) {
      // FutureBuilder will handle showing the error state.
    }
  }

  Future<void> _confirmComplete(ActionItem item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirm completion'),
        content: Text(
            'Have you completed "${item.title}"? This action cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('No')),
          ElevatedButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Yes')),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        final userId = await SessionService().getUserId();
        await ApiService.updateActionItem(
            userId, item.copyWith(isCompleted: true));

        if (!mounted) return;

        // Refresh local data first so the UI updates.
        await _loadActionItems();

        // Then, navigate to the Chat tab with the completed task's title
        // and request AppShell to open a prefilled JournalEntryScreen.
        widget.onNavigate(
          0,
          completedTaskTitle: item.title,
          
        );
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Failed to update. Please try again.')),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<ActionItem>>(
      future: _actionItemsFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return const Center(child: Text('Could not load your Journey.'));
        }

        if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(24.0),
              child: Text(
                'Your Journey is just beginning.\nChat with Aastha to discover your next steps!',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 18, color: Colors.grey, height: 1.5),
              ),
            ),
          );
        }

        final items = snapshot.data!;
        return ListView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 24.0),
          itemCount: items.length,
          itemBuilder: (context, index) {
            final item = items[index];
            return Card(
              margin: const EdgeInsets.only(bottom: 12.0),
              child: ListTile(
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
                leading: Checkbox(
                  value: item.isCompleted,
                  onChanged: item.isCompleted
                      ? null
                      : (bool? _) => _confirmComplete(item),
                  activeColor: Theme.of(context).colorScheme.secondary,
                ),
                title: Text(
                  item.title,
                  style: TextStyle(
                    decoration: item.isCompleted
                        ? TextDecoration.lineThrough
                        : TextDecoration.none,
                    color: item.isCompleted
                        ? Colors.grey
                        : Theme.of(context).textTheme.bodyLarge?.color,
                  ),
                ),
                subtitle: Text(item.description),
                trailing: item.resourceId.isNotEmpty
                    ? TextButton(
                        onPressed: () =>
                            widget.onNavigate(2, resourceId: item.resourceId),
                        child: const Text('View Guide'),
                      )
                    : null,
              ),
            );
          },
        );
      },
    );
  }
}
