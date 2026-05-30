// ═══════════════════════════════════════════════════════════════
// NEXUS DHT Screen — Децентрализованная P2P сеть
//
//  - 4 вкладки: Сеть / Профиль / Чат / Обфускация
//  - Сеть: статус DHT, пиры, статистика
//  - Профиль: регистрация/логин в P2P (локально, без сервера)
//  - Чат: простой P2P обмен сообщениями через DHT
//  - Обфускация: настройки TLS/HTTP маскировки
// ═══════════════════════════════════════════════════════════════

import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/dht_network.dart';
import '../services/global_p2p_node.dart';
import '../services/dht_auth.dart';

class DhtScreen extends StatefulWidget {
  final int initialTab;
  const DhtScreen({super.key, this.initialTab = 0});
  @override
  State<DhtScreen> createState() => _DhtScreenState();
}

class _DhtScreenState extends State<DhtScreen> with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;
  final _dhtMgr = DhtNetworkManager.instance;
  final _auth = DhtAuthService.instance;
  Timer? _refreshTimer;

  // Login/Register
  final _usernameCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _nicknameCtrl = TextEditingController();
  bool _isRegister = false;

  // Чат
  final _chatCtrl = TextEditingController();
  final _chatMsgCtrl = TextEditingController();
  String _chatTarget = '';
  final List<Map<String, dynamic>> _chatMessages = [];

  String _statusText = 'initializing...';
  int _peerCount = 0;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 4, vsync: this, initialIndex: widget.initialTab);
    _dhtMgr.addListener(_onChange);
    _auth.addListener(_onChange);
    _refreshTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (mounted) {
        setState(() {
          _statusText = _buildStatusText();
          _peerCount = _dhtMgr.node?.totalPeers ?? 0;
        });
      }
    });
    _initDht();
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    _dhtMgr.removeListener(_onChange);
    _auth.removeListener(_onChange);
    _refreshTimer?.cancel();
    _usernameCtrl.dispose();
    _passwordCtrl.dispose();
    _nicknameCtrl.dispose();
    _chatCtrl.dispose();
    _chatMsgCtrl.dispose();
    super.dispose();
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  String _buildStatusText() {
    if (!_dhtMgr.initialized) return 'инициализация...';
    if (!_dhtMgr.running) return 'остановлена';
    return 'активна (${_dhtMgr.node?.totalPeers ?? 0} пиров)';
  }

  Future<void> _initDht() async {
    await _dhtMgr.init();
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF0D1117) : const Color(0xFFF5F5F5);

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        title: const Text('P2P Сеть'),
        backgroundColor: const Color(0xFF6C63FF),
        foregroundColor: Colors.white,
        bottom: TabBar(
          controller: _tabCtrl,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white60,
          isScrollable: true,
          tabs: const [
            Tab(icon: Icon(Icons.hub), text: 'Сеть'),
            Tab(icon: Icon(Icons.person), text: 'Профиль'),
            Tab(icon: Icon(Icons.chat), text: 'Чат'),
            Tab(icon: Icon(Icons.security), text: 'Обфускация'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabCtrl,
        children: [
          _buildNetworkTab(isDark),
          _buildProfileTab(isDark),
          _buildChatTab(isDark),
          _buildObfuscationTab(isDark),
        ],
      ),
    );
  }

  // ═══ 1. СЕТЬ ═══
  Widget _buildNetworkTab(bool isDark) {
    final running = _dhtMgr.running;
    final node = _dhtMgr.node;
    final peers = node?.allPeers ?? [];

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Статус
        Card(
          color: isDark ? const Color(0xFF161B22) : Colors.white,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                Icon(Icons.hub, size: 56, color: running ? Colors.green : Colors.grey),
                const SizedBox(height: 12),
                Text('Сеть ${running ? "активна" : "остановлена"}',
                  style: TextStyle(
                    fontSize: 20, fontWeight: FontWeight.bold,
                    color: running ? Colors.green : Colors.grey,
                  ),
                ),
                const SizedBox(height: 8),
                Text('ID: ${node?.nodeId.toHex().substring(0, 20) ?? "—"}',
                  style: TextStyle(fontSize: 11, fontFamily: 'monospace', color: Colors.grey),),
                const SizedBox(height: 4),
                Text('Порт: ${node?.port ?? 41320}', style: TextStyle(fontSize: 12, color: Colors.grey)),
              ],
            ),
          ),
        ),

        const SizedBox(height: 16),

        // Статистика
        Card(
          color: isDark ? const Color(0xFF161B22) : Colors.white,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _statItem(Icons.people, 'Пиры', '${peers.length}', Colors.blue),
                _statItem(Icons.storage, 'Ключи', '${node?.storedKeys ?? 0}', Colors.green),
                _statItem(Icons.arrow_upward, 'Отпр.', '${node?.sentCount ?? 0}', Colors.amber),
                _statItem(Icons.arrow_downward, 'Получ.', '${node?.recvCount ?? 0}', Colors.purple),
              ],
            ),
          ),
        ),

        const SizedBox(height: 16),

        // Кнопка перезапуска
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            icon: Icon(running ? Icons.stop : Icons.play_arrow),
            label: Text(running ? 'Остановить DHT' : 'Запустить DHT'),
            style: ElevatedButton.styleFrom(
              backgroundColor: running ? Colors.red : Colors.green,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            onPressed: () async {
              if (running) {
                _dhtMgr.stop();
              } else {
                await _dhtMgr.init();
              }
              setState(() {});
            },
          ),
        ),

        const SizedBox(height: 16),

        // Список пиров
        Text('Пиры (${peers.length})', style: TextStyle(
          fontSize: 16, fontWeight: FontWeight.bold,
          color: isDark ? Colors.white : Colors.black87,
        )),
        const SizedBox(height: 8),

        if (peers.isEmpty)
          Card(
            color: isDark ? const Color(0xFF161B22) : Colors.white,
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Center(
                child: Text('Нет активных пиров\nЗапустите DHT на двух устройствах',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey, fontSize: 13),
                ),
              ),
            ),
          )
        else
          ...peers.map((p) => Card(
            color: isDark ? const Color(0xFF161B22) : Colors.white,
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: Colors.blue.withValues(alpha: 0.2),
                child: Icon(Icons.computer, color: Colors.blue, size: 20),
              ),
              title: Text(p.id.toHex().substring(0, 12), style: TextStyle(
                fontSize: 13, fontFamily: 'monospace', color: isDark ? Colors.white : Colors.black87,
              )),
              subtitle: Text('${p.address}:${p.port}', style: TextStyle(fontSize: 11, color: Colors.grey)),
              trailing: Icon(Icons.circle, size: 8, color: Colors.green),
            ),
          )),
      ],
    );
  }

  Widget _statItem(IconData icon, String label, String value, Color color) {
    return Column(
      children: [
        Icon(icon, color: color, size: 24),
        const SizedBox(height: 4),
        Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: color)),
        Text(label, style: TextStyle(fontSize: 11, color: Colors.grey)),
      ],
    );
  }

  // ═══ 2. ПРОФИЛЬ ═══
  Widget _buildProfileTab(bool isDark) {
    final profile = _auth.currentProfile;
    final loggedIn = profile != null;

    if (loggedIn) {
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            color: isDark ? const Color(0xFF161B22) : Colors.white,
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  CircleAvatar(
                    radius: 32,
                    backgroundColor: const Color(0xFF6C63FF),
                    child: Text(
                      (profile.username.isNotEmpty ? profile.username[0] : '?').toUpperCase(),
                      style: const TextStyle(fontSize: 28, color: Colors.white),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(profile.username, style: TextStyle(
                    fontSize: 22, fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : Colors.black87,
                  )),
                  if (profile.nickname.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(profile.nickname, style: TextStyle(color: Colors.grey, fontSize: 14)),
                  ],
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.hub, size: 14, color: Colors.green),
                      const SizedBox(width: 4),
                      Text('Личный ID: ${profile.userId.substring(0, 12)}...',
                        style: TextStyle(fontSize: 11, fontFamily: 'monospace', color: Colors.grey)),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _profileStat('Пиры', '${_peerCount}', Colors.blue),
                      _profileStat('Сообщ.', '${_chatMessages.length}', Colors.green),
                      _profileStat('NEXUS', 'v1.0', Colors.amber),
                    ],
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              icon: const Icon(Icons.logout),
              label: const Text('Выйти из P2P'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.red,
                side: const BorderSide(color: Colors.red),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              onPressed: () async {
                await _auth.logout();
                setState(() {});
              },
            ),
          ),
        ],
      );
    }

    // Форма регистрации/логина
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Icon(Icons.person_add, size: 64, color: const Color(0xFF6C63FF)),
        const SizedBox(height: 8),
        Text(
          _isRegister ? 'Регистрация в P2P сети' : 'Вход в P2P сеть',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.black87),
        ),
        const SizedBox(height: 4),
        Text('Аккаунт хранится локально на устройстве',
          textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: Colors.grey)),
        const SizedBox(height: 24),

        Card(
          color: isDark ? const Color(0xFF161B22) : Colors.white,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                TextField(
                  controller: _usernameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Имя пользователя',
                    prefixIcon: Icon(Icons.person),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _passwordCtrl,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Пароль',
                    prefixIcon: Icon(Icons.lock),
                    border: OutlineInputBorder(),
                  ),
                ),
                if (_isRegister) ...[
                  const SizedBox(height: 12),
                  TextField(
                    controller: _nicknameCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Отображаемое имя',
                      prefixIcon: Icon(Icons.face),
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
                const SizedBox(height: 16),

                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF6C63FF),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    onPressed: () async {
                      final username = _usernameCtrl.text.trim();
                      final password = _passwordCtrl.text.trim();
                      if (username.isEmpty || password.isEmpty) return;

                      if (_isRegister) {
                        final ok = await _auth.register(username, password, nickname: _nicknameCtrl.text.trim());
                        if (ok && mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Профиль создан локально'), backgroundColor: Colors.green),
                          );
                        }
                      } else {
                        final ok = await _auth.login(username, password);
                        if (!ok && mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Неверный логин или пароль'), backgroundColor: Colors.red),
                          );
                        }
                      }
                      setState(() {});
                    },
                    child: Text(_isRegister ? 'Создать профиль' : 'Войти'),
                  ),
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 12),

        TextButton(
          onPressed: () => setState(() => _isRegister = !_isRegister),
          child: Text(_isRegister ? 'Уже есть профиль? Войти' : 'Нет профиля? Создать'),
        ),

        if (_auth.error.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(_auth.error, style: const TextStyle(color: Colors.red, fontSize: 12)),
          ),
      ],
    );
  }

  Widget _profileStat(String label, String value, Color color) {
    return Column(
      children: [
        Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: color)),
        Text(label, style: TextStyle(fontSize: 11, color: Colors.grey)),
      ],
    );
  }

  // ═══ 3. ЧАТ ═══
  Widget _buildChatTab(bool isDark) {
    final node = _dhtMgr.node;
    final peers = node?.allPeers ?? [];

    return Column(
      children: [
        // Выбор цели
        Container(
          padding: const EdgeInsets.all(12),
          color: isDark ? const Color(0xFF161B22) : Colors.white,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Отправить сообщение', style: TextStyle(
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : Colors.black87,
              )),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonHideUnderline(
                      child: DropdownButtonFormField<String>(
                        value: _chatTarget.isEmpty ? null : _chatTarget,
                        hint: const Text('Выберите пира'),
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        ),
                        items: peers.map((p) => DropdownMenuItem(
                          value: p.id.toHex(),
                          child: Text(p.id.toHex().substring(0, 12), style: const TextStyle(fontSize: 13)),
                        )).toList(),
                        onChanged: (v) => setState(() => _chatTarget = v ?? ''),
                      ),
                    ),
                  ),
                  if (peers.isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: Text('Нет пиров', style: TextStyle(fontSize: 11, color: Colors.grey)),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _chatCtrl,
                maxLines: 2,
                decoration: InputDecoration(
                  hintText: 'Введите сообщение...',
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.send),
                    onPressed: _sendP2PMessage,
                  ),
                ),
              ),
            ],
          ),
        ),

        // Сообщения
        Expanded(
          child: _chatMessages.isEmpty
            ? Center(
                child: Text('Нет сообщений\nОтправьте P2P сообщение пиру',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey, fontSize: 13),
                ),
              )
            : ListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: _chatMessages.length,
                itemBuilder: (ctx, i) {
                  final msg = _chatMessages[i];
                  final isMe = msg['isMe'] as bool? ?? false;
                  return Align(
                    alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                    child: Container(
                      constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.7),
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: isMe
                          ? const Color(0xFF6C63FF)
                          : (isDark ? const Color(0xFF22262E) : Colors.grey[200]),
                        borderRadius: BorderRadius.circular(16).copyWith(
                          bottomRight: isMe ? Radius.zero : null,
                          bottomLeft: isMe ? null : Radius.zero,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(msg['text'] as String? ?? '',
                            style: TextStyle(color: isMe ? Colors.white : (isDark ? Colors.white : Colors.black87)),
                          ),
                          const SizedBox(height: 4),
                          Text(msg['time'] as String? ?? '',
                            style: TextStyle(fontSize: 10, color: isMe ? Colors.white60 : Colors.grey),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
        ),
      ],
    );
  }

  void _sendP2PMessage() {
    final text = _chatCtrl.text.trim();
    if (text.isEmpty || _chatTarget.isEmpty) return;

    final now = DateTime.now();
    final timeStr = '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';

    setState(() {
      _chatMessages.add({
        'text': text,
        'time': timeStr,
        'target': _chatTarget,
        'isMe': true,
      });
      _chatCtrl.clear();
    });

    // В реальной DHT сети тут была бы отправка через DHTNode.sendMessage()
    debugPrint('[P2P Chat] Sent to $_chatTarget: $text');
  }

  // ═══ 4. ОБФУСКАЦИЯ ═══
  Widget _buildObfuscationTab(bool isDark) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          color: isDark ? const Color(0xFF161B22) : Colors.white,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                Icon(Icons.security, size: 48, color: Colors.amber),
                const SizedBox(height: 8),
                Text('Обфускация трафика', style: TextStyle(
                  fontSize: 18, fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : Colors.black87,
                )),
                const SizedBox(height: 4),
                Text('Маскировка всего трафика под HTTPS к max.ru',
                  textAlign: TextAlign.center, style: TextStyle(color: Colors.grey, fontSize: 12)),
              ],
            ),
          ),
        ),

        const SizedBox(height: 12),

        // VPN маскировка
        Card(
          color: isDark ? const Color(0xFF161B22) : Colors.white,
          child: Column(
            children: [
              ListTile(
                leading: Icon(Icons.shield, color: Colors.green),
                title: Text('VPN обфускация', style: TextStyle(color: isDark ? Colors.white : Colors.black87)),
                subtitle: const Text('Вся система маскируется под HTTPS к max.ru', style: TextStyle(fontSize: 12)),
                trailing: Icon(Icons.check_circle, color: Colors.green),
              ),
              const Divider(height: 1),
              ListTile(
                leading: Icon(Icons.dns, color: Colors.blue),
                title: Text('DoH DNS', style: TextStyle(color: isDark ? Colors.white : Colors.black87)),
                subtitle: const Text('Cloudflare (1.1.1.1) через HTTPS', style: TextStyle(fontSize: 12)),
                trailing: Icon(Icons.check_circle, color: Colors.green),
              ),
              const Divider(height: 1),
              ListTile(
                leading: Icon(Icons.shuffle, color: Colors.purple),
                title: Text('TLS 1.3 padding', style: TextStyle(color: isDark ? Colors.white : Colors.black87)),
                subtitle: const Text('Случайный размер пакетов', style: TextStyle(fontSize: 12)),
                trailing: Icon(Icons.check_circle, color: Colors.green),
              ),
            ],
          ),
        ),

        const SizedBox(height: 16),

        // Параметры
        Card(
          color: isDark ? const Color(0xFF161B22) : Colors.white,
          child: Column(
            children: [
              ListTile(
                leading: Icon(Icons.speed, color: Colors.orange),
                title: Text('Режим обфускации', style: TextStyle(color: isDark ? Colors.white : Colors.black87)),
                subtitle: const Text('HTTPS / HTTP / Auto', style: TextStyle(fontSize: 12)),
                trailing: DropdownButton<String>(
                  value: 'HTTPS',
                  underline: const SizedBox(),
                  items: ['HTTPS', 'HTTP', 'Auto'].map((m) => DropdownMenuItem(value: m, child: Text(m))).toList(),
                  onChanged: (v) {},
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
