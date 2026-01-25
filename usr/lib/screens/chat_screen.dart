  Future<void> _getAiResponse(String userMessage) async {
    setState(() {
      _isAiThinking = true;
    });

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

      // Ensure current message is included
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
        throw Exception('Failed to get response from AI: ${response.status} ${response.data}');
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
          // Force sign out on JWT error
          await _signOut();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Session expired. You have been logged out. Please login again.'),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 10),
            ),
          );
          // Navigate back to auth screen
          if (mounted) {
            Navigator.of(context).pushReplacementNamed('/');
          }
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('AI Error: ${e.details ?? e.reasonPhrase}'), backgroundColor: Colors.red),
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