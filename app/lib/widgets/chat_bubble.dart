// lib/widgets/chat_bubble.dart

import 'package:flutter/material.dart';
import 'package:sahara_app/models/action_item.dart';

class ChatBubble extends StatelessWidget {
  final String text;
  final bool isUser;
  final ActionItem? suggestion;
  final bool suggestionHandled;
  final void Function(ActionItem item)? onSuggestionAccepted;
  final VoidCallback? onSuggestionRejected;

  // NEW journaling props
  final String? journalEntryTitle;
  final String? journalEntryPrefill;
  final VoidCallback? onWriteJournal;
  final bool journalPromptHandled;
  final VoidCallback? onJournalPromptRejected; // ✅ NEW

  const ChatBubble({
    super.key,
    required this.text,
    required this.isUser,
    this.suggestion,
    this.suggestionHandled = false,
    this.onSuggestionAccepted,
    this.onSuggestionRejected,
    this.journalEntryTitle,
    this.journalEntryPrefill,
    this.onWriteJournal,
    this.journalPromptHandled = false,
    this.onJournalPromptRejected, // ✅ NEW
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
            crossAxisAlignment:
                isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                text,
                style: TextStyle(
                  color: isUser ? theme.colorScheme.onPrimary : Colors.black87,
                ),
              ),
              if (suggestion != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12.0),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: theme.colorScheme.primary,
                        ),
                        onPressed: (suggestionHandled || onSuggestionAccepted == null)
                            ? null
                            : () => onSuggestionAccepted!(suggestion!),
                        child: const Text('Yes, add it!'),
                      ),
                      const SizedBox(width: 8),
                      TextButton(
                        onPressed: (suggestionHandled || onSuggestionRejected == null)
                            ? null
                            : onSuggestionRejected,
                        child: Text(
                          'No, thanks',
                          style: TextStyle(color: Colors.black54),
                        ),
                      ),
                    ],
                  ),
                ),
              if (journalEntryTitle != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12.0),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: theme.colorScheme.primary,
                        ),
                        onPressed: journalPromptHandled ? null : onWriteJournal,
                        child: const Text('Write in Journal'),
                      ),
                      const SizedBox(width: 8),
                      TextButton(
                        onPressed: journalPromptHandled ? null : onJournalPromptRejected,
                        child: Text(
                          'No, thanks',
                          style: TextStyle(color: Colors.black54),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
