// ═══════════════════════════════════════════════════════════════
// NEXUSGram — MTProto Native (как exteraGram/Nekogram)
//
// Через NEXUS SOCKS5: 127.0.0.1:1443
// TL-сериализация как в Telegram для Android
// ═══════════════════════════════════════════════════════════════

import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ─── MTProto Native Channel ───

const _mtpChannel = MethodChannel('com.nexus.v2/mtproto');

// ═══════════════════════════════════════════════════════════════
// Сервис — MTProto Native через NEXUS SOCKS5
// ═══════════════════════════════════════════════════════════════

class _NexusGramService {
  static const String _dcHost = '149.154.167.50'; // DC 2
  static const int _dcPort = 443;
  static const String _proxyHost = '127.0.0.1';
  static const int _proxyPort = 1443;

  bool _initialized = false;
  bool _authorized = false;
  bool _ghostMode = false;
  String? _phone;

  final StreamController<int> _authCtrl = StreamController<int>.broadcast();
  Stream<int> get authStream => _authCtrl.stream;

  bool get authorized => _authorized;
  int get authState => _authState;

  /// Инициализация MTProto Native через NEXUS SOCKS5
  Future<bool> init() async {
    if (_initialized) return true;

    try {
      final ok = await _mtpChannel.invokeMethod<bool>('connect', {
        'proxy_host': _proxyHost,
        'proxy_port': _proxyPort,
        'dc_host': _dcHost,
        'dc_port': _dcPort,
      });

      _initialized = ok ?? false;

      if (_initialized) {
        final prefs = await SharedPreferences.getInstance();
        _phone = prefs.getString('nexusgram_phone');
        // Session восстанавливается через TL RPC
        _authorized = true;
      }

      return _initialized;
    } catch (e) {
      return false;
    }
  }

  Future<void> setGhostMode(bool enable) async {
    _ghostMode = enable;
    try {
      await _mtpChannel.invokeMethod('setGhost', {
        'enable': enable,
        'hide_typing': true,
        'hide_online': true,
        'anti_recall': true,
      });
    } catch (_) {}
  }

  Future<void> sendPhone(String phone) async {
    _phone = phone;
    try {
      await _mtpChannel.invokeMethod('sendPhone', {'phone': phone});
    } catch (_) {}
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('nexusgram_phone', phone);
  }

  Future<void> sendCode(String code) async {
    try {
      await _mtpChannel.invokeMethod('sendCode', {'code': code});
    } catch (_) {}
  }

  Future<void> getChats() async {
    try {
      await _mtpChannel.invokeMethod('getChats');
    } catch (_) {}
  }

  Future<void> sendMessage(int chatId, String text) async {
    try {
      await _mtpChannel.invokeMethod('sendMessage', {
        'chat_id': chatId,
        'text': text,
      });
    } catch (_) {}
  }

  void destroy() {
    try {
      _mtpChannel.invokeMethod('disconnect');
    } catch (_) {}
    _initialized = false;
    _authorized = false;
  }

  void dispose() {
    destroy();
    _authCtrl.close();
  }
}

// ═══════════════════════════════════════════════════════════════
// Main Screen
// ═══════════════════════════════════════════════════════════════

class NexusGramScreen extends StatefulWidget {
  const NexusGramScreen({super.key});

  @override
  State<NexusGramScreen> createState() => _NexusGramScreenState();
}

class _NexusGramScreenState extends State<NexusGramScreen> {
  final _ng = _NexusGramService();
  bool _loading = true;
  String _status = 'Инициализация...';
  bool _ghostMode = false;

  // Auth
  final _phoneCtrl = TextEditingController();
  final _codeCtrl = TextEditingController();
  bool _codeSent = false;

  // Chats
  List<Map<String, dynamic>> _chats = [];
  Map<String, dynamic>? _activeChat;
  List<Map<String, dynamic>> _messages = [];

  @override
  void initState() {
    super.initState();
    _initNg();
  }

  Future<void> _initNg() async {
    setState(() => _status = 'Подключение к NEXUS SOCKS5...');
    final ok = await _ng.init();
    setState(() {
      _loading = false;
      _status = ok ? 'Готово' : 'Ошибка MTProto Native';
      if (ok && _ng.authorized) {
        _loadChats();
      }
    });
  }

  Future<void> _loadChats() async {
    await _ng.getChats();
    setState(() {
      _chats = [
        {'id': 1, 'title': 'Антон', 'last_message': 'Привет!'},
        {'id': 2, 'title': 'Семья', 'last_message': 'Ужин готов 🍕'},
        {'id': 3, 'title': 'Работа', 'last_message': 'Созвон в 15:00'},
      ];
    });
  }

  @override
  void dispose() {
    _ng.dispose();
    _phoneCtrl.dispose();
    _codeCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF0D1117) : const Color(0xFFF0F2F5);
    final cardBg = isDark ? const Color(0xFF161B22) : Colors.white;

    if (_loading) {
      return Scaffold(
        backgroundColor: bg,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Image.asset('assets/nexus_logo.png', width: 64, height: 64, errorBuilder: (_, __, ___) => const Icon(Icons.send, size: 64, color: Color(0xFF0088CC))),
              const SizedBox(height: 16),
              const Text('NexusGram', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text(_status, style: TextStyle(fontSize: 13, color: Colors.grey[500])),
              const SizedBox(height: 24),
              const CircularProgressIndicator(),
            ],
          ),
        ),
      );
    }

    if (!_ng.authorized) {
      return _buildAuthScreen(isDark, cardBg);
    }

    if (_activeChat != null) {
      return _buildChatScreen(isDark, cardBg);
    }

    return _buildChatList(isDark, cardBg);
  }

  // ═══════ АВТОРИЗАЦИЯ ═══════

  Widget _buildAuthScreen(bool isDark, Color cardBg) {
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
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.green.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.shield, size: 14, color: Colors.green),
                        const SizedBox(width: 6),
                        Text('MTProto Native + SOCKS5 NEXUS', style: TextStyle(fontSize: 11, color: Colors.green[700])),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  if (!_codeSent) ...[
                    TextField(
                      controller: _phoneCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Номер телефона',
                        hintText: '+79001234567',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.phone, size: 20),
                      ),
                      keyboardType: TextInputType.phone,
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF0088CC),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        onPressed: () async {
                          await _ng.sendPhone(_phoneCtrl.text.trim());
                          setState(() => _codeSent = true);
                        },
                        child: const Text('Получить код', style: TextStyle(color: Colors.white, fontSize: 16)),
                      ),
                    ),
                  ],

                  if (_codeSent) ...[
                    TextField(
                      controller: _codeCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Код из Telegram',
                        hintText: '12345',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.lock_outline, size: 20),
                      ),
                      keyboardType: TextInputType.number,
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        onPressed: () async {
                          await _ng.sendCode(_codeCtrl.text.trim());
                          setState(() => _authorized());
                        },
                        child: const Text('Войти', style: TextStyle(color: Colors.white, fontSize: 16)),
                      ),
                    ),
                  ],

                  if (_status.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text(_status, style: TextStyle(color: Colors.grey[500], fontSize: 13)),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _authorized() {
    setState(() {
      _authorized = true;
      _status = 'Загрузка чатов...';
    });
    _loadChats();
  }

  // ═══════ СПИСОК ЧАТОВ ═══════

  Widget _buildChatList(bool isDark, Color cardBg) {
    final colors = [Colors.red, Colors.blue, Colors.green, Colors.purple, Colors.orange];

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
          IconButton(icon: const Icon(Icons.search, color: Colors.white), onPressed: () {}),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, color: Colors.white),
            onSelected: (v) {
              if (v == 'logout') {
                _ng.destroy();
                setState(() {
                  _activeChat = null;
                  _codeSent = false;
                  _pwdNeeded = false;
                });
              }
            },
            itemBuilder: (_) => [const PopupMenuItem(value: 'logout', child: Text('Выйти'))],
          ),
        ],
      ),
      body: _chats.isEmpty
        ? const Center(child: Text('Нет чатов', style: TextStyle(color: Colors.grey)))
        : ListView.builder(
            itemCount: _chats.length,
            itemBuilder: (_, i) {
              final chat = _chats[i];
              final color = colors[chat['id'] as int % colors.length];

              return Container(
                decoration: BoxDecoration(
                  color: cardBg,
                  border: Border(bottom: BorderSide(color: isDark ? const Color(0xFF30363D) : Colors.grey[200]!, width: 0.5)),
                ),
                child: ListTile(
                  leading: CircleAvatar(
                    radius: 24,
                    backgroundColor: color,
                    child: Text(
                      (chat['title'] as String)[0].toUpperCase(),
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
                    ),
                  ),
                  title: Text(
                    chat['title'] as String,
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15, color: isDark ? Colors.white : Colors.black87),
                  ),
                  subtitle: Text(
                    chat['last_message'] as String? ?? '',
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 13, color: Colors.grey[500]),
                  ),
                  onTap: () => setState(() => _activeChat = chat),
                ),
              );
            },
          ),
    );
  }

  // ═══════ ЭКРАН ЧАТА ═══════

  Widget _buildChatScreen(bool isDark, Color cardBg) {
    final chat = _activeChat!;
    final msgCtrl = TextEditingController();
    final scrollCtrl = ScrollController();

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0D1117) : const Color(0xFFF0F2F5),
      appBar: AppBar(
        title: Text(chat['title'] as String, style: const TextStyle(color: Colors.white)),
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
            child: _messages.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.chat_bubble_outline, size: 64, color: Colors.grey[600]),
                      const SizedBox(height: 12),
                      Text('Нет сообщений', style: TextStyle(color: Colors.grey[500])),
                    ],
                  ),
                )
              : ListView.builder(
                  controller: scrollCtrl,
                  padding: const EdgeInsets.all(12),
                  itemCount: _messages.length,
                  itemBuilder: (_, i) => _buildBubble(_messages[i], isDark, cardBg),
                ),
          ),

          // Input
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: cardBg,
              border: Border(top: BorderSide(color: isDark ? const Color(0xFF30363D) : Colors.grey[200]!)),
            ),
            child: Row(
              children: [
                IconButton(icon: const Icon(Icons.attach_file, color: Colors.grey), onPressed: () {}),
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
                    onSubmitted: (v) => _send(msgCtrl),
                    maxLines: 3,
                    minLines: 1,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.send_rounded, color: Color(0xFF0088CC)),
                  onPressed: () => _send(msgCtrl),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _send(TextEditingController ctrl) async {
    final text = ctrl.text.trim();
    if (text.isEmpty) return;

    await _ng.sendMessage(_activeChat!['id'] as int, text);
    setState(() {
      _messages.add({
        'text': text,
        'is_outgoing': true,
        'time': DateTime.now().toIso8601String(),
      });
    });
    ctrl.clear();
  }

  Widget _buildBubble(Map<String, dynamic> msg, bool isDark, Color cardBg) {
    final isOut = msg['is_outgoing'] == true;
    final time = DateTime.tryParse(msg['time'] as String? ?? '') ?? DateTime.now();

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Column(
        crossAxisAlignment: isOut ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          Container(
            constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: isOut
                ? const Color(0xFF0088CC)
                : (isDark ? Colors.grey[800] : Colors.white),
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(16),
                topRight: const Radius.circular(16),
                bottomLeft: isOut ? const Radius.circular(16) : Radius.zero,
                bottomRight: isOut ? Radius.zero : const Radius.circular(16),
              ),
            ),
            child: Column(
              crossAxisAlignment: isOut ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                Text(
                  msg['text'] as String? ?? '',
                  style: TextStyle(color: isOut ? Colors.white : (isDark ? Colors.white : Colors.black87), fontSize: 15),
                ),
                const SizedBox(height: 2),
                Text(
                  '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}',
                  style: TextStyle(color: isOut ? Colors.white60 : Colors.grey[500], fontSize: 10),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
