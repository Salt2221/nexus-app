// ═══════════════════════════════════════════════════════════════
// NEXUS AI экран — Nexus AI чат + обучение модели
//
//  ВСТРОЕН:
//   - Чат с Nexus AI (через DeepSeek/LLM API)
//   - Обучение локальной Nexus-1.5t в фоне
//   - Загрузка датасетов через GitHub
// ═══════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';

import '../services/ai_chat_service.dart';
import '../services/model_train_service.dart';

class NexusAiScreen extends StatefulWidget {
  const NexusAiScreen({super.key});

  @override
  State<NexusAiScreen> createState() => _NexusAiScreenState();
}

class _NexusAiScreenState extends State<NexusAiScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _chatService = NexusAiChatService.instance;
  final _trainService = ModelTrainService.instance;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _chatService.addListener(() => setState(() {}));
    _trainService.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _tabController.dispose();
    _chatService.removeListener(() => setState(() {}));
    _trainService.removeListener(() => setState(() {}));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF0D1117) : const Color(0xFFF5F5F5);

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        title: Text('Nexus AI'),
        backgroundColor: isDark ? const Color(0xFF161B22) : Colors.white,
        elevation: 0,
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.amber,
          labelColor: Colors.amber,
          unselectedLabelColor: Colors.grey,
          tabs: [
            Tab(text: '💬 Чат'),
            Tab(text: '🧠 Обучение'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _ChatTab(isDark: isDark),
          _TrainTab(isDark: isDark),
        ],
      ),
    );
  }
}

// ═══ TAB 1: ЧАТ ═══

class _ChatTab extends StatefulWidget {
  final bool isDark;
  const _ChatTab({required this.isDark});

  @override
  State<_ChatTab> createState() => _ChatTabState();
}

class _ChatTabState extends State<_ChatTab> {
  final _inputController = TextEditingController();
  final _scrollController = ScrollController();

  @override
  void dispose() {
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _sendMessage() {
    final text = _inputController.text.trim();
    if (text.isEmpty) return;
    _inputController.clear();
    NexusAiChatService.instance.sendMessage(text);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final chat = NexusAiChatService.instance;
    final isDark = widget.isDark;

    return Column(
      children: [
        // Сообщения
        Expanded(
          child: ListView.builder(
            controller: _scrollController,
            padding: EdgeInsets.all(12),
            itemCount: chat.messages.length,
            itemBuilder: (_, i) {
              final msg = chat.messages[i];
              final isUser = msg.role == 'user';
              return Align(
                alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
                child: Container(
                  margin: EdgeInsets.only(bottom: 8),
                  padding: EdgeInsets.all(12),
                  constraints: BoxConstraints(maxWidth: 300),
                  decoration: BoxDecoration(
                    color: isUser
                        ? Colors.deepPurple.shade700
                        : (isDark ? const Color(0xFF1E232B) : Colors.grey[200]),
                    borderRadius: BorderRadius.circular(16).copyWith(
                      bottomRight: isUser ? Radius.zero : null,
                      bottomLeft: !isUser ? Radius.zero : null,
                    ),
                  ),
                  child: Text(msg.content,
                    style: TextStyle(color: isDark ? Colors.white : Colors.black87),
                  ),
                ),
              );
            },
          ),
        ),
        // Ввод
        Container(
          padding: EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF161B22) : Colors.white,
            border: Border(top: BorderSide(color: isDark ? const Color(0xFF30363D) : Colors.grey[200]!)),
          ),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _inputController,
                  decoration: InputDecoration(
                    hintText: 'Спросите Nexus AI...',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(24)),
                    contentPadding: EdgeInsets.symmetric(horizontal: 16),
                  ),
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => _sendMessage(),
                ),
              ),
              SizedBox(width: 8),
              CircleAvatar(
                backgroundColor: Colors.deepPurple,
                child: IconButton(
                  icon: Icon(Icons.send, color: Colors.white, size: 20),
                  onPressed: _sendMessage,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ═══ TAB 2: ОБУЧЕНИЕ ═══

class _TrainTab extends StatelessWidget {
  final bool isDark;
  const _TrainTab({required this.isDark});

  @override
  Widget build(BuildContext context) {
    final train = ModelTrainService.instance;
    return SingleChildScrollView(
      padding: EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Статус обучения
          Card(
            color: isDark ? const Color(0xFF161B22) : Colors.white,
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Column(
                children: [
                  Row(
                    children: [
                      Icon(Icons.auto_awesome, color: Colors.deepPurple, size: 32),
                      SizedBox(width: 12),
                      Expanded(child: Text('Nexus-1.5t', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
                      Switch.adaptive(
                        value: train.running,
                        onChanged: (_) {},
                      ),
                    ],
                  ),
                  SizedBox(height: 12),
                  LinearProgressIndicator(
                    value: train.progress,
                    backgroundColor: Colors.grey.shade800,
                    valueColor: AlwaysStoppedAnimation(Colors.deepPurple),
                  ),
                  SizedBox(height: 8),
                  Text('${(train.progress * 100).toStringAsFixed(1)}% | ${train.status}',
                    style: TextStyle(color: Colors.grey[400], fontSize: 13),
                  ),
                ],
              ),
            ),
          ),

          SizedBox(height: 16),

          // GitHub датасет
          Card(
            color: isDark ? const Color(0xFF161B22) : Colors.white,
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('📦 Датасеты (GitHub)', style: TextStyle(fontWeight: FontWeight.bold)),
                  SizedBox(height: 8),

                  _DatasetRow(
                    name: 'nexus-training-v1',
                    source: 'github.com/Salt2221/nexus-training',
                    isDark: isDark,
                    onSync: () => train.syncDataset('nexus-training-v1'),
                  ),
                  Divider(color: isDark ? const Color(0xFF30363D) : Colors.grey[200]),
                  _DatasetRow(
                    name: 'user-conversations',
                    source: 'Локальные чаты',
                    isDark: isDark,
                    onSync: () => train.syncDataset('user-conversations'),
                  ),
                  Divider(color: isDark ? const Color(0xFF30363D) : Colors.grey[200]),
                  _DatasetRow(
                    name: 'code-corpus',
                    source: 'github.com/Salt2221/nexus-code',
                    isDark: isDark,
                    onSync: () => train.syncDataset('code-corpus'),
                  ),

                  SizedBox(height: 16),
                  Text('Обучение происходит автоматически в фоне.',
                    style: TextStyle(color: Colors.grey[500], fontSize: 12),
                  ),
                  Text('Модель: Nexus-1.5t (Ollama, локально).',
                    style: TextStyle(color: Colors.grey[500], fontSize: 12),
                  ),
                ],
              ),
            ),
          ),

          SizedBox(height: 16),

          // Статистика
          Card(
            color: isDark ? const Color(0xFF161B22) : Colors.white,
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('📊 Статистика', style: TextStyle(fontWeight: FontWeight.bold)),
                  SizedBox(height: 8),
                  _StatRow('Итераций', train.epochs.toString()),
                  _StatRow('Сэмплов', train.samples.toString()),
                  _StatRow('Время работы', '${train.uptime} сек'),
                  _StatRow('Ошибок', train.errors.toString()),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DatasetRow extends StatelessWidget {
  final String name;
  final String source;
  final bool isDark;
  final VoidCallback onSync;

  const _DatasetRow({required this.name, required this.source, required this.isDark, required this.onSync});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(Icons.folder, size: 20, color: Colors.amber),
        SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(name, style: TextStyle(fontWeight: FontWeight.w500)),
              Text(source, style: TextStyle(color: Colors.grey[500], fontSize: 11)),
            ],
          ),
        ),
        IconButton(icon: Icon(Icons.sync, size: 20), onPressed: onSync),
      ],
    );
  }
}

class _StatRow extends StatelessWidget {
  final String label;
  final String value;
  const _StatRow(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: Colors.grey[400])),
          Text(value, style: TextStyle(fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}
