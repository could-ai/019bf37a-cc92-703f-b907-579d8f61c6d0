import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:speech_to_text/speech_recognition_result.dart';
import 'dart:convert'; // For jsonDecode
import 'notes_screen.dart';

class MemoChatScreen extends StatefulWidget {
  const MemoChatScreen({super.key});

  @override
  State<MemoChatScreen> createState() => _MemoChatScreenState();
}

class _MemoChatScreenState extends State<MemoChatScreen> {
  final TextEditingController _textController = TextEditingController();
  final SupabaseClient _supabase = Supabase.instance.client;
  final ScrollController _scrollController = ScrollController();
  
  // Messages will be stored with newest first (index 0 = newest)
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
    _textController.addListener(() {
      setState(() {});
    });
  }

  @override
  void dispose() {
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
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

      // Fetch messages ordered by created_at descending (newest first)
      // This works with ListView(reverse: true) where index 0 is at the bottom
      final data = await _supabase
          .from('messages')
          .select()
          .eq('user_id', userId)
          .order('created_at', ascending: false);

      if (mounted) {
        setState(() {
          _messages = List<Map<String, dynamic>>.from(data);
          _isLoading = false;
        });
        // No need to scroll manually on load because reverse: true starts at scroll offset 0 (bottom)
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

  void _scrollToNewest() {
    if (_scrollController.hasClients) {
      // With reverse: true, 0.0 is the bottom (newest message)
      _scrollController.animateTo(
        0.0,
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
          // Insert at the beginning (index 0) because list is reversed
          _messages.insert(0, response);
        });
        _scrollToNewest();
      }
    } catch (e) {
      print('Error saving message: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error saving message: $e'),
            backgroundColor: Colors.red.shade600,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
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
      _scrollToNewest(); // Scroll to show thinking indicator (which is at the bottom)
    }

    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) {
        throw Exception('User not logged in');
      }

      final response = await _supabase.functions.invoke(
        'chat-grok',
        body: {'content': userMessage},
      );

      if (response.status != 200) {
        String errorMessage = 'Function error: ${response.status}';
        try {
          if (response.data is Map && response.data['error'] != null) {
            errorMessage = response.data['error'];
          } else if (response.data is String) {
             errorMessage = response.data;
          }
        } catch (_) {}

        throw FunctionException(
          status: response.status, 
          details: response.data, 
          reasonPhrase: errorMessage
        );
      }

      final data = response.data;
      if (data != null && data['reply'] != null) {
        final aiReply = data['reply'] as String;
        await _saveMessage(aiReply, false);
        
        if (data['saved_notes'] != null && (data['saved_notes'] as List).isNotEmpty) {
           if (mounted) {
             ScaffoldMessenger.of(context).showSnackBar(
               SnackBar(
                 content: const Row(
                   children: [
                     Icon(Icons.check_circle, color: Colors.white, size: 20),
                     SizedBox(width: 8),
                     Text('Memory updated'),
                   ],
                 ),
                 duration: const Duration(seconds: 2),
                 backgroundColor: Colors.green.shade600,
                 behavior: SnackBarBehavior.floating,
                 shape: RoundedRectangleBorder(
                   borderRadius: BorderRadius.circular(10),
                 ),
               ),
             );
           }
        }

      } else if (data != null && data['error'] != null) {
        throw Exception(data['error']);
      } else {
        throw Exception('Invalid response format from AI');
      }

    } on FunctionException catch (e) {
      print('Function Error: ${e.status} ${e.details} ${e.reasonPhrase}');
      if (mounted) {
        if (e.status == 401) {
           ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Session expired. Please login again.'), 
              backgroundColor: Colors.red.shade600,
              duration: const Duration(seconds: 5),
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              action: SnackBarAction(
                label: 'Logout', 
                onPressed: _signOut,
                textColor: Colors.white,
              ),
            ),
          );
        } else {
          String msg = e.reasonPhrase ?? 'Unknown error';
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('AI Error: $msg'), 
              backgroundColor: Colors.red.shade600,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          );
        }
      }
    } catch (e) {
      print('AI Error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red.shade600,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isAiThinking = false;
        });
        _scrollToNewest();
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final backgroundColor = isDark ? Colors.black : const Color(0xFFF2F2F7);
    
    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        backgroundColor: isDark ? Colors.grey.shade900 : Colors.white,
        elevation: 0,
        centerTitle: true,
        // Notes icon moved to leading (left side)
        leading: IconButton(
          icon: Icon(
            Icons.history_edu,
            color: isDark ? Colors.blue.shade400 : Colors.blue,
            size: 22,
          ),
          tooltip: 'Memories',
          onPressed: () {
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const NotesScreen()),
            );
          },
        ),
        // Title with Icon + Text
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: isDark 
                    ? Colors.blue.shade900.withOpacity(0.3) 
                    : Colors.blue.shade50,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.psychology,
                size: 18,
                color: isDark ? Colors.blue.shade400 : Colors.blue.shade700,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              'Memo',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white : Colors.black,
                letterSpacing: -0.4,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(
              Icons.logout,
              color: isDark ? Colors.blue.shade400 : Colors.blue,
              size: 22,
            ),
            tooltip: 'Sign Out',
            onPressed: _signOut,
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Column(
        children: [
          // Messages List
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _messages.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(32.0),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.chat_bubble_outline,
                                size: 64,
                                color: isDark 
                                    ? Colors.grey.shade700 
                                    : Colors.grey.shade400,
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'Tell or ask Memo something',
                                style: TextStyle(
                                  fontSize: 17,
                                  color: isDark 
                                      ? Colors.grey.shade600 
                                      : Colors.grey.shade500,
                                  letterSpacing: -0.4,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        ),
                      )
                    : ListView.builder(
                        controller: _scrollController,
                        reverse: true, // Start from bottom
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        itemCount: _messages.length + (_isAiThinking ? 1 : 0),
                        itemBuilder: (context, index) {
                          // Handle thinking indicator as the first item (index 0) when visible
                          if (_isAiThinking) {
                            if (index == 0) {
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 28,
                                      height: 28,
                                      margin: const EdgeInsets.only(right: 8),
                                      decoration: BoxDecoration(
                                        color: isDark ? Colors.grey.shade800 : Colors.grey.shade300,
                                        shape: BoxShape.circle,
                                      ),
                                      child: Icon(
                                        Icons.psychology,
                                        size: 16,
                                        color: isDark ? Colors.blue.shade400 : Colors.blue.shade700,
                                      ),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                      decoration: BoxDecoration(
                                        color: isDark ? Colors.grey.shade800 : Colors.white,
                                        borderRadius: BorderRadius.circular(18),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          SizedBox(
                                            width: 12,
                                            height: 12,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              valueColor: AlwaysStoppedAnimation<Color>(
                                                isDark ? Colors.blue.shade400 : Colors.blue,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Text(
                                            'Thinking...',
                                            style: TextStyle(
                                              fontSize: 14,
                                              color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }
                            // Adjust index for messages
                            index = index - 1;
                          }

                          final message = _messages[index];
                          final isUser = message['is_user'] as bool;
                          // In reversed list, index 0 is the bottom-most (newest) message
                          final isLastMessage = index == 0;
                          
                          return Padding(
                            padding: EdgeInsets.only(
                              bottom: isLastMessage ? 8 : 12,
                            ),
                            child: Row(
                              mainAxisAlignment: isUser 
                                  ? MainAxisAlignment.end 
                                  : MainAxisAlignment.start,
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                if (!isUser) ...[
                                  // AI Avatar
                                  Container(
                                    width: 28,
                                    height: 28,
                                    margin: const EdgeInsets.only(right: 8, bottom: 2),
                                    decoration: BoxDecoration(
                                      color: isDark 
                                          ? Colors.grey.shade800 
                                          : Colors.grey.shade300,
                                      shape: BoxShape.circle,
                                    ),
                                    child: Icon(
                                      Icons.psychology,
                                      size: 16,
                                      color: isDark 
                                          ? Colors.blue.shade400 
                                          : Colors.blue.shade700,
                                    ),
                                  ),
                                ],
                                // Message Bubble
                                Flexible(
                                  child: Container(
                                    constraints: BoxConstraints(
                                      maxWidth: MediaQuery.of(context).size.width * 0.75,
                                    ),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 10,
                                    ),
                                    decoration: BoxDecoration(
                                      color: isUser
                                          ? (isDark 
                                              ? Colors.blue.shade700 
                                              : Colors.blue)
                                          : (isDark 
                                              ? Colors.grey.shade800 
                                              : Colors.white),
                                      borderRadius: BorderRadius.circular(18),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black.withOpacity(isDark ? 0.3 : 0.05),
                                          blurRadius: 8,
                                          offset: const Offset(0, 2),
                                        ),
                                      ],
                                    ),
                                    child: Text(
                                      message['content'] as String,
                                      style: TextStyle(
                                        fontSize: 16,
                                        height: 1.4,
                                        color: isUser
                                            ? Colors.white
                                            : (isDark ? Colors.white : Colors.black87),
                                        letterSpacing: -0.3,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
          ),
          
          // Input Bar
          Container(
            decoration: BoxDecoration(
              color: isDark ? Colors.grey.shade900 : Colors.white,
              border: Border(
                top: BorderSide(
                  color: isDark ? Colors.grey.shade800 : Colors.grey.shade300,
                  width: 0.5,
                ),
              ),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: SafeArea(
              child: Row(
                children: [
                  // Text Input
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: isDark ? Colors.grey.shade800 : const Color(0xFFF2F2F7),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: TextField(
                        controller: _textController,
                        decoration: InputDecoration(
                          hintText: 'Tell or ask Memo something',
                          hintStyle: TextStyle(
                            fontSize: 16,
                            color: isDark ? Colors.grey.shade500 : Colors.grey.shade600,
                            letterSpacing: -0.3,
                          ),
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 10,
                          ),
                        ),
                        style: TextStyle(
                          fontSize: 16,
                          color: isDark ? Colors.white : Colors.black,
                          letterSpacing: -0.3,
                        ),
                        maxLines: null,
                        textInputAction: TextInputAction.send,
                        onSubmitted: _handleSubmitted,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Send/Mic Button
                  GestureDetector(
                    onTap: _textController.text.isEmpty
                        ? (_isListening ? _stopListening : _startListening)
                        : () => _handleSubmitted(_textController.text),
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: _textController.text.isEmpty
                            ? (isDark ? Colors.grey.shade800 : const Color(0xFFF2F2F7))
                            : (isDark ? Colors.blue.shade600 : Colors.blue),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        _textController.text.isEmpty
                            ? (_isListening ? Icons.mic : Icons.mic_none)
                            : Icons.arrow_upward,
                        color: _textController.text.isEmpty
                            ? (isDark ? Colors.grey.shade400 : Colors.grey.shade700)
                            : Colors.white,
                        size: 20,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
