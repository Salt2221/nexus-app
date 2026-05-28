// ════════════════════════════════════════════
// DeepSeek Chat Service — прямой API через ключ из конфига
// ════════════════════════════════════════════

import 'dart:convert';
import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';

/// DeepSeek API endpoint (тот же что использует OpenClaw)
const _deepSeekUrl = 'https://api.deepseek.com/v1/chat/completions';
const _deepSeekKey = 'sk-333…bf56'; // из openclaw.json

class ChatMessage {
  final String role; // 'user' или 'assistant'
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
  Timer? _debounceTimer;

  List<ChatMessage> get messages => List.unmodifiable(_messages);
  bool get isLoading => _isLoading;
  String? get error => _error;

  /// Отправить сообщение и получить ответ
  Future<void> sendMessage(String text) async {
    if (text.trim().isEmpty) return;

    _messages.add(ChatMessage(role: 'user', content: text.trim()));
    _isLoading = true;
    _error = null;
    notifyListeners();

    // Добавляем пустое сообщение для стриминга
    final responseMsg = ChatMessage(role: 'assistant', content: '', isStreaming: true);
    _messages.add(responseMsg);
    notifyListeners();

    try {
      // Собираем историю для контекста
      final history = _messages
          .where((m) => !m.isStreaming)
          .map((m) => {'role': m.role, 'content': m.content})
          .toList();

      // Ограничиваем историю последними 20 сообщениями
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
          'model': 'deepseek-chat',
          'messages': [
            {'role': 'system', 'content': 'Ты — NEXUS AI, умный ассистент. Отвечай кратко и по делу. На русском.'},
            ...history,
          ],
          'temperature': 0.7,
          'max_tokens': 2000,
          'stream': false,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final content = data['choices']?[0]?['message']?['content'] ?? 'Нет ответа';
        _messages.last.content = content;
        _messages.last.isStreaming = false;
      } else {
        final errBody = response.body;
        _error = 'API ошибка ${response.statusCode}';
        _messages.removeLast();
        _messages.add(ChatMessage(
          role: 'assistant',
          content: '⚠️ Ошибка API: ${response.statusCode}\n${errBody.length > 200 ? errBody.substring(0, 200) : errBody}',
        ));
      }
    } catch (e) {
      _error = 'Ошибка соединения: $e';
      _messages.removeLast();
      _messages.add(ChatMessage(
        role: 'assistant',
        content: '⚠️ Ошибка подключения к DeepSeek API. Проверьте интернет.',
      ));
    }

    _isLoading = false;
    notifyListeners();
  }

  /// Очистить историю чата
  void clearHistory() {
    _messages.clear();
    notifyListeners();
  }
}
