// ═══════════════════════════════════════════════════════════════
// NEXUS Заметки — полноценный текстовый редактор
//
// - Создание, редактирование, удаление заметок
// - Хранение в локальном файле JSON
// - Поиск по тексту
// ═══════════════════════════════════════════════════════════════

import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

// ═══ МОДЕЛЬ ═══

class Note {
  String id;
  String title;
  String content;
  DateTime createdAt;
  DateTime updatedAt;
  String colorHex;

  Note({
    String? id,
    this.title = '',
    this.content = '',
    DateTime? createdAt,
    DateTime? updatedAt,
    this.colorHex = '#1E232B',
  })  : id = id ?? DateTime.now().millisecondsSinceEpoch.toString(),
        createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'content': content,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
    'colorHex': colorHex,
  };

  factory Note.fromJson(Map<String, dynamic> json) => Note(
    id: json['id'] as String,
    title: json['title'] as String? ?? '',
    content: json['content'] as String? ?? '',
    createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ?? DateTime.now(),
    updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? '') ?? DateTime.now(),
    colorHex: json['colorHex'] as String? ?? '#1E232B',
  );
}

// ═══ СЕРВИС ═══

class NotesService {
  static final NotesService instance = NotesService._();
  List<Note> _notes = [];
  String? _filePath;

  NotesService._();

  List<Note> get notes => List.unmodifiable(_notes);

  Future<void> init() async {
    final dir = await getApplicationDocumentsDirectory();
    _filePath = '${dir.path}/nexus_notes.json';
    await _load();
    if (_notes.isEmpty) {
      _notes.add(Note(title: 'Добро пожаловать!', content: 'Это ваша первая заметка. Нажмите ✏️ чтобы редактировать.'));
      await _save();
    }
  }

  Future<void> _load() async {
    try {
      final file = File(_filePath!);
      if (await file.exists()) {
        final data = jsonDecode(await file.readAsString()) as List;
        _notes = data.map((e) => Note.fromJson(e as Map<String, dynamic>)).toList();
      }
    } catch (_) {}
  }

  Future<void> _save() async {
    try {
      final file = File(_filePath!);
      await file.writeAsString(jsonEncode(_notes.map((n) => n.toJson()).toList()));
    } catch (_) {}
  }

  Future<void> addNote(String title, String content) async {
    _notes.insert(0, Note(title: title, content: content));
    await _save();
  }

  Future<void> updateNote(String id, String title, String content) async {
    final idx = _notes.indexWhere((n) => n.id == id);
    if (idx >= 0) {
      _notes[idx].title = title;
      _notes[idx].content = content;
      _notes[idx].updatedAt = DateTime.now();
      await _save();
    }
  }

  Future<void> deleteNote(String id) async {
    _notes.removeWhere((n) => n.id == id);
    await _save();
  }
}

// ═══ UI ═══

class NotesScreen extends StatefulWidget {
  const NotesScreen({super.key});

  @override
  State<NotesScreen> createState() => _NotesScreenState();
}

class _NotesScreenState extends State<NotesScreen> {
  final _service = NotesService.instance;
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _openEditor({Note? note}) {
    Navigator.push(context, MaterialPageRoute(
      builder: (_) => _NoteEditorScreen(note: note),
    )).then((_) => setState(() {}));
  }

  Future<void> _confirmDelete(Note note) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Удалить заметку?'),
        content: Text('"${note.title}" будет удалена'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text('Отмена')),
          ElevatedButton(onPressed: () => Navigator.pop(context, true), child: Text('Удалить', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (ok == true) {
      await _service.deleteNote(note.id);
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF0D1117) : const Color(0xFFF5F5F5);

    final notes = _searchController.text.isEmpty
        ? _service.notes
        : _service.notes.where((n) =>
            n.title.toLowerCase().contains(_searchController.text.toLowerCase()) ||
            n.content.toLowerCase().contains(_searchController.text.toLowerCase())
          ).toList();

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        title: Text('Заметки'),
        backgroundColor: isDark ? const Color(0xFF161B22) : Colors.white,
        elevation: 0,
        actions: [
          IconButton(icon: Icon(Icons.add), onPressed: () => _openEditor()),
        ],
      ),
      body: Column(
        children: [
          // Поиск
          Padding(
            padding: EdgeInsets.all(8),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Поиск заметок...',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                contentPadding: EdgeInsets.symmetric(horizontal: 16),
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),

          // Список
          Expanded(
            child: notes.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.note_add, size: 64, color: Colors.grey[600]),
                        SizedBox(height: 16),
                        Text('Нет заметок', style: TextStyle(color: Colors.grey[400], fontSize: 18)),
                        SizedBox(height: 8),
                        Text('Нажмите + чтобы создать', style: TextStyle(color: Colors.grey[500], fontSize: 14)),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: EdgeInsets.all(8),
                    itemCount: notes.length,
                    itemBuilder: (_, i) {
                      final note = notes[i];
                      final preview = note.content.replaceAll('\n', ' ').trim();
                      return Card(
                        color: isDark ? const Color(0xFF161B22) : Colors.white,
                        child: ListTile(
                          title: Text(note.title.isEmpty ? 'Без названия' : note.title,
                            style: TextStyle(fontWeight: FontWeight.w600)),
                          subtitle: Text(
                            preview.length > 80 ? '${preview.substring(0, 80)}...' : preview,
                            maxLines: 2, overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(_formatDate(note.updatedAt), style: TextStyle(fontSize: 10, color: Colors.grey[600])),
                              SizedBox(width: 4),
                              PopupMenuButton(
                                itemBuilder: (_) => [
                                  PopupMenuItem(value: 'edit', child: Text('Редактировать')),
                                  PopupMenuItem(value: 'delete', child: Text('Удалить', style: TextStyle(color: Colors.red))),
                                ],
                                onSelected: (v) {
                                  if (v == 'edit') _openEditor(note: note);
                                  if (v == 'delete') _confirmDelete(note);
                                },
                              ),
                            ],
                          ),
                          onTap: () => _openEditor(note: note),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: Colors.amber,
        onPressed: () => _openEditor(),
        child: Icon(Icons.add, color: Colors.black),
      ),
    );
  }

  String _formatDate(DateTime dt) {
    final now = DateTime.now();
    if (dt.day == now.day && dt.month == now.month && dt.year == now.year) {
      return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    }
    return '${dt.day}.${dt.month}.${dt.year}';
  }
}

// ═══ РЕДАКТОР ═══

class _NoteEditorScreen extends StatefulWidget {
  final Note? note;
  const _NoteEditorScreen({this.note});

  @override
  State<_NoteEditorScreen> createState() => _NoteEditorScreenState();
}

class _NoteEditorScreenState extends State<_NoteEditorScreen> {
  late TextEditingController _titleController;
  late TextEditingController _contentController;
  final _service = NotesService.instance;
  bool _changed = false;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.note?.title ?? '');
    _contentController = TextEditingController(text: widget.note?.content ?? '');
    _titleController.addListener(() => _changed = true);
    _contentController.addListener(() => _changed = true);
  }

  @override
  void dispose() {
    _saveIfChanged();
    _titleController.dispose();
    _contentController.dispose();
    super.dispose();
  }

  Future<void> _saveIfChanged() async {
    if (!_changed) return;
    final title = _titleController.text.trim().isEmpty ? 'Без названия' : _titleController.text.trim();
    final content = _contentController.text;

    if (widget.note != null) {
      await _service.updateNote(widget.note!.id, title, content);
    } else {
      await _service.addNote(title, content);
    }
  }

  Future<void> _saveNow() async {
    await _saveIfChanged();
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.note != null ? 'Редактировать' : 'Новая заметка'),
        backgroundColor: isDark ? const Color(0xFF161B22) : Colors.white,
        elevation: 0,
        actions: [
          IconButton(icon: Icon(Icons.save), onPressed: _saveNow),
        ],
      ),
      body: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              controller: _titleController,
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              decoration: InputDecoration(
                hintText: 'Заголовок',
                border: InputBorder.none,
              ),
            ),
            Divider(),
            Expanded(
              child: TextField(
                controller: _contentController,
                style: TextStyle(fontSize: 16),
                maxLines: null,
                expands: true,
                textAlignVertical: TextAlignVertical.top,
                decoration: InputDecoration(
                  hintText: 'Начните писать...',
                  border: InputBorder.none,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
