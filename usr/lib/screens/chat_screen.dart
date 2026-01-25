import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:record/record.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import '../integrations/supabase.dart';

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
  bool _isListening = false;
  bool _isTranscribing = false;
  final _supabase = Supabase.instance.client;
  final _recorder = AudioRecorder();
  String? _audioPath;
  Timer? _recordingTimer;
  int _recordDurationSeconds = 0;

  @override
  void initState() {
    super.initState();
    _checkPermissions();
  }

  @override
  void dispose() {
    _recordingTimer?.cancel();
    _recorder.dispose();
    super.dispose();
  }

  Future<void> _checkPermissions() async {
    try {
      final hasPermission = await _recorder.hasPermission();
      print('录音权限检查: $hasPermission');
      if (!hasPermission) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('需要麦克风权限才能使用语音功能')),
          );
        }
      }
    } catch (e) {
      print('权限检查错误: $e');
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
    });

    if (text.trim().isEmpty) return;

    // 1. 保存用户消息到数据库
    await _saveMessage(text, true);

    // 2. 模拟 Memo 的回复逻辑
    // 在实际应用中，这里可能会调用 Edge Function 或其他 AI 服务
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
        // 保存 Agent 回复到数据库
        await _saveMessage(responseText, false);
      }
    });
  }

  Future<void> _transcribeAudio(String path) async {
    print('开始转录音频: $path');
    setState(() {
      _isTranscribing = true;
    });

    try {
      final file = File(path);
      if (!await file.exists()) {
        print('音频文件不存在');
        return;
      }
      
      final bytes = await file.readAsBytes();
      print('音频文件大小: ${bytes.length} bytes');
      
      // Use SupabaseConfig for URL and Key
      final uri = Uri.parse('${SupabaseConfig.supabaseUrl}/functions/v1/transcribe');
      print('发送请求到: $uri');
      
      final request = http.MultipartRequest('POST', uri)
        ..headers['Authorization'] = 'Bearer ${SupabaseConfig.supabaseAnonKey}'
        ..files.add(http.MultipartFile.fromBytes('audio', bytes, filename: 'audio.wav'));

      final response = await request.send();
      final respStr = await response.stream.bytesToString();
      print('响应状态码: ${response.statusCode}');
      print('响应内容: $respStr');

      if (response.statusCode == 200) {
        final json = jsonDecode(respStr);
        final text = json['text'];
        print('转录结果: $text');
        if (text != null && text.toString().isNotEmpty) {
           _handleSubmitted(text);
        }
      } else {
        // Handle specific error cases
        String errorMessage = 'Transcription failed';
        try {
          final json = jsonDecode(respStr);
          if (json['is_config_error'] == true) {
            errorMessage = 'Configuration Error: ${json['error']}';
            _showApiKeyDialog();
          } else {
            errorMessage = json['error'] ?? respStr;
          }
        } catch (_) {
          errorMessage = respStr;
        }

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(errorMessage),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 5),
            ),
          );
        }
      }
    } catch (e) {
      print('转录错误: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error transcribing audio: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isTranscribing = false;
        });
      }
      // Clean up temp file
      if (path.isNotEmpty) {
        try {
          await File(path).delete();
        } catch (_) {}
      }
    }
  }

  void _showApiKeyDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Setup Required'),
        content: const Text(
          'To use the voice feature, you need to set up the Deepgram API Key.\n\n'
          '1. Go to console.deepgram.com and get an API Key.\n'
          '2. Go to your Supabase Dashboard -> Edge Functions -> Secrets.\n'
          '3. Add a new secret named "DEEPGRAM_API_KEY" with your key value.'
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _startRecording() async {
    print('尝试开始录音...');
    try {
      if (await _recorder.hasPermission()) {
        print('有录音权限，开始录音');
        final tempDir = await getTemporaryDirectory();
        final path = '${tempDir.path}/audio_${DateTime.now().millisecondsSinceEpoch}.wav';
        print('录音文件路径: $path');
        
        // Use WAV encoder for compatibility
        const config = RecordConfig(encoder: AudioEncoder.wav);
        await _recorder.start(config, path: path);
        
        setState(() {
          _isListening = true;
          _recordDurationSeconds = 0;
        });

        _recordingTimer?.cancel();
        _recordingTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
          setState(() {
            _recordDurationSeconds++;
          });
          if (_recordDurationSeconds >= 30) {
            print('达到30秒限制，自动停止');
            _stopRecording();
          }
        });
      } else {
        print('没有录音权限');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('需要麦克风权限才能使用语音功能')),
          );
        }
      }
    } catch (e) {
      print('录音错误: $e');
      print('错误类型: ${e.runtimeType}');
      print('错误堆栈: ${StackTrace.current}');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('录音失败: $e')),
        );
      }
    }
  }

  void _stopRecording() async {
    print('停止录音...');
    _recordingTimer?.cancel();
    if (!_isListening) {
      print('当前未在录音状态');
      return;
    }

    try {
      final path = await _recorder.stop();
      print('录音停止，文件路径: $path');
      setState(() {
        _isListening = false;
        _audioPath = path;
      });
      if (_audioPath != null) {
        await _transcribeAudio(_audioPath!);
      }
    } catch (e) {
      print('停止录音错误: $e');
    }
  }

  void _cancelRecording() async {
    print('取消录音');
    _recordingTimer?.cancel();
    if (!_isListening) return;
    
    try {
      await _recorder.stop();
    } catch (_) {}

    setState(() {
      _isListening = false;
      _audioPath = null;
    });
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
              onLongPressStart: (_) {
                print('长按开始录音');
                _startRecording();
              },
              onLongPressEnd: (_) {
                print('长按结束停止录音');
                _stopRecording();
              },
              child: IconButton(
                icon: Icon(_isListening ? Icons.stop_circle_outlined : Icons.mic_none),
                color: _isListening ? Colors.red : Theme.of(context).colorScheme.secondary,
                iconSize: _isListening ? 32 : 24,
                onPressed: () {
                  print('点击语音按钮，当前状态: ${_isListening ? "录音中" : "未录音"}');
                  if (_isListening) {
                    _stopRecording();
                  } else {
                    _startRecording();
                  }
                },
                tooltip: _isListening ? 'Stop Recording' : 'Voice Input (Hold or Tap)',
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
                child: _isListening 
                  ? Row(
                      children: [
                        const SizedBox(width: 16),
                        const Icon(Icons.fiber_manual_record, color: Colors.red, size: 16),
                        const SizedBox(width: 8),
                        Text(
                          'Recording... 00:${_recordDurationSeconds.toString().padLeft(2, '0')} / 00:30',
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const Spacer(),
                        IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: _cancelRecording,
                          tooltip: 'Cancel',
                        ),
                      ],
                    )
                  : _isTranscribing 
                    ? Row(
                        children: [
                          const SizedBox(width: 16),
                          const SizedBox(
                            width: 16, 
                            height: 16, 
                            child: CircularProgressIndicator(strokeWidth: 2)
                          ),
                          const SizedBox(width: 12),
                          Text(
                            'Transcribing...',
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.primary,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ],
                      )
                    : Row(
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
