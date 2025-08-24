// lib/widgets/chat_bubble.dart

import 'package:flutter/material.dart';
import 'package:sahara_app/models/action_item.dart';
import 'package:sahara_app/services/database_service.dart';

class ChatBubble extends StatelessWidget {
  final String text;
  final bool isUser;
  final ActionItem? suggestion;
  final Function(String actionTitle) onSuggestionAccepted;

  const ChatBubble({
    super.key,
    required this.text,
    required this.isUser,
    this.suggestion,
    required this.onSuggestionAccepted,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4.0),
      child: Align(
        alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          padding: const EdgeInsets.all(16.0),
          decoration: BoxDecoration(
            color: isUser ? theme.colorScheme.primary : Colors.grey.shade200,
            borderRadius: BorderRadius.circular(20.0),
          ),
          child: Column(
            crossAxisAlignment: isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min, // Important for the bubble to wrap content
            children: [
              // The main message text
              Text(
                text,
                style: TextStyle(
                  color: isUser ? theme.colorScheme.onPrimary : Colors.black87,
                ),
              ),
              
              // If a suggestion exists, display the interactive buttons
              if (suggestion != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12.0),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Using a smaller, softer button style for the suggestion
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: theme.colorScheme.primary,
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20.0),
                          ),
                        ),
                        child: const Text('Yes, add it!'),
                        onPressed: () async {
                          // We still handle the database action here for simplicity
                          await DatabaseService.instance.createActionItem(suggestion!);
                          // But we call the callback to let the screen handle the UI feedback
                          onSuggestionAccepted(suggestion!.title);
                        },
                      ),
                      const SizedBox(width: 8),
                      TextButton(
                        child: const Text(
                          'No, thanks',
                          style: TextStyle(color: Colors.black54),
                        ),
                        onPressed: () { 
                          // Optionally, we could add logic to hide this message
                        },
                      )
                    ],
                  ),
                )
            ],
          ),
        ),
      ),
    );
  }
}