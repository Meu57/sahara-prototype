import 'package:flutter/material.dart';
import 'package:sahara_app/models/action_item.dart';
import 'package:sahara_app/services/database_service.dart';

class JourneyScreen extends StatefulWidget {
  const JourneyScreen({super.key});

  @override
  State<JourneyScreen> createState() => _JourneyScreenState();
}

class _JourneyScreenState extends State<JourneyScreen> {
  late Future<List<ActionItem>> _actionItemsFuture;

  @override
  void initState() {
    super.initState();
    _loadActionItems();
  }

  void _loadActionItems() {
    setState(() {
      _actionItemsFuture = DatabaseService.instance.getActionItems();
    });
  }

  void _toggleItemCompletion(ActionItem item) async {
    final updatedItem = item.copyWith(isCompleted: !item.isCompleted);
    await DatabaseService.instance.updateActionItem(updatedItem);
    _loadActionItems();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<ActionItem>>(
      future: _actionItemsFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
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
                contentPadding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
                leading: Checkbox(
                  value: item.isCompleted,
                  onChanged: (bool? value) {
                    _toggleItemCompletion(item);
                  },
                  activeColor: Theme.of(context).colorScheme.secondary,
                ),
                title: Text(
                  item.title,
                  style: TextStyle(
                    decoration: item.isCompleted ? TextDecoration.lineThrough : TextDecoration.none,
                    color: item.isCompleted
                        ? Colors.grey
                        : Theme.of(context).textTheme.bodyLarge?.color,
                  ),
                ),
                subtitle: Text(item.description),
              ),
            );
          },
        );
      },
    );
  }
}
