// lib/screens/chat_screen.dart (FINAL, CLEANED VERSION)

import 'package:flutter/material.dart';
import 'package:sahara_app/models/action_item.dart';
import 'package:sahara_app/models/chat_message.dart';
import 'package:sahara_app/services/api_service.dart';
import 'package:sahara_app/services/database_service.dart';
import 'package:sahara_app/widgets/chat_bubble.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final GlobalKey<AnimatedListState> _listKey = GlobalKey<AnimatedListState>();
  final TextEditingController _controller = TextEditingController();
  final List<ChatMessage> _messages = [];
  bool _isAasthaTyping = false;
  bool _canSendMessage = false;

  @override
  void initState() {
    super.initState();
    // Add the initial welcome message after the first frame is built
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _addMessageToList(ChatMessage(text: 'Welcome to Sahara. How are you feeling today?', isUser: false));
    });

    _controller.addListener(() {
      setState(() {
        _canSendMessage = _controller.text.trim().isNotEmpty;
      });
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
  
  // A single, unified function to handle sending a message
  void _sendMessage() {
    if (!_canSendMessage) return;

    final textToSend = _controller.text.trim();
    _controller.clear();

    // 1. Immediately add the user's message to the UI
    final userMessage = ChatMessage(text: textToSend, isUser: true);
    _addMessageToList(userMessage);

    // 2. Show the "typing" indicator and call the live backend
    setState(() => _isAasthaTyping = true);
    _getLiveAasthaResponse(textToSend);
  }

  // This function now contains all the logic for getting a response
  Future<void> _getLiveAasthaResponse(String message) async {
    // Get the real reply from our live API service
    final String replyText = await ApiService.sendMessage(message);
    
    // Ensure the widget is still on screen before updating state
    if (!mounted) return;

    setState(() => _isAasthaTyping = false);
    _addMessageToList(ChatMessage(text: replyText, isUser: false));

    // After the main reply, we can decide if we should propose an action.
    // For the prototype, we can base it on a simple keyword check.
    // This is a placeholder for the more advanced "Micro-Intervention Engine".
    if (replyText.toLowerCase().contains('stress') || message.toLowerCase().contains('stress')) {
      await Future.delayed(const Duration(milliseconds: 1200));
      if (mounted) _proposeJourneyAction();
    }
  }
  
  // This is our helper for proposing an action item
  Future<void> _proposeJourneyAction() async {
    const suggestedTitle = 'Try a 5-minute breathing exercise';
    final alreadyExists = await DatabaseService.instance.doesActionItemExist(suggestedTitle);

    if (!alreadyExists && mounted) {
      final suggestion = ActionItem(
        title: suggestedTitle,
        description: 'Find this in the Resource Library.',
        dateAdded: DateTime.now(),
      );

      _addMessageToList(ChatMessage(
        text: 'I noticed we are talking about feeling stressed. Sometimes a short breathing exercise can help. Would you like me to add one to your Journey?',
        isUser: false,
        suggestion: suggestion,
      ));
    }
  }

  // This is our helper for adding any message to the animated list
  void _addMessageToList(ChatMessage message) {
    if (mounted) {
      _messages.insert(0, message);
      _listKey.currentState?.insertItem(0, duration: const Duration(milliseconds: 500));
    }
  }
  
  // Helper to show the polished confirmation snackbar
  void _showConfirmationSnackbar(String message) {
    final theme = Theme.of(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: const TextStyle(color: Colors.black87)),
        backgroundColor: theme.colorScheme.secondary,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10.0)),
        margin: const EdgeInsets.all(10.0),
        duration: const Duration(seconds: 3),
      ),
    );
  }
  
  // This is the function that builds each item in our animated list
  Widget _buildItem(BuildContext context, int index, Animation<double> animation) {
    final message = _messages[index];
    final curvedAnimation = CurvedAnimation(parent: animation, curve: Curves.easeOutQuart);

    return FadeTransition(
      opacity: curvedAnimation,
      child: SlideTransition(
        position: Tween<Offset>(begin: const Offset(0, 0.5), end: Offset.zero).animate(curvedAnimation),
        // The ChatBubble needs to be passed the callback function
        child: ChatBubble(
          text: message.text,
          isUser: message.isUser,
          suggestion: message.suggestion,
          onSuggestionAccepted: (actionTitle) {
            _showConfirmationSnackbar('"$actionTitle" has been added to your Journey!');
          },
        ),
      ),
    );
  }
  
  @override
  Widget build(BuildContext context) {
    // The UI part (Column, AnimatedList, etc.) is the same as my previous fix,
    // so I will keep the fully polished version. This should have no errors.
    return Column(
      children: [
        Expanded(
          child: AnimatedList(
            key: _listKey,
            reverse: true,
            padding: const EdgeInsets.all(16.0),
            initialItemCount: _messages.length,
            itemBuilder: _buildItem,
          ),
        ),
        if (_isAasthaTyping)
          Padding(
            padding: const EdgeInsets.only(left: 16.0, right: 16.0, bottom: 8.0),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text( 'Aastha is typing...', style: TextStyle(color: Colors.grey.shade600, fontStyle: FontStyle.italic),
              ),
            ),
          ),
        // Polished Input Bar
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 8.0),
          decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [BoxShadow(blurRadius: 4, color: Colors.black.withOpacity(0.1))]),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _controller,
                  decoration: InputDecoration(
                    hintText: 'Type your message...',
                    filled: true,
                    fillColor: Theme.of(context).scaffoldBackgroundColor,
                    border: OutlineInputBorder( borderRadius: BorderRadius.circular(30.0), borderSide: BorderSide.none,),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 10.0),
                  ),
                  onSubmitted: (_) { if (_canSendMessage) _sendMessage(); },
                ),
              ),
              const SizedBox(width: 8.0),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                transitionBuilder: (child, animation) => ScaleTransition(scale: animation, child: child),
                child: _canSendMessage
                    ? IconButton( key: const ValueKey('send_button'), icon: const Icon(Icons.send), onPressed: _sendMessage,
                        style: IconButton.styleFrom(
                          backgroundColor: Theme.of(context).colorScheme.primary,
                          foregroundColor: Theme.of(context).colorScheme.onPrimary,
                        ),
                      )
                    : const SizedBox(key: ValueKey('empty_box')),
              ),
            ],
          ),
        ),
      ],
    );
  }
}