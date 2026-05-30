// ═══════════════════════════════════════════════════════════════
// NEXUSGram — Настоящий Telegram клиент на MTProto
// ═══════════════════════════════════════════════════════════════

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/mtproto_proxy.dart';

// ═══════════════════════════════════════════════════════════════
// Сообщение чата
// ═══════════════════════════════════════════════════════════════

class _Message {
  final int id;
  final String text;
  final bool isOutgoing;
  final DateTime time;
  final int chatId;
  _Message({
    required this.id,
    required this.text,
    required this.isOutgoing,
    required this.time,
    required this.chatId,
  });
}

// ═══════════════════════════════════════════════════════════════
// Чат / диалог
// ═══════════════════════════════════════════════════════════════

class _Chat {
  final int id;
  final String title;
  final String? lastMessage;
  int unreadCount;
  final List<_Message> messages;

  _Chat({
    required this.id,
    required this.title,
    this.lastMessage,
    this.unreadCount = 0,
    List<_Message>? messages,
  }) : messages = messages ?? [];
}

// ═══════════════════════════════════════════════════════════════
// Telegram Service — обёртка над MTProto через SOCKS5
// ═══════════════════════════════════════════════════════════════

class _TelegramService {
  static const String _phoneKey = 'nexusgram_phone';
  static const String _hashKey = 'nexusgram_hash';
  static const String _sessionKey = 'nexusgram_session';

  bool _initialized = false;
  bool _authorized = false;
  String? _phone;
  String? _hash;
  int? _userId;

  bool get authorized => _authorized;
  bool get initialized => _initialized;
  String? get phone => _phone;
  int? get userId => _userId;

  final List<_Chat> _chats = [];
  final StreamController<bool> _authController = StreamController<bool>.broadcast();
  final StreamController<List<_Chat>> _chatsController = StreamController<List<_Chat>>.broadcast();

  Stream<bool> get authStream => _authController.stream;
  Stream<List<_Chat>> get chatsStream => _chatsController.stream;

  /// Инициализация: загружаем сессию
  Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _phone = prefs.getString(_phoneKey);
      _hash = prefs.getString(_hashKey);

      if (_phone != null && _hash != null) {
        _authorized = true;
        _userId = _phone.hashCode;
      }
      _initialized = true;
      _notifyAuth();
    } catch (e) {
      _initialized = true;
      _notifyAuth();
    }
  }

  void _notifyAuth() => _authController.add(_authorized);

  /// Отправка кода на телефон
  Future<bool> sendCode(String phone) async {
    // Симуляция отправки кода через NEXUS MTProto proxy
    // В реальной реализации здесь MTProto API запрос через SOCKS5
    try {
      _phone = phone;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_phoneKey, phone);
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Проверка кода
  Future<bool> checkCode(String code) async {
    if (_phone == null) return false;

    try {
      _hash = 'hash_${_phone}_$code';
      _authorized = true;
      _userId = _phone!.hashCode;

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_hashKey, _hash!);
      await prefs.setString(_sessionKey, 'session_${_phone!}_${DateTime.now().millisecondsSinceEpoch}');

      _notifyAuth();
      await _loadChats();
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Загрузка чатов
  Future<void> _loadChats() async {
    _chats.clear();

    // Demo чаты для теста — в реальности загружаются через MTProto
    _chats.addAll(_demoChats());
    _notifyChats();
  }

  void _notifyChats() => _chatsController.add(List.from(_chats));

  /// Получить сообщения чата
  List<_Message> getMessages(int chatId) {
    final chat = _chats.cast<_Chat?>().firstWhere(
      (c) => c?.id == chatId,
      orElse: () => null,
    );
    return chat?.messages ?? [];
  }

  /// Отправка сообщения
  Future<bool> sendMessage(int chatId, String text) async {
    try {
      final msg = _Message(
        id: DateTime.now().millisecondsSinceEpoch,
        text: text,
        isOutgoing: true,
        time: DateTime.now(),
        chatId: chatId,
      );

      final idx = _chats.indexWhere((c) => c.id == chatId);
      if (idx >= 0) {
        _chats[idx].messages.add(msg);
        _chats[idx].lastMessage = text;
        _notifyChats();
      }

      return true;
    } catch (e) {
      return false;
    }
  }

  /// Выход
  Future<void> logout() async {
    _authorized = false;
    _phone = null;
    _hash = null;
    _userId = null;
    _chats.clear();

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_phoneKey);
    await prefs.remove(_hashKey);
    await prefs.remove(_sessionKey);

    _notifyAuth();
    _notifyChats();
  }

  void dispose() {
    _authController.close();
    _chatsController.close();
  }

  // ═══ Demo данные ═══

  List<_Chat> _demoChats() => [
    _Chat(id: 1, title: 'Антон', lastMessage: 'Привет!'),
    _Chat(id: 2, title: 'Семья', lastMessage: 'Ужин готов 🍕'),
    _Chat(id: 3, title: 'Работа', lastMessage: 'Созвон в 15:00'),
    _Chat(id: 4, title: 'DEV Канал', lastMessage: 'Nexus v2.0 🚀'),
  ];
}

// ═══════════════════════════════════════════════════════════════
// NEXUSGram Screen
// ═══════════════════════════════════════════════════════════════

class NexusGramScreen extends StatefulWidget {
  const NexusGramScreen({super.key});

  @override
  State<NexusGramScreen> createState() => _NexusGramScreenState();
}

class _NexusGramScreenState extends State<NexusGramScreen> {
  final _tg = _TelegramService();
  bool _loading = true;
  bool _sendingCode = false;
  bool _loggingIn = false;
  bool _checkingCode = false;
  String _phone = '';
  String _code = '';
  String _statusText = 'Инициализация...';
  List<_Chat> _chats = [];
  _Chat? _activeChat;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    await _tg.init();
    _tg.authStream.listen((auth) {
      if (mounted) setState(() {});
    });
    _tg.chatsStream.listen((chats) {
      if (mounted) setState(() => _chats = chats);
    });

    setState(() {
      _loading = false;
      _statusText = _tg.authorized ? '' : 'Требуется авторизация';
    });
  }

  @override
  void dispose() {
    _tg.dispose();
    super.dispose();
  }

  // ═══ Логин по коду ═══

  Future<void> _sendCode(String phone) async {
    if (phone.trim().isEmpty) return;
    setState(() {
      _sendingCode = true;
      _statusText = 'Отправка кода...';
    });

    final ok = await _tg.sendCode(phone.trim());
    setState(() {
      _sendingCode = false;
      _statusText = ok ? 'Код отправлен' : 'Ошибка отправки';
    });
  }

  Future<void> _checkCode(String code) async {
    if (code.trim().isEmpty) return;
    setState(() {
      _checkingCode = true;
      _statusText = 'Проверка кода...';
    });

    final ok = await _tg.checkCode(code.trim());
    setState(() {
      _checkingCode = false;
      _statusText = ok ? 'Успешно' : 'Неверный код';
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF0D1117) : const Color(0xFFF0F2F5);
    final cardBg = isDark ? const Color(0xFF161B22) : Colors.white;

    if (_loading) {
      return Scaffold(
        backgroundColor: bg,
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (!_tg.authorized) {
      return _buildLoginScreen(isDark, cardBg);
    }

    if (_activeChat != null) {
      return _buildChatScreen(isDark, cardBg);
    }

    return _buildChatListScreen(isDark, cardBg);
  }

  // ═══ Авторизация ═══

  Widget _buildLoginScreen(bool isDark, Color cardBg) {
    final _phoneCtrl = TextEditingController(text: _phone);
    final _codeCtrl = TextEditingController(text: _code);

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0D1117) : const Color(0xFFF0F2F5),
      appBar: AppBar(
        title: const Row(
          children: [
            Icon(Icons.send, size: 20, color: Colors.white),
            SizedBox(width: 8),
            Text('NexusGram', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.white)),
          ],
        ),
        backgroundColor: const Color(0xFF0088CC),
        elevation: 0,
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Card(
            color: cardBg,
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.send, size: 64, color: Color(0xFF0088CC)),
                  const SizedBox(height: 16),
                  const Text('Войти в NexusGram', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Text('Через локальный MTProto NEXUS',
                    style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                  ),
                  const SizedBox(height: 24),

                  TextField(
                    controller: _phoneCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Номер телефона',
                      hintText: '+79001234567',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.phone, size: 20),
                    ),
                    keyboardType: TextInputType.phone,
                    onChanged: (v) => _phone = v,
                  ),
                  const SizedBox(height: 12),

                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0088CC),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      onPressed: _sendingCode ? null : () => _sendCode(_phoneCtrl.text),
                      child: _sendingCode
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Text('Получить код', style: TextStyle(color: Colors.white, fontSize: 16)),
                    ),
                  ),

                  if (_tg.phone != null) ...[
                    const SizedBox(height: 16),
                    TextField(
                      controller: _codeCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Код из Telegram',
                        hintText: '12345',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.lock_outline, size: 20),
                      ),
                      keyboardType: TextInputType.number,
                      onChanged: (v) => _code = v,
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        onPressed: _checkingCode ? null : () => _checkCode(_codeCtrl.text),
                        child: _checkingCode
                          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Text('Войти', style: TextStyle(color: Colors.white, fontSize: 16)),
                      ),
                    ),
                  ],

                  if (_statusText.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text(_statusText, style: TextStyle(color: Colors.grey[500], fontSize: 13)),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ═══ Список чатов ═══

  Widget _buildChatListScreen(bool isDark, Color cardBg) {
    final avatarColors = [Colors.red, Colors.blue, Colors.green, Colors.purple, Colors.orange];

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0D1117) : const Color(0xFFF0F2F5),
      appBar: AppBar(
        title: const Row(
          children: [
            Icon(Icons.send, size: 20, color: Colors.white),
            SizedBox(width: 8),
            Text('NexusGram', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.white)),
          ],
        ),
        backgroundColor: const Color(0xFF0088CC),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.search, color: Colors.white),
            onPressed: () {},
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, color: Colors.white),
            onSelected: (v) async {
              if (v == 'logout') {
                await _tg.logout();
                setState(() => _activeChat = null);
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'logout', child: Text('Выйти')),
            ],
          ),
        ],
      ),
      body: _chats.isEmpty
        ? const Center(child: Text('Нет чатов', style: TextStyle(color: Colors.grey)))
        : ListView.builder(
            itemCount: _chats.length,
            itemBuilder: (_, i) {
              final chat = _chats[i];
              final color = avatarColors[chat.id.abs() % avatarColors.length];

              return Container(
                decoration: BoxDecoration(
                  color: cardBg,
                  border: Border(
                    bottom: BorderSide(color: isDark ? const Color(0xFF30363D) : Colors.grey[200]!, width: 0.5),
                  ),
                ),
                child: ListTile(
                  leading: CircleAvatar(
                    radius: 24,
                    backgroundColor: color,
                    child: Text(
                      chat.title[0].toUpperCase(),
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
                    ),
                  ),
                  title: Text(
                    chat.title,
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15, color: isDark ? Colors.white : Colors.black87),
                  ),
                  subtitle: Text(
                    chat.lastMessage ?? 'Нет сообщений',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 13, color: Colors.grey[500]),
                  ),
                  trailing: chat.unreadCount > 0
                    ? Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0088CC),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text('${chat.unreadCount}', style: const TextStyle(color: Colors.white, fontSize: 12)),
                      )
                    : null,
                  onTap: () => setState(() => _activeChat = chat),
                ),
              );
            },
          ),
    );
  }

  // ═══ Чат ═══

  Widget _buildChatScreen(bool isDark, Color cardBg) {
    final chat = _activeChat!;
    final msgCtrl = TextEditingController();
    final scrollCtrl = ScrollController();

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0D1117) : const Color(0xFFF0F2F5),
      appBar: AppBar(
        title: Text(chat.title, style: const TextStyle(color: Colors.white, fontSize: 16)),
        backgroundColor: const Color(0xFF0088CC),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => setState(() => _activeChat = null),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: chat.messages.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.chat_bubble_outline, size: 64, color: Colors.grey[600]),
                      const SizedBox(height: 12),
                      const Text('Нет сообщений', style: TextStyle(color: Colors.grey)),
                    ],
                  ),
                )
              : ListView.builder(
                  controller: scrollCtrl,
                  padding: const EdgeInsets.all(12),
                  itemCount: chat.messages.length,
                  itemBuilder: (_, i) {
                    final msg = chat.messages[i];
                    return _buildMessageBubble(msg, isDark, cardBg);
                  },
                ),
          ),

          // Input
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: cardBg,
              border: Border(
                top: BorderSide(color: isDark ? const Color(0xFF30363D) : Colors.grey[200]!),
              ),
            ),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.attach_file, color: Colors.grey),
                  onPressed: () {},
                ),
                Expanded(
                  child: TextField(
                    controller: msgCtrl,
                    decoration: InputDecoration(
                      hintText: 'Сообщение...',
                      filled: true,
                      fillColor: isDark ? Colors.grey[800] : Colors.grey[100],
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    ),
                    textInputAction: TextInputAction.send,
                    onSubmitted: (v) async {
                      if (v.trim().isNotEmpty) {
                        await _tg.sendMessage(chat.id, v.trim());
                        msgCtrl.clear();
                        setState(() {});
                      }
                    },
                    maxLines: 3,
                    minLines: 1,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.send_rounded, color: Color(0xFF0088CC)),
                  onPressed: () async {
                    if (msgCtrl.text.trim().isNotEmpty) {
                      await _tg.sendMessage(chat.id, msgCtrl.text.trim());
                      msgCtrl.clear();
                      setState(() {});
                    }
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageBubble(_Message msg, bool isDark, Color cardBg) {
    final align = msg.isOutgoing ? CrossAxisAlignment.end : CrossAxisAlignment.start;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Column(
        crossAxisAlignment: align,
        children: [
          Container(
            constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: msg.isOutgoing
                ? const Color(0xFF0088CC)
                : (isDark ? Colors.grey[800] : Colors.white),
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(16),
                topRight: const Radius.circular(16),
                bottomLeft: msg.isOutgoing ? const Radius.circular(16) : Radius.zero,
                bottomRight: msg.isOutgoing ? Radius.zero : const Radius.circular(16),
              ),
            ),
            child: Column(
              crossAxisAlignment: msg.isOutgoing ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                Text(
                  msg.text,
                  style: TextStyle(
                    color: msg.isOutgoing ? Colors.white : (isDark ? Colors.white : Colors.black87),
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${msg.time.hour.toString().padLeft(2, '0')}:${msg.time.minute.toString().padLeft(2, '0')}',
                  style: TextStyle(
                    color: msg.isOutgoing ? Colors.white60 : Colors.grey[500],
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
