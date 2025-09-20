// lib/screens/chat_screen.dart
import 'package:flutter/material.dart';
import 'package:sahara_app/models/action_item.dart';
import 'package:sahara_app/models/chat_message.dart';
import 'package:sahara_app/services/api_service.dart';
import 'package:sahara_app/services/session_service.dart';
import 'package:sahara_app/screens/journal_entry_screen.dart';
import 'package:sahara_app/widgets/chat_bubble.dart';

class ChatScreen extends StatefulWidget {
  final String? completedTaskTitle;

  const ChatScreen({
    super.key,
    this.completedTaskTitle,
  });

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
      if (widget.completedTaskTitle != null) {
        _showSimulatedReply(widget.completedTaskTitle!);
      } else {
        _addMessageToList(
            ChatMessage(text: 'Welcome to Sahara. How are you feeling today?', isUser: false));
      }
    });
    _controller.addListener(() {
      setState(() {
        _canSendMessage = _controller.text.trim().isNotEmpty;
      });
    });
  }

  @override
  void didUpdateWidget(covariant ChatScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.completedTaskTitle != null &&
        widget.completedTaskTitle != oldWidget.completedTaskTitle) {
      _showSimulatedReply(widget.completedTaskTitle!);
    }
  }

  void _showSimulatedReply(String taskTitle) {
    final String simulatedReplyText =
        "I see you just completed the '$taskTitle' exercise. That's a great step. How did it feel for you?";
    final ChatMessage message = ChatMessage(
      text: simulatedReplyText,
      isUser: false,
      journalEntryTitle: "Reflection on '$taskTitle'",
      journalEntryPrefill: "I completed '$taskTitle' today. It felt...",
    );
    _addMessageToList(message);
  }

  // NEW: A handler for the journal prompt button
  void _handleWriteInJournal(int index) {
    final message = _messages[index];
    if (message.journalPromptHandled) return;

    // Immediately mark the prompt as handled to disable the button
    setState(() {
      _messages[index] = message.copyWith(journalPromptHandled: true);
    });

    // Navigate to the journal entry screen
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => JournalEntryScreen(
          initialTitle: message.journalEntryTitle,
          initialContent: message.journalEntryPrefill,
        ),
      ),
    );
  }

  // ✅ NEW: Add a handler for the "No, thanks" button
  void _handleJournalPromptRejected(int index) {
    final message = _messages[index];
    if (message.journalPromptHandled) return;

    // Immediately mark the prompt as handled to disable both buttons
    setState(() {
      _messages[index] = message.copyWith(journalPromptHandled: true);
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
    try {
      final String userId = await SessionService().getUserId();
      final response = await ApiService.sendMessage(message, userId: userId);

      final String replyText =
          response['reply'] as String? ?? 'Sorry, no reply received.';
      final suggestionData = response['suggestion'] as Map<String, dynamic>?;

      if (!mounted) return;
      setState(() => _isAasthaTyping = false);

      ActionItem? suggestion;
      if (suggestionData != null) {
        suggestion = ActionItem.fromSuggestionJson(suggestionData);
      }

      _addMessageToList(
          ChatMessage(text: replyText, isUser: false, suggestion: suggestion));
    } catch (e) {
      if (!mounted) return;
      setState(() => _isAasthaTyping = false);
      _addMessageToList(ChatMessage(
          text: "Sorry, I'm having trouble connecting.", isUser: false));
    }
  }

  void _addMessageToList(ChatMessage message) {
    if (mounted) {
      _messages.insert(0, message);
      _listKey.currentState?.insertItem(0, duration: const Duration(milliseconds: 500));
    }
  }

  void _showAddedSnackbar() {
    final theme = Theme.of(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Activity added to your Journey.'),
        backgroundColor: theme.colorScheme.secondary,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _showDismissSnackbar() {
    final theme = Theme.of(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Suggestion noted.'),
        backgroundColor: theme.colorScheme.secondary,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _showErrorSnackbar() {
    final theme = Theme.of(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Could not add item. Please try again.'),
        backgroundColor: theme.colorScheme.error,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  Future<void> _handleSuggestionAcceptedAtIndex(int index) async {
    final message = _messages[index];
    if (message.suggestion == null || message.suggestionHandled) return;

    setState(() {
      _messages[index] = message.copyWith(suggestionHandled: true);
    });

    try {
      final userId = await SessionService().getUserId();
      await ApiService.addJourneyItem(userId, message.suggestion!);

      if (!mounted) return;
      _showAddedSnackbar();

      SessionService.journeyRefresh.value++;
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _messages[index] = message.copyWith(suggestionHandled: false);
      });
      _showErrorSnackbar();
    }
  }

  void _handleSuggestionRejectedAtIndex(int index) {
    final message = _messages[index];
    if (message.suggestionHandled) return;

    setState(() {
      _messages[index] = message.copyWith(suggestionHandled: true);
    });

    _showDismissSnackbar();
  }

  // UPDATED: The _buildItem method
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
          suggestionHandled: message.suggestionHandled,
          onSuggestionAccepted: (_) => _handleSuggestionAcceptedAtIndex(index),
          onSuggestionRejected: () => _handleSuggestionRejectedAtIndex(index),

          journalEntryTitle: message.journalEntryTitle,
          journalEntryPrefill: message.journalEntryPrefill,

          // UPDATED: Pass the new flag and the new handlers
          journalPromptHandled: message.journalPromptHandled,
          onWriteJournal: () => _handleWriteInJournal(index),

          // ✅ NEW: Pass the new handler to the bubble
          onJournalPromptRejected: () => _handleJournalPromptRejected(index),
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
