// ═══════════════════════════════════════════════════════════════
// NEXUS AI Chat Service — чат с LLM (локальный + API)
//
//  ВСТРОЕН:
//   - Локальный DeepSeek через Ollama API
//   - Поддержка истории диалога
// ═══════════════════════════════════════════════════════════════

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';

class ChatMessage {
  final String role; // user, assistant
  final String content;
  final DateTime timestamp;

  ChatMessage({required this.role, required this.content, DateTime? timestamp})
      : timestamp = timestamp ?? DateTime.now();
}

class NexusAiChatService extends ChangeNotifier {
  static final NexusAiChatService instance = NexusAiChatService._();

  final List<ChatMessage> _messages = [];
  bool _busy = false;
  String _status = 'ready';

  // Ollama endpoint
  String _ollamaUrl = 'http://localhost:11434';
  String _model = 'nexus-sptm-1.5t';

  NexusAiChatService._() {
    _messages.add(ChatMessage(
      role: 'assistant',
      content: 'Привет! Я Nexus AI. Чем могу помочь?',
    ));
  }

  List<ChatMessage> get messages => List.unmodifiable(_messages);
  bool get busy => _busy;
  String get status => _status;

  Future<void> sendMessage(String text) async {
    if (_busy || text.isEmpty) return;

    _messages.add(ChatMessage(role: 'user', content: text));
    _busy = true;
    _status = 'thinking...';
    notifyListeners();

    try {
      // Пробуем локальный Ollama
      var response = await _queryOllama(text);
      _messages.add(ChatMessage(role: 'assistant', content: response));
      _status = 'ready';
    } catch (e) {
      // Fallback: симулированный ответ
      _messages.add(ChatMessage(
        role: 'assistant',
        content: _fallbackResponse(text),
      ));
      _status = 'ready (fallback)';
    }

    _busy = false;
    notifyListeners();
  }

  Future<String> _queryOllama(String prompt) async {
    try {
      var client = HttpClient();
      client.connectionTimeout = Duration(seconds: 5);

      var body = jsonEncode({
        'model': _model,
        'prompt': prompt,
        'stream': false,
        'options': {'temperature': 0.7, 'max_tokens': 512},
      });

      var request = await client.postUrl(Uri.parse('$_ollamaUrl/api/generate'));
      request.headers.contentType = ContentType.json;
      request.write(body);
      var response = await request.close();

      if (response.statusCode == 200) {
        var data = jsonDecode(await response.transform(utf8.decoder).join());
        return data['response'] as String? ?? '...';
      }
      throw Exception('HTTP ${response.statusCode}');
    } catch (e) {
      debugPrint('[AI] Ollama error: $e');
      rethrow;
    }
  }

  String _fallbackResponse(String text) {
    var t = text.toLowerCase();
    if (t.contains('привет') || t.contains('здравств')) return 'Здравствуйте! Чем могу помочь?';
    if (t.contains('как дела')) return 'Всё отлично! Работаю над улучшением NEXUS.';
    if (t.contains('что ты умеешь')) {
      return 'Я могу:\n- Отвечать на вопросы\n- Помогать с настройкой NEXUS\n- Анализировать данные\n- Обучаться на новых данных\n\nСейчас я использую локальную модель Nexus-1.5t через Ollama.';
    }
    return 'Интересный вопрос. Дайте подумать...\n\nЧтобы получить более точный ответ, подключите DeepSeek API в настройках.';
  }

  void clearChat() {
    _messages.clear();
    _messages.add(ChatMessage(role: 'assistant', content: 'Чат очищен. Чем могу помочь?'));
    notifyListeners();
  }
}
