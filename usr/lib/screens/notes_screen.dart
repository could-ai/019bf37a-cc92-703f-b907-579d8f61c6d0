import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class NotesScreen extends StatefulWidget {
  const NotesScreen({super.key});

  @override
  State<NotesScreen> createState() => _NotesScreenState();
}

class _NotesScreenState extends State<NotesScreen> {
  final _supabase = Supabase.instance.client;
  late Stream<List<Map<String, dynamic>>> _notesStream;

  @override
  void initState() {
    super.initState();
    final userId = _supabase.auth.currentUser?.id;
    if (userId != null) {
      // Using stream for real-time updates
      _notesStream = _supabase
          .from('notes')
          .stream(primaryKey: ['id'])
          .eq('user_id', userId)
          .order('created_at', ascending: false);
    } else {
      _notesStream = const Stream.empty();
    }
  }

  Future<void> _deleteNote(int id) async {
    try {
      await _supabase.from('notes').delete().eq('id', id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Note deleted')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error deleting note: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Memories'),
      ),
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: _notesStream,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }

          final notes = snapshot.data ?? [];

          if (notes.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.note_alt_outlined, size: 64, color: Theme.of(context).colorScheme.secondary),
                  const SizedBox(height: 16),
                  const Text(
                    'No memories yet.\nTell Memo something about yourself!',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey),
                  ),
                ],
              ),
            );
          }

          return ListView.builder(
            itemCount: notes.length,
            itemBuilder: (context, index) {
              final note = notes[index];
              final createdAt = DateTime.parse(note['created_at']).toLocal();
              
              return Dismissible(
                key: Key(note['id'].toString()),
                background: Container(
                  color: Colors.red,
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.only(right: 16),
                  child: const Icon(Icons.delete, color: Colors.white),
                ),
                direction: DismissDirection.endToStart,
                confirmDismiss: (direction) async {
                  return await showDialog(
                    context: context,
                    builder: (BuildContext context) {
                      return AlertDialog(
                        title: const Text("Confirm"),
                        content: const Text("Are you sure you want to delete this memory?"),
                        actions: <Widget>[
                          TextButton(
                            onPressed: () => Navigator.of(context).pop(false),
                            child: const Text("Cancel"),
                          ),
                          TextButton(
                            onPressed: () => Navigator.of(context).pop(true),
                            child: const Text("Delete", style: TextStyle(color: Colors.red)),
                          ),
                        ],
                      );
                    },
                  );
                },
                onDismissed: (_) => _deleteNote(note['id']),
                child: Card(
                  margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  elevation: 2,
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                      child: Icon(Icons.lightbulb, color: Theme.of(context).colorScheme.primary),
                    ),
                    title: Text(
                      note['content'] ?? '',
                      style: const TextStyle(fontWeight: FontWeight.w500),
                    ),
                    subtitle: Text(
                      '${createdAt.year}-${createdAt.month.toString().padLeft(2, '0')}-${createdAt.day.toString().padLeft(2, '0')} ${createdAt.hour.toString().padLeft(2, '0')}:${createdAt.minute.toString().padLeft(2, '0')}',
                      style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.outline),
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
