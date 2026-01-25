import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import '../integrations/supabase.dart';
import 'auth_screen.dart';

class ChatMessage {
  final String id;
  final String text;
  final bool isUser;
  final DateTime timestamp;

  ChatMessage({
    required this.id,
    required this.text,
    required this.isUser,
    required this.timestamp,
  });

  factory ChatMessage.fromMap(Map<String, dynamic> map) {
    return ChatMessage(
      id: map['id'] ?? '',
      text: map['content'] ?? '',
      isUser: map['is_user'] ?? true,
      timestamp: DateTime.parse(map['created_at']).toLocal(),
    );
  }
}

class MemoChatScreen extends StatefulWidget {
  const MemoChatScreen({super.key});

  @override
  State<MemoChatScreen> createState() => _MemoChatScreenState();
}

class _MemoChatScreenState extends State<MemoChatScreen> {
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  bool _isComposing = false;
  
  // Speech to Text variables
  final SpeechToText _speechToText = SpeechToText();
  bool _speechEnabled = false;
  bool _isListening = false;
  String _lastWords = '';

  final _supabase = Supabase.instance.client;

  @override
  void initState() {
    super.initState();
    _initSpeech();
  }

  /// Initialize the speech recognition service
  void _initSpeech() async {
    try {
      _speechEnabled = await _speechToText.initialize(
        onStatus: _onSpeechStatus,
        onError: _onSpeechError,
      );
      setState(() {});
    } catch (e) {
      print('Speech initialization error: $e');
    }
  }

  void _onSpeechStatus(String status) {
    print('Speech status: $status');
    setState(() {
      _isListening = status == 'listening';
    });
  }

  void _onSpeechError(dynamic errorNotification) {
    print('Speech error: $errorNotification');
    setState(() {
      _isListening = false;
    });
    // Don't show snackbar for 'no match' as it can be spammy
    if (errorNotification.errorMsg != 'error_no_match') {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Speech Error: ${errorNotification.errorMsg}')),
      );
    }
  }

  Future<void> _signOut() async {
    try {
      await _supabase.auth.signOut();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error signing out: $e')),
        );
      }
    }
  }

  Future<void> _saveMessage(String text, bool isUser) async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) return;

      await _supabase.from('messages').insert({
        'content': text,
        'is_user': isUser,
        'user_id': userId,
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error saving message: $e')),
        );
      }
    }
  }

  void _handleSubmitted(String text) async {
    _textController.clear();
    setState(() {
      _isComposing = false;
      _lastWords = '';
    });

    if (text.trim().isEmpty) return;

    // 1. Save user message
    await _saveMessage(text, true);

    // 2. Simulate Agent response
    Future.delayed(const Duration(milliseconds: 600), () async {
      String responseText;
      String lowerText = text.toLowerCase();

      if (lowerText.startsWith('search') || lowerText.startsWith('find') || lowerText.contains('搜索')) {
        responseText = "Searching your memories for: \"${text.replaceFirst(RegExp(r'search|find|搜索', caseSensitive: false), '').trim()}\" ... \n(This is a demo search result)";
      } else if (lowerText.endsWith('?')) {
        responseText = "That's an interesting question. Based on what you've told me before, I think...";
      } else {
        responseText = "Got it. I've saved this to your memory.";
      }

      if (mounted) {
        await _saveMessage(responseText, false);
      }
    });
  }

  /// Start listening for speech
  void _startListening() async {
    if (!_speechEnabled) {
      _initSpeech(); // Try to init again if failed previously
      if (!_speechEnabled) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Speech recognition not available')),
        );
        return;
      }
    }

    await _speechToText.listen(
      onResult: _onSpeechResult,
      localeId: 'en_US', // Default to English, can be made dynamic
      listenFor: const Duration(seconds: 30),
      pauseFor: const Duration(seconds: 3),
      partialResults: true,
      cancelOnError: true,
      listenMode: ListenMode.dictation,
    );
    
    setState(() {
      _isListening = true;
      _lastWords = '';
    });
  }

  /// Stop listening
  void _stopListening() async {
    await _speechToText.stop();
    setState(() {
      _isListening = false;
    });
  }

  /// Callback when speech result is received
  void _onSpeechResult(SpeechRecognitionResult result) {
    setState(() {
      _lastWords = result.recognizedWords;
      _textController.text = _lastWords;
      _isComposing = _lastWords.isNotEmpty;
    });

    // If final result, we could auto-send, but let's let user confirm
    // if (result.finalResult) { ... }
  }

  Widget _buildTextComposer() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 8.0),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainer,
        border: Border(top: BorderSide(color: Theme.of(context).dividerColor.withOpacity(0.1))),
      ),
      child: SafeArea(
        child: Row(
          children: [
            GestureDetector(
              onLongPressStart: (_) => _startListening(),
              onLongPressEnd: (_) => _stopListening(),
              child: IconButton(
                icon: Icon(_isListening ? Icons.mic : Icons.mic_none),
                color: _isListening ? Colors.red : Theme.of(context).colorScheme.secondary,
                iconSize: _isListening ? 32 : 24,
                onPressed: () {
                  if (_isListening) {
                    _stopListening();
                  } else {
                    _startListening();
                  }
                },
                tooltip: _isListening ? 'Stop Listening' : 'Voice Input',
              ),
            ),
            const SizedBox(width: 8.0),
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  borderRadius: BorderRadius.circular(24.0),
                  border: Border.all(color: Theme.of(context).dividerColor.withOpacity(0.2)),
                ),
                child: Row(
                  children: [
                    const SizedBox(width: 16.0),
                    Expanded(
                      child: TextField(
                        controller: _textController,
                        onChanged: (text) {
                          setState(() {
                            _isComposing = text.isNotEmpty;
                          });
                        },
                        onSubmitted: _handleSubmitted,
                        textInputAction: TextInputAction.send,
                        decoration: InputDecoration(
                          hintText: _isListening ? 'Listening...' : 'Tell or ask Memo something',
                          border: InputBorder.none,
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(vertical: 10.0),
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.arrow_upward_rounded),
                      color: _isComposing 
                          ? Theme.of(context).colorScheme.primary 
                          : Theme.of(context).disabledColor,
                      onPressed: _isComposing
                          ? () => _handleSubmitted(_textController.text)
                          : null,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Memo', style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
        elevation: 0,
        backgroundColor: Theme.of(context).colorScheme.surface,
        scrolledUnderElevation: 2.0,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Logout',
            onPressed: _signOut,
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<List<Map<String, dynamic>>>(
              stream: _supabase
                  .from('messages')
                  .stream(primaryKey: ['id'])
                  .order('created_at', ascending: false),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(child: Text('Error: ${snapshot.error}'));
                }

                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                final data = snapshot.data!;
                
                if (data.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32.0),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.psychology, size: 64, color: Theme.of(context).colorScheme.primary.withOpacity(0.5)),
                          const SizedBox(height: 16),
                          Text(
                            "Hi, I'm Memo.\nI can help you remember things and answer your questions.",
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.secondary,
                              fontSize: 16,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }

                final messages = data.map((map) => ChatMessage.fromMap(map)).toList();

                return ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.all(16.0),
                  reverse: true,
                  itemCount: messages.length,
                  itemBuilder: (_, int index) {
                    final message = messages[index];
                    return _ChatBubble(message: message);
                  },
                );
              },
            ),
          ),
          _buildTextComposer(),
        ],
      ),
    );
  }
}

class _ChatBubble extends StatelessWidget {
  final ChatMessage message;

  const _ChatBubble({required this.message});

  @override
  Widget build(BuildContext context) {
    final isUser = message.isUser;
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        mainAxisAlignment: isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isUser) ...[
            CircleAvatar(
              backgroundColor: colorScheme.secondaryContainer,
              radius: 16,
              child: Icon(Icons.smart_toy_outlined, size: 18, color: colorScheme.onSecondaryContainer),
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
              decoration: BoxDecoration(
                color: isUser ? colorScheme.primary : colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(20),
                  topRight: const Radius.circular(20),
                  bottomLeft: isUser ? const Radius.circular(20) : const Radius.circular(4),
                  bottomRight: isUser ? const Radius.circular(4) : const Radius.circular(20),
                ),
              ),
              child: Text(
                message.text,
                style: TextStyle(
                  color: isUser ? colorScheme.onPrimary : colorScheme.onSurfaceVariant,
                  fontSize: 16,
                ),
              ),
            ),
          ),
          if (isUser) const SizedBox(width: 40),
          if (!isUser) const SizedBox(width: 40),
        ],
      ),
    );
  }
}
