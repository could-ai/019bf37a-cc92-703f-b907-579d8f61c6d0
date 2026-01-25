import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:speech_to_text/speech_recognition_result.dart';

class MemoChatScreen extends StatefulWidget {
  const MemoChatScreen({super.key});

  @override
  State<MemoChatScreen> createState() => _MemoChatScreenState();
}

class _MemoChatScreenState extends State<MemoChatScreen> {
  final TextEditingController _textController = TextEditingController();
  final SupabaseClient _supabase = Supabase.instance.client;
  final ScrollController _scrollController = ScrollController();
  
  List<Map<String, dynamic>> _messages = [];
  bool _isLoading = true;
  bool _isAiThinking = false;
  
  // Speech to text
  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _isListening = false;
  bool _speechEnabled = false;

  @override
  void initState() {
    super.initState();
    _loadMessages();
    _initSpeech();
  }

  void _initSpeech() async {
    try {
      _speechEnabled = await _speech.initialize(
        onStatus: (status) => print('Speech status: $status'),
        onError: (errorNotification) => print('Speech error: $errorNotification'),
      );
      if (mounted) {
        setState(() {});
      }
    } catch (e) {
      print('Speech initialization error: $e');
    }
  }

  Future<void> _loadMessages() async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) return;

      final data = await _supabase
          .from('messages')
          .select()
          .eq('user_id', userId)
          .order('created_at', ascending: true);

      if (mounted) {
        setState(() {
          _messages = List<Map<String, dynamic>>.from(data);
          _isLoading = false;
        });
        
        // Scroll to bottom after loading
        WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
      }
    } catch (e) {
      print('Error loading messages: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  Future<void> _saveMessage(String content, bool isUser) async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) return;

      final newMessage = {
        'user_id': userId,
        'content': content,
        'is_user': isUser,
      };

      final response = await _supabase
          .from('messages')
          .insert(newMessage)
          .select()
          .single();

      if (mounted) {
        setState(() {
          _messages.add(response);
        });
        _scrollToBottom();
      }
    } catch (e) {
      print('Error saving message: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error saving message: $e')),
        );
      }
    }
  }

  Future<void> _handleSubmitted(String text) async {
    if (text.trim().isEmpty) return;

    _textController.clear();
    await _saveMessage(text, true);
    await _getAiResponse(text);
  }

  Future<void> _getAiResponse(String userMessage) async {
    if (mounted) {
      setState(() {
        _isAiThinking = true;
      });
    }

    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) {
        throw Exception('User not logged in');
      }

      // 1. Fetch chat history (only user messages as requested)
      final List<dynamic> historyData = await _supabase
          .from('messages')
          .select('content, is_user, created_at')
          .eq('user_id', userId)
          .eq('is_user', true) 
          .order('created_at', ascending: false)
          .limit(20);

      final history = historyData.reversed.toList();

      final List<Map<String, String>> messages = history.map<Map<String, String>>((msg) {
        return {
          'role': 'user',
          'content': msg['content'] as String,
        };
      }).toList();

      // Ensure current message is included if not already (it should be if saved first)
      if (messages.isEmpty || messages.last['content'] != userMessage) {
        messages.add({
          'role': 'user',
          'content': userMessage,
        });
      }

      print('Sending to AI: ${messages.length} messages');

      // 2. Call the Edge Function
      final response = await _supabase.functions.invoke(
        'chat-grok',
        body: {'messages': messages},
      );

      if (response.status != 200) {
        throw FunctionException(
          status: response.status, 
          details: response.data, 
          reasonPhrase: 'Function error'
        );
      }

      final data = response.data;
      if (data != null && data['reply'] != null) {
        final aiReply = data['reply'] as String;
        await _saveMessage(aiReply, false);
      } else if (data != null && data['error'] != null) {
        throw Exception(data['error']);
      } else {
        throw Exception('Invalid response format from AI');
      }

    } on FunctionException catch (e) {
      print('Function Error: ${e.status} ${e.details} ${e.reasonPhrase}');
      if (mounted) {
        if (e.status == 401) {
          // Only logout if it's strictly a 401 (Unauthorized)
          // The Edge Function now returns 500 for API Key errors, so 401 should only be for Session Expiry
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Session expired. Please login again.'),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 5),
              action: SnackBarAction(
                label: 'Logout',
                textColor: Colors.white,
                onPressed: _signOut,
              ),
            ),
          );
          // We don't auto-logout immediately to let user see the message, 
          // but usually 401 means subsequent requests will fail too.
          await _signOut();
        } else {
          // Handle other errors (500, etc.)
          String errorMessage = 'AI Error';
          if (e.details != null && e.details is Map && e.details['error'] != null) {
            errorMessage = e.details['error'];
          } else {
            errorMessage = 'AI Error: ${e.status} ${e.reasonPhrase}';
          }
          
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(errorMessage), 
              backgroundColor: Colors.red
            ),
          );
        }
      }
    } catch (e) {
      print('AI Error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error getting AI response: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isAiThinking = false;
        });
      }
    }
  }

  Future<void> _signOut() async {
    try {
      await _supabase.auth.signOut();
      if (mounted) {
        Navigator.of(context).pushReplacementNamed('/');
      }
    } catch (e) {
      print('Error signing out: $e');
    }
  }

  // Speech functions
  void _startListening() async {
    if (!_speechEnabled) {
      _initSpeech();
    }
    
    await _speech.listen(
      onResult: _onSpeechResult,
      listenFor: const Duration(seconds: 30),
      pauseFor: const Duration(seconds: 3),
      partialResults: true,
    );
    if (mounted) {
      setState(() {
        _isListening = true;
      });
    }
  }

  void _stopListening() async {
    await _speech.stop();
    if (mounted) {
      setState(() {
        _isListening = false;
      });
    }
  }

  void _onSpeechResult(SpeechRecognitionResult result) {
    if (mounted) {
      setState(() {
        _textController.text = result.recognizedWords;
      });
    }
    
    if (result.finalResult) {
      _handleSubmitted(result.recognizedWords);
      _stopListening();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Memo'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: _signOut,
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _messages.isEmpty
                    ? Center(
                        child: Text(
                          'Tell or ask Memo something...',
                          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                                color: Colors.grey,
                              ),
                        ),
                      )
                    : ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.all(16),
                        itemCount: _messages.length,
                        itemBuilder: (context, index) {
                          final message = _messages[index];
                          final isUser = message['is_user'] as bool;
                          return Align(
                            alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
                            child: Container(
                              margin: const EdgeInsets.symmetric(vertical: 4),
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: isUser
                                    ? Theme.of(context).colorScheme.primaryContainer
                                    : Theme.of(context).colorScheme.secondaryContainer,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(message['content'] as String),
                            ),
                          );
                        },
                      ),
          ),
          if (_isAiThinking)
            const Padding(
              padding: EdgeInsets.all(8.0),
              child: LinearProgressIndicator(),
            ),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              children: [
                IconButton(
                  icon: Icon(_isListening ? Icons.mic : Icons.mic_none),
                  color: _isListening ? Colors.red : null,
                  onPressed: _isListening ? _stopListening : _startListening,
                ),
                Expanded(
                  child: TextField(
                    controller: _textController,
                    decoration: const InputDecoration(
                      hintText: 'Type a message...',
                      border: OutlineInputBorder(),
                    ),
                    onSubmitted: _handleSubmitted,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.send),
                  onPressed: () => _handleSubmitted(_textController.text),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
