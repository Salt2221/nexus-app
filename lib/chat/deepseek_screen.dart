// ════════════════════════════════════════════
// DeepSeek Chat Screen — интерфейс чата с ИИ
// ════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'deepseek_service.dart';

class DeepSeekChatScreen extends StatefulWidget {
  const DeepSeekChatScreen({super.key});

  @override
  State<DeepSeekChatScreen> createState() => _DeepSeekChatScreenState();
}

class _DeepSeekChatScreenState extends State<DeepSeekChatScreen> {
  final _textController = TextEditingController();
  final _scrollController = ScrollController();
  final _service = DeepSeekChatService.instance;

  @override
  void initState() {
    super.initState();
    _service.addListener(_onStateChanged);
  }

  @override
  void dispose() {
    _service.removeListener(_onStateChanged);
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onStateChanged() {
    if (mounted) setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _sendMessage() {
    final text = _textController.text.trim();
    if (text.isEmpty || _service.isLoading) return;
    _textController.clear();
    _service.sendMessage(text);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF0D1117) : const Color(0xFFF0F2F5);
    final cardColor = isDark ? const Color(0xFF161B22) : Colors.white;
    final myBubbleColor = const Color(0xFF6C63FF);
    final theirBubbleColor = isDark ? const Color(0xFF21262D) : const Color(0xFFE8E8ED);

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        title: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.auto_awesome, size: 20),
            SizedBox(width: 8),
            Text('NEXUS AI', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
          ],
        ),
        backgroundColor: const Color(0xFF6C63FF),
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          if (_service.messages.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_sweep),
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('Очистить чат?'),
                    content: const Text('История диалога будет удалена'),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Отмена')),
                      FilledButton(
                        onPressed: () { Navigator.pop(ctx); _service.clearHistory(); },
                        child: const Text('Очистить'),
                      ),
                    ],
                  ),
                );
              },
            ),
        ],
      ),
      body: Column(
        children: [
          // Сообщения
          Expanded(
            child: _service.messages.isEmpty
                ? _buildEmptyState(isDark)
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(12),
                    itemCount: _service.messages.length,
                    itemBuilder: (_, i) => _buildMessageBubble(
                      _service.messages[i],
                      myBubbleColor,
                      theirBubbleColor,
                      isDark,
                    ),
                  ),
          ),

          // Индикатор загрузки
          if (_service.isLoading)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Row(
                children: [
                  SizedBox(
                    width: 16, height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: const Color(0xFF6C63FF),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text('DeepSeek думает...', style: TextStyle(fontSize: 12, color: Colors.grey[500])),
                ],
              ),
            ),

          // Поле ввода
          _buildInputArea(cardColor, isDark),
        ],
      ),
    );
  }

  Widget _buildEmptyState(bool isDark) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.auto_awesome, size: 64, color: const Color(0xFF6C63FF).withValues(alpha: 0.3)),
          const SizedBox(height: 16),
          Text('NEXUS AI', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.black87)),
          const SizedBox(height: 8),
          Text('Задайте любой вопрос', style: TextStyle(color: Colors.grey[500], fontSize: 14)),
          const SizedBox(height: 24),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: [
              _suggestionChip('Что ты умеешь?'),
              _suggestionChip('Расскажи о VPN'),
              _suggestionChip('Как работает DPI?'),
              _suggestionChip('Напиши код на Python'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _suggestionChip(String text) {
    return ActionChip(
      label: Text(text, style: const TextStyle(fontSize: 12)),
      onPressed: () {
        _textController.text = text;
        _sendMessage();
      },
      backgroundColor: const Color(0xFF6C63FF).withValues(alpha: 0.1),
      side: BorderSide(color: const Color(0xFF6C63FF).withValues(alpha: 0.3)),
    );
  }

  Widget _buildMessageBubble(ChatMessage msg, Color myColor, Color theirColor, bool isDark) {
    final isMe = msg.role == 'user';
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isMe) ...[
            CircleAvatar(
              radius: 14,
              backgroundColor: const Color(0xFF6C63FF),
              child: const Icon(Icons.auto_awesome, size: 14, color: Colors.white),
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Container(
              constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.72),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: isMe ? myColor : theirColor,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(16),
                  topRight: const Radius.circular(16),
                  bottomLeft: Radius.circular(isMe ? 16 : 4),
                  bottomRight: Radius.circular(isMe ? 4 : 16),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    msg.content + (msg.isStreaming ? ' ▊' : ''),
                    style: TextStyle(
                      color: isMe ? Colors.white : (isDark ? Colors.white : Colors.black87),
                      fontSize: 15,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${msg.timestamp.hour.toString().padLeft(2, '0')}:${msg.timestamp.minute.toString().padLeft(2, '0')}',
                    style: TextStyle(
                      fontSize: 10,
                      color: isMe ? Colors.white60 : Colors.grey[500],
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (isMe) ...[
            const SizedBox(width: 8),
            CircleAvatar(
              radius: 14,
              backgroundColor: Colors.grey[400],
              child: const Icon(Icons.person, size: 14, color: Colors.white),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildInputArea(Color cardColor, bool isDark) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
      decoration: BoxDecoration(
        color: cardColor,
        border: Border(top: BorderSide(color: isDark ? const Color(0xFF30363D) : Colors.grey[200]!)),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _textController,
              maxLines: 4,
              minLines: 1,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _sendMessage(),
              decoration: InputDecoration(
                hintText: 'Спроси NEXUS AI...',
                hintStyle: TextStyle(color: Colors.grey[500], fontSize: 14),
                filled: true,
                fillColor: isDark ? const Color(0xFF0D1117) : const Color(0xFFF0F2F5),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(20),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              ),
              style: TextStyle(color: isDark ? Colors.white : Colors.black87),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: _sendMessage,
            child: Container(
              width: 44, height: 44,
              decoration: BoxDecoration(
                color: _service.isLoading ? Colors.grey : const Color(0xFF6C63FF),
                borderRadius: BorderRadius.circular(22),
              ),
              child: const Icon(Icons.send, color: Colors.white, size: 20),
            ),
          ),
        ],
      ),
    );
  }
}
