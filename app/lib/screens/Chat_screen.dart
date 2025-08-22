import 'package:flutter/material.dart';
import 'package:sahara_app/models/action_item.dart';
import 'package:sahara_app/models/chat_message.dart';
import 'package:sahara_app/widgets/chat_bubble.dart';
import 'package:sahara_app/services/database_service.dart';
import 'package:sahara_app/services/api_service.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final GlobalKey<AnimatedListState> _listKey = GlobalKey<AnimatedListState>();
  final TextEditingController _controller = TextEditingController();
  bool _isAasthaTyping = false;
  bool _canSendMessage = false;

  final List<ChatMessage> _messages = [];

  @override
  void initState() {
    super.initState();
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

  // --- THIS IS THE NEW LIVE LOGIC ---
  void _sendMessage() {
    if (_controller.text.trim().isEmpty) return;

    final userMessage = ChatMessage(text: _controller.text.trim(), isUser: true);

    setState(() {
      _messages.insert(0, userMessage);
      _listKey.currentState?.insertItem(0, duration: const Duration(milliseconds: 600));
      _isAasthaTyping = true;
    });

    final textToSend = _controller.text.trim();
    _controller.clear();

    _getLiveAasthaResponse(textToSend);
  }

  Future<void> _getLiveAasthaResponse(String message) async {
    final String replyText = await ApiService.sendMessage(message);

    final aasthaResponse = ChatMessage(text: replyText, isUser: false);

    if (mounted) {
      setState(() {
        _messages.insert(0, aasthaResponse);
        _listKey.currentState?.insertItem(0, duration: const Duration(milliseconds: 600));
        _isAasthaTyping = false;
      });
    }

    // Optional: Add contextual suggestion after AI reply
    final suggestedTitle = 'Try a 5-minute breathing exercise';
    final bool alreadyExists = await DatabaseService.instance.doesActionItemExist(suggestedTitle);

    if (!alreadyExists) {
      final suggestionItem = ActionItem(
        title: suggestedTitle,
        description: 'Find this in the Resource Library.',
        dateAdded: DateTime.now(),
      );
      final suggestionMessage = ChatMessage(
        text: 'I noticed we are talking about feeling stressed. Sometimes a short breathing exercise can help. Would you like me to add one to your Journey?',
        isUser: false,
        suggestion: suggestionItem,
      );
      _addAasthaResponse(null, suggestionMessage: suggestionMessage);
    }
  }

  void _addAasthaResponse(String? text, {ChatMessage? suggestionMessage}) {
    final response = suggestionMessage ?? ChatMessage(text: text!, isUser: false);

    if (mounted) {
      setState(() {
        _messages.insert(0, response);
        _listKey.currentState?.insertItem(0, duration: const Duration(milliseconds: 600));
        _isAasthaTyping = false;
      });
    }
  }

  Widget _buildItem(BuildContext context, int index, Animation<double> animation) {
    final message = _messages[index];
    return SizeTransition(
      sizeFactor: animation,
      child: ChatBubble(
        text: message.text,
        isUser: message.isUser,
        suggestion: message.suggestion,
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
          const Padding(
            padding: EdgeInsets.only(bottom: 12.0),
            child: Text(
              'Aastha is typing...',
              style: TextStyle(fontStyle: FontStyle.italic),
            ),
          ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 8.0),
          color: Colors.white,
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
                  onSubmitted: (value) {
                    if (_canSendMessage) _sendMessage();
                  },
                ),
              ),
              const SizedBox(width: 8.0),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                transitionBuilder: (child, animation) =>
                    ScaleTransition(scale: animation, child: child),
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
