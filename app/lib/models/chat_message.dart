// lib/models/chat_message.dart (UPGRADED for suggestions)
import 'package:sahara_app/models/action_item.dart';

class ChatMessage {
  final String text;
  final bool isUser;
  // NEW: A message can optionally contain an ActionItem to suggest
  final ActionItem? suggestion; 

  ChatMessage({required this.text, required this.isUser, this.suggestion});
}