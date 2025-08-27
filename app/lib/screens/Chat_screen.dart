// lib/screens/chat_screen.dart (FINAL, UPDATED VERSION)

import 'package:flutter/material.dart';
import 'package:sahara_app/models/action_item.dart';
import 'package:sahara_app/models/chat_message.dart';
import 'package:sahara_app/services/api_service.dart';
import 'package:sahara_app/services/database_service.dart';
import 'package:sahara_app/services/session_service.dart';
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

  void _sendMessage() {
    if (!_canSendMessage) return;

    final textToSend = _controller.text.trim();
    _controller.clear();

    final userMessage = ChatMessage(text: textToSend, isUser: true);
    _addMessageToList(userMessage);

    setState(() => _isAasthaTyping = true);
    _getLiveAasthaResponse(textToSend);
  }

  Future<void> _getLiveAasthaResponse(String message) async {
    final String userId = await SessionService().getUserId();

    final String replyText = await ApiService.sendMessage(message, userId: userId);

    if (!mounted) return;

    setState(() => _isAasthaTyping = false);
    _addMessageToList(ChatMessage(text: replyText, isUser: false));

    if (replyText.toLowerCase().contains('stress') || message.toLowerCase().contains('stress')) {
      await Future.delayed(const Duration(milliseconds: 1200));
      if (mounted) _proposeJourneyAction();
    }
  }

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

  void _addMessageToList(ChatMessage message) {
    if (mounted) {
      _messages.insert(0, message);
      _listKey.currentState?.insertItem(0, duration: const Duration(milliseconds: 500));
    }
  }

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

  Widget _buildItem(BuildContext context, int index, Animation<double> animation) {
    final message = _messages[index];
    final curvedAnimation = CurvedAnimation(parent: animation, curve: Curves.easeOutQuart);

    return FadeTransition(
      opacity: curvedAnimation,
      child: SlideTransition(
        position: Tween<Offset>(begin: const Offset(0, 0.5), end: Offset.zero).animate(curvedAnimation),
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
              child: Text(
                'Aastha is typing...',
                style: TextStyle(color: Colors.grey.shade600, fontStyle: FontStyle.italic),
              ),
            ),
          ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 8.0),
          decoration: BoxDecoration(
            color: Colors.white,
            boxShadow: [BoxShadow(blurRadius: 4, color: Colors.black.withOpacity(0.1))],
          ),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _controller,
                  decoration: InputDecoration(
                    hintText: 'Type your message...',
                    filled: true,
                    fillColor: Theme.of(context).scaffoldBackgroundColor,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(30.0),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 10.0),
                  ),
                  onSubmitted: (_) {
                    if (_canSendMessage) _sendMessage();
                  },
                ),
              ),
              const SizedBox(width: 8.0),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                transitionBuilder: (child, animation) => ScaleTransition(scale: animation, child: child),
                child: _canSendMessage
                    ? IconButton(
                        key: const ValueKey('send_button'),
                        icon: const Icon(Icons.send),
                        onPressed: _sendMessage,
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
