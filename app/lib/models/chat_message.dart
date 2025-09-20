// lib/models/chat_message.dart
import 'package:sahara_app/models/action_item.dart';

class ChatMessage {
  final String text;
  final bool isUser;
  final ActionItem? suggestion;
  final bool suggestionHandled;
  final String? journalEntryTitle;
  final String? journalEntryPrefill;

  // NEW: Add a flag to track the journal prompt
  final bool journalPromptHandled;

  ChatMessage({
    required this.text,
    required this.isUser,
    this.suggestion,
    this.suggestionHandled = false,
    this.journalEntryTitle,
    this.journalEntryPrefill,
    this.journalPromptHandled = false, // NEW: Add to constructor
  });

  // NEW: Update the copyWith method
  ChatMessage copyWith({
    bool? suggestionHandled,
    bool? journalPromptHandled,
  }) {
    return ChatMessage(
      text: text,
      isUser: isUser,
      suggestion: suggestion,
      suggestionHandled: suggestionHandled ?? this.suggestionHandled,
      journalEntryTitle: journalEntryTitle,
      journalEntryPrefill: journalEntryPrefill,
      journalPromptHandled: journalPromptHandled ?? this.journalPromptHandled,
    );
  }
}