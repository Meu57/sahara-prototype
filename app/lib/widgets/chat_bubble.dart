// lib/widgets/chat_bubble.dart (UPGRADED WITH YOUR STATEFUL WIDGET FIX)

import 'package:flutter/material.dart';
import 'package:sahara_app/services/database_service.dart';
import 'package:sahara_app/models/action_item.dart';

// We convert this to a StatefulWidget to safely use `mounted`
class ChatBubble extends StatefulWidget {
  final String text;
  final bool isUser;
  final ActionItem? suggestion;
    final void Function(String message)? onSuggestionAccepted;

  const ChatBubble({
    super.key,
    required this.text,
    required this.isUser,
    this.suggestion,
     this.onSuggestionAccepted,
  });

  @override
  State<ChatBubble> createState() => _ChatBubbleState();
}

class _ChatBubbleState extends State<ChatBubble> {
  bool _isSuggestionAccepted = false; // To hide the button after it's pressed

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4.0),
      child: Align(
        alignment: widget.isUser ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          padding: const EdgeInsets.all(16.0),
          decoration: BoxDecoration(
            color: widget.isUser ? theme.colorScheme.primary : Colors.grey.shade200,
            borderRadius: BorderRadius.circular(20.0),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(widget.text, style: TextStyle(color: widget.isUser ? theme.colorScheme.onPrimary : Colors.black87)),
              
              // If a suggestion exists AND it hasn't been accepted yet
              if (widget.suggestion != null && !_isSuggestionAccepted)
                Padding(
                  padding: const EdgeInsets.only(top: 12.0),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ElevatedButton(
                        child: const Text('Yes, add it!'),
                        onPressed: () async {
                          // --- YOUR FIX IS IMPLEMENTED HERE ---
                          // First, we update the UI optimistically to hide the buttons
                          setState(() {
                            _isSuggestionAccepted = true;
                          });

                          // Then we perform the database operation
                          await DatabaseService.instance.createActionItem(widget.suggestion!);
                          
                          // NOW we check if the widget is still on screen
                          if (!mounted) return;

                          // And if it is, we safely show the snackbar
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: const Text('A new step has been added to your Journey!', style: TextStyle(color: Colors.black87)),
                              backgroundColor: theme.colorScheme.secondary,
                              behavior: SnackBarBehavior.floating,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10.0)),
                              margin: const EdgeInsets.all(10.0),
                              duration: const Duration(seconds: 2),
                            ),
                          );
                          // --- END OF YOUR FIX ---
                        },
                      ),
                      const SizedBox(width: 8),
                      TextButton(
                        child: const Text('No, thanks'),
                        onPressed: () {
                          setState(() {
                            _isSuggestionAccepted = true; // Also hide buttons on "No"
                          });
                        },
                      )
                    ],
                  ),
                )
            ],
          )
        ),
      ),
    );
  }
}