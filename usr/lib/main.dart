import 'package:flutter/material.dart';

void main() {
  runApp(const MemoApp());
}

class MemoApp extends StatelessWidget {
  const MemoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Memo',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blueGrey,
          brightness: Brightness.light,
        ),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blueGrey,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      themeMode: ThemeMode.system,
      initialRoute: '/',
      routes: {
        '/': (context) => const MemoChatScreen(),
      },
    );
  }
}

class ChatMessage {
  final String text;
  final bool isUser;
  final DateTime timestamp;

  ChatMessage({
    required this.text,
    required this.isUser,
    required this.timestamp,
  });
}

class MemoChatScreen extends StatefulWidget {
  const MemoChatScreen({super.key});

  @override
  State<MemoChatScreen> createState() => _MemoChatScreenState();
}

class _MemoChatScreenState extends State<MemoChatScreen> {
  final List<ChatMessage> _messages = [];
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  bool _isComposing = false;
  bool _isListening = false; // 模拟语音状态

  @override
  void initState() {
    super.initState();
    // 添加一条初始欢迎消息
    _messages.add(ChatMessage(
      text: "Hi, I'm Memo. I can help you remember things and answer your questions.",
      isUser: false,
      timestamp: DateTime.now(),
    ));
  }

  void _handleSubmitted(String text) {
    _textController.clear();
    setState(() {
      _isComposing = false;
    });

    if (text.trim().isEmpty) return;

    // 1. 添加用户消息
    ChatMessage userMessage = ChatMessage(
      text: text,
      isUser: true,
      timestamp: DateTime.now(),
    );

    setState(() {
      _messages.insert(0, userMessage);
    });

    // 2. 模拟 Memo 的回复逻辑
    Future.delayed(const Duration(milliseconds: 600), () {
      String responseText;
      String lowerText = text.toLowerCase();

      if (lowerText.startsWith('search') || lowerText.startsWith('find') || lowerText.contains('搜索')) {
        responseText = "Searching your memories for: \"${text.replaceFirst(RegExp(r'search|find|搜索', caseSensitive: false), '').trim()}\"... \n(This is a demo search result)";
      } else if (lowerText.endsWith('?')) {
        responseText = "That's an interesting question. Based on what you've told me before, I think...";
      } else {
        responseText = "Got it. I've saved this to your memory.";
      }

      if (mounted) {
        setState(() {
          _messages.insert(0, ChatMessage(
            text: responseText,
            isUser: false,
            timestamp: DateTime.now(),
          ));
        });
      }
    });
  }

  void _simulateVoiceInput() {
    setState(() {
      _isListening = !_isListening;
    });
    
    if (_isListening) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Listening... (Voice UI Demo)')),
      );
      // 模拟3秒后自动结束录音并输入文字
      Future.delayed(const Duration(seconds: 3), () {
        if (mounted && _isListening) {
          setState(() {
            _isListening = false;
            _textController.text = "This is a simulated voice input.";
            _isComposing = true;
          });
        }
      });
    }
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
            IconButton(
              icon: Icon(_isListening ? Icons.mic : Icons.mic_none),
              color: _isListening ? Colors.red : Theme.of(context).colorScheme.secondary,
              onPressed: _simulateVoiceInput,
              tooltip: 'Voice Input',
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
                        decoration: const InputDecoration(
                          hintText: 'Tell or ask Memo something',
                          border: InputBorder.none,
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(vertical: 10.0),
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
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.all(16.0),
              reverse: true, // 消息从底部开始
              itemCount: _messages.length,
              itemBuilder: (_, int index) {
                final message = _messages[index];
                return _ChatBubble(message: message);
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
          if (isUser) const SizedBox(width: 40), // 简单的缩进
          if (!isUser) const SizedBox(width: 40),
        ],
      ),
    );
  }
}
