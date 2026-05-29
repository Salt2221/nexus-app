// ════════════════════════════════════════════
// NEXUS AI Service — Ollama (локально) + DeepSeek API fallback
// ════════════════════════════════════════════

import 'dart:convert';
import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';

/// Ollama endpoint (локальная модель)
const _ollamaUrl = 'http://10.0.2.2:11434/api/chat';
const _ollamaModel = 'nexus-sptm-1.5t';
/// DeepSeek API как fallback
const _deepSeekUrl = 'https://api.deepseek.com/chat/completions';
const _deepSeekKey = 'sk-3337858918b340628bc2f69d97f6bf56';
const _deepSeekModel = 'deepseek-chat';

class ChatMessage {
  final String role;
  String content;
  final DateTime timestamp;
  bool isStreaming;

  ChatMessage({
    required this.role,
    required this.content,
    DateTime? timestamp,
    this.isStreaming = false,
  }) : timestamp = timestamp ?? DateTime.now();
}

class DeepSeekChatService extends ChangeNotifier {
  DeepSeekChatService._();
  static final DeepSeekChatService instance = DeepSeekChatService._();

  final List<ChatMessage> _messages = [];
  bool _isLoading = false;
  String? _error;

  List<ChatMessage> get messages => List.unmodifiable(_messages);
  bool get isLoading => _isLoading;
  String? get error => _error;

  /// Отправить сообщение, получить ответ (Ollama -> DeepSeek fallback)
  Future<void> sendMessage(String text) async {
    if (text.trim().isEmpty) return;

    _messages.add(ChatMessage(role: 'user', content: text.trim()));
    _isLoading = true;
    _error = null;
    notifyListeners();

    final responseMsg = ChatMessage(role: 'assistant', content: '', isStreaming: true);
    _messages.add(responseMsg);
    notifyListeners();

    try {
      // Сначала пробуем Ollama
      final success = await _tryOllama();
      if (!success) {
        // Fallback на DeepSeek API
        await _tryDeepSeek();
      }
    } catch (e) {
      _error = 'Ошибка соединения: $e';
      _messages.removeLast();
      _messages.add(ChatMessage(
        role: 'assistant',
        content: '⚠️ Ошибка подключения. Проверьте, запущен ли Ollama на сервере.',
      ));
    }

    _isLoading = false;
    notifyListeners();
  }

  Future<bool> _tryOllama() async {
    try {
      final history = _messages
          .where((m) => !m.isStreaming)
          .map((m) => {'role': m.role, 'content': m.content})
          .toList();

      if (history.length > 20) {
        final trimmed = history.sublist(history.length - 20);
        history.clear();
        history.addAll(trimmed);
      }

      final response = await http.post(
        Uri.parse(_ollamaUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'model': _ollamaModel,
          'messages': [
            {'role': 'system', 'content': 'Ты — NEXUS AI, умный ассистент. Отвечай кратко и по делу. На русском.'},
            ...history,
          ],
          'stream': false,
          'options': {
            'temperature': 0.7,
            'num_predict': 2000,
          },
        }),
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final content = data['message']?['content'] ?? 'Нет ответа';
        _messages.last.content = content;
        _messages.last.isStreaming = false;
        return true;
      }
      return false; // fallback
    } catch (_) {
      return false; // Ollama не доступен, fallback
    }
  }

  Future<bool> _tryDeepSeek() async {
    try {
      final history = _messages
          .where((m) => !m.isStreaming)
          .map((m) => {'role': m.role, 'content': m.content})
          .toList();

      if (history.length > 20) {
        final trimmed = history.sublist(history.length - 20);
        history.clear();
        history.addAll(trimmed);
      }

      final response = await http.post(
        Uri.parse(_deepSeekUrl),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $_deepSeekKey',
        },
        body: jsonEncode({
          'model': _deepSeekModel,
          'messages': [
            {'role': 'system', 'content': 'Ты — NEXUS AI, умный ассистент. Отвечай кратко и по делу. На русском.'},
            ...history,
          ],
          'temperature': 0.7,
          'max_tokens': 2000,
          'stream': false,
        }),
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final content = data['choices']?[0]?['message']?['content'] ?? 'Нет ответа';
        _messages.last.content = content;
        _messages.last.isStreaming = false;
        return true;
      }

      final errBody = response.body;
      final errMsg = errBody.length > 200 ? errBody.substring(0, 200) : errBody;
      _error = 'Ошибка API DeepSeek (${response.statusCode})';
      _messages.removeLast();
      _messages.add(ChatMessage(
        role: 'assistant',
        content: '⚠️ Ошибка API: ${response.statusCode}\n$errMsg',
      ));
      return false;
    } catch (e) {
      _error = 'Ошибка соединения с DeepSeek: $e';
      _messages.removeLast();
      _messages.add(ChatMessage(
        role: 'assistant',
        content: '⚠️ Не удалось подключиться ни к Ollama, ни к DeepSeek API.',
      ));
      return false;
    }
  }

  void clearHistory() {
    _messages.clear();
    notifyListeners();
  }
}
