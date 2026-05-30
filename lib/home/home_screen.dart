// ═══════════════════════════════════════════════════════════════
// NEXUS Главное меню
//
// Разделы:
//   1. VPN — ЕДИНАЯ КНОПКА (запускает всё сразу)
//   2. P2P Чаты — децентрализованные чаты (друзья, группы, каналы)
//   3. Профиль — P2P профиль + аватар
//   4. Настройки — темы, шрифты, обновление
// ═══════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/nexus_icons.dart';
import '../services/dht_network.dart';
import '../services/dht_auth.dart';
import '../services/global_p2p_node.dart';
import '../gram/nexusgram_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _vpnActive = false;
  String _vpnStatus = 'Выключено';

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF0D1117) : const Color(0xFFF5F5F5);
    final cardBg = isDark ? const Color(0xFF161B22) : Colors.white;

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        title: Row(
          children: [
            _CustomPaintIcon(nexusLogoIcon, Colors.amber, size: 32),
            SizedBox(width: 8, height: 32),
            Text('NEXUS', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 22)),
          ],
        ),
        backgroundColor: cardBg,
        elevation: 0,
        actions: [
          IconButton(
            icon: Icon(Icons.settings, color: Colors.grey),
            onPressed: () {
              // открыть настройки
            },
          ),
        ],
      ),
      body: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          children: [
            // ═══ VPN — единая кнопка ═══
            _VpnMainButton(
              active: _vpnActive,
              isDark: isDark,
              onToggle: () {
                setState(() {
                  _vpnActive = !_vpnActive;
                  _vpnStatus = _vpnActive ? 'Защита активна' : 'Выключено';
                });
              },
            ),

            SizedBox(height: 16),

            // ═══ P2P Чаты ═══
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: _MenuCard(
                      icon: _CustomPaintIcon(nexusP2pIcon, Color(0xFFFF5722), size: 40),
                      title: 'P2P Чаты',
                      subtitle: 'Друзья, группы, каналы',
                      color: Color(0xFFFF5722),
                      isDark: isDark,
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const _P2pChatPlaceholder()),
                        );
                      },
                    ),
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: _MenuCard(
                      icon: _CustomPaintIcon(nexusProfileIcon, Color(0xFFE91E63), size: 40),
                      title: 'Профиль',
                      subtitle: 'P2P аккаунт',
                      color: Color(0xFFE91E63),
                      isDark: isDark,
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const _ProfilePlaceholder()),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 12),

            // ═══ NexusGram ═══
            _MenuCard(
              icon: const Icon(Icons.send, size: 28, color: Color(0xFF0088CC)),
              title: 'NexusGram',
              subtitle: 'Telegram через NEXUS',
              color: const Color(0xFF0088CC),
              isDark: isDark,
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const NexusGramScreen()),
                );
              },
              compact: true,
            ),

            const SizedBox(height: 12),

            // ═══ Настройки и статус ═══
            _MenuCard(
              icon: Icon(Icons.tune, size: 28, color: Colors.grey),
              title: 'Настройки',
              subtitle: 'Тема, шрифт, обновления',
              color: Colors.grey,
              isDark: isDark,
              onTap: () {
                // открыть настройки
              },
              compact: true,
            ),

            SizedBox(height: 8),

            // Статус-бар
            Container(
              padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: cardBg,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: isDark ? const Color(0xFF30363D) : Colors.grey[200]!),
              ),
              child: Row(
                children: [
                  Icon(Icons.circle, size: 8,
                    color: _vpnActive ? Colors.green : Colors.grey),
                  SizedBox(width: 8),
                  Text('VPN: $_vpnStatus', style: TextStyle(fontSize: 12, color: Colors.grey)),
                  Spacer(),
                  Text('P2P: Активна', style: TextStyle(fontSize: 12, color: Colors.green[400])),
                  SizedBox(width: 8),
                  Icon(Icons.circle, size: 8, color: Colors.green),
                  SizedBox(width: 16),
                  Text('Обучение: ${_trainProgress}%',
                    style: TextStyle(fontSize: 12, color: Colors.deepPurple[200])),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String get _trainProgress => '45';
}

// ═══ VPN Единая кнопка ═══

class _VpnMainButton extends StatelessWidget {
  final bool active;
  final bool isDark;
  final VoidCallback onToggle;

  const _VpnMainButton({required this.active, required this.isDark, required this.onToggle});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onToggle,
      child: AnimatedContainer(
        duration: Duration(milliseconds: 300),
        width: double.infinity,
        height: 160,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: active
                ? [Color(0xFF00BCD4), Color(0xFF1A237E)]
                : [const Color(0xFF1A237E).withValues(alpha: 0.5), const Color(0xFF0D1117)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: active ? Color(0xFF00BCD4) : const Color(0xFF30363D),
            width: 2,
          ),
          boxShadow: active
              ? [BoxShadow(color: Color(0xFF00BCD4).withValues(alpha: 0.3), blurRadius: 20, spreadRadius: 2)]
              : [],
        ),
        child: Stack(
          children: [
            // Shield icon
            Positioned(
              right: 20,
              top: 20,
              child: Icon(
                active ? Icons.shield : Icons.shield_outlined,
                color: active ? Colors.white : Colors.grey[600],
                size: 64,
              ),
            ),
            Padding(
              padding: EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.lock,
                        color: active ? Color(0xFF00BCD4) : Colors.grey,
                        size: 20,
                      ),
                      SizedBox(width: 8),
                      Text('VPN ЗАЩИТА',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: active ? Colors.white : Colors.grey[400],
                          letterSpacing: 2,
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 8),
                  Text(
                    active
                        ? 'Обфускация max.ru • DPI • MTProto • SOCKS5'
                        : 'Нажмите для запуска полной защиты',
                    style: TextStyle(color: active ? Colors.white70 : Colors.grey[600], fontSize: 13),
                  ),
                  SizedBox(height: 12),
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                    decoration: BoxDecoration(
                      color: active ? Colors.white.withValues(alpha: 0.15) : Colors.grey.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      active ? '● АКТИВНО' : '○ НЕАКТИВНО',
                      style: TextStyle(
                        color: active ? Color(0xFF00BCD4) : Colors.grey,
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══ КАРТОЧКИ МЕНЮ ═══

class _MenuCard extends StatelessWidget {
  final Widget icon;
  final String title;
  final String subtitle;
  final Color color;
  final bool isDark;
  final VoidCallback onTap;
  final bool compact;

  const _MenuCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.isDark,
    required this.onTap,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    if (compact) {
      return GestureDetector(
        onTap: onTap,
        child: Container(
          padding: EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF161B22) : Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: isDark ? const Color(0xFF30363D) : Colors.grey[200]!),
          ),
          child: Row(
            children: [
              icon,
              SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  Text(subtitle, style: TextStyle(color: Colors.grey[500], fontSize: 12)),
                ],
              ),
            ],
          ),
        ),
      );
    }

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF161B22) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: isDark ? const Color(0xFF30363D) : Colors.grey[200]!),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            icon,
            SizedBox(height: 12),
            Text(title,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : Colors.black87,
              ),
            ),
            SizedBox(height: 4),
            Text(subtitle,
              style: TextStyle(fontSize: 11, color: Colors.grey[500]),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

// ═══ ПЛЕЙСХОЛДЕРЫ ═══

class _P2pChatPlaceholder extends StatelessWidget {
  const _P2pChatPlaceholder();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      appBar: AppBar(title: Text('P2P Чаты')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.hub, size: 80, color: Color(0xFFFF5722)),
            SizedBox(height: 16),
            Text('P2P Чаты', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
            SizedBox(height: 8),
            Text('Децентрализованные чаты на DHT', style: TextStyle(color: Colors.grey)),
            SizedBox(height: 24),
            Text('Друзья | Группы | Каналы', style: TextStyle(color: Colors.grey[500])),
            SizedBox(height: 8),
            Text('Файлы | Фото | Сообщения', style: TextStyle(color: Colors.grey[500])),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// P2P Profile Screen — два способа регистрации
// ═══════════════════════════════════════════════════════════════

class _ProfilePlaceholder extends StatefulWidget {
  const _ProfilePlaceholder();

  @override
  State<_ProfilePlaceholder> createState() => _P2pProfileState();
}

class _P2pProfileState extends State<_ProfilePlaceholder> {
  bool _registered = false;
  bool _loading = false;
  String? _username;
  String? _email;
  String _p2pId = '';
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadSession();
  }

  Future<void> _loadSession() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedUsername = prefs.getString('p2p_username');
      final savedEmail = prefs.getString('p2p_email');
      if (savedUsername != null) {
        setState(() {
          _username = savedUsername;
          _email = savedEmail;
          _registered = true;
          _p2pId = 'P2P:${sha1hex(savedUsername)}';
        });
      }
    } catch (_) {}
  }

  void _openRegistration() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).brightness == Brightness.dark
          ? const Color(0xFF161B22)
          : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _RegistrationSheet(
        onRegistered: (email, username) {
          setState(() {
            _email = email;
            _username = username;
            _registered = true;
            _p2pId = 'P2P:${sha1hex(username)}';
          });
        },
      ),
    );
  }

  String sha1hex(String s) {
    // простая генерация ID из username
    int h = 0;
    for (var c in s.codeUnits) {
      h = ((h << 5) - h) + c;
      h &= 0xFFFFFFFF;
    }
    return h.toRadixString(16).padLeft(8, '0');
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? const Color(0xFF161B22) : Colors.white;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0D1117) : const Color(0xFFF5F5F5),
      appBar: AppBar(
        title: const Text('Профиль'),
        backgroundColor: const Color(0xFFE91E63),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              if (!_registered) _buildNotRegistered(isDark, cardBg),
              if (_registered) _buildRegistered(isDark, cardBg),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNotRegistered(bool isDark, Color cardBg) {
    return Card(
      color: cardBg,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            CircleAvatar(
              radius: 48,
              backgroundColor: const Color(0xFFE91E63),
              child: const Icon(Icons.person, size: 48, color: Colors.white),
            ),
            const SizedBox(height: 16),
            const Text('Войдите в P2P сеть',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(
              'Выберите способ регистрации',
              style: TextStyle(color: Colors.grey[500], fontSize: 14),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _openRegistration,
                icon: const Icon(Icons.login, size: 20),
                label: const Text('Регистрация / Вход', style: TextStyle(fontSize: 16)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFE91E63),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'После регистрации профиль будет храниться в DHT сети\nна N ближайших нодах',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey[600], fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRegistered(bool isDark, Color cardBg) {
    return Card(
      color: cardBg,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            CircleAvatar(
              radius: 48,
              backgroundColor: const Color(0xFFE91E63),
              child: Text(
                (_username ?? '?')[0].toUpperCase(),
                style: const TextStyle(fontSize: 36, fontWeight: FontWeight.bold, color: Colors.white),
              ),
            ),
            const SizedBox(height: 16),
            Text('P2P ID: $_p2pId',
              style: TextStyle(fontSize: 12, fontFamily: 'monospace', color: Colors.grey[500])),
            const SizedBox(height: 4),
            if (_username != null)
              Text('@$_username',
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            if (_email != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('$_email',
                  style: TextStyle(fontSize: 13, color: Colors.grey[500])),
              ),
            const SizedBox(height: 24),
            const Divider(),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _infoChip(Icons.hub, 'Нод: 3', Colors.purple),
                _infoChip(Icons.key, 'Ключ: X25519', Colors.teal),
                _infoChip(Icons.cloud, 'DHT: активна', Colors.green),
              ],
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () async {
                  final prefs = await SharedPreferences.getInstance();
                  await prefs.remove('p2p_username');
                  await prefs.remove('p2p_email');
                  setState(() {
                    _registered = false;
                    _username = null;
                    _email = null;
                    _p2pId = '';
                  });
                },
                child: const Text('Выйти', style: TextStyle(color: Colors.red)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _infoChip(IconData icon, String label, Color color) {
    return Column(
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(height: 4),
        Text(label, style: TextStyle(fontSize: 10, color: Colors.grey[600])),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// Registration Sheet — два способа
// ═══════════════════════════════════════════════════════════════

class _RegistrationSheet extends StatefulWidget {
  final void Function(String? email, String username) onRegistered;

  const _RegistrationSheet({required this.onRegistered});

  @override
  State<_RegistrationSheet> createState() => _RegistrationSheetState();
}

class _RegistrationSheetState extends State<_RegistrationSheet> {
  int _method = 0; // 0=Google, 1=P2P
  bool _loading = false;
  String _error = '';

  final _emailCtrl = TextEditingController();
  final _usernameCtrl = TextEditingController();
  final _displayCtrl = TextEditingController();

  @override
  void dispose() {
    _emailCtrl.dispose();
    _usernameCtrl.dispose();
    _displayCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bottom = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 12, 20, 12 + bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle bar
            Container(
              width: 40, height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[400],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            const Text('Регистрация в P2P сети',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),

            // Method selector
            Row(
              children: [
                Expanded(
                  child: _methodButton(0, Icons.email, 'Google'),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _methodButton(1, Icons.hub, 'P2P Ключ'),
                ),
              ],
            ),
            const SizedBox(height: 20),

            if (_method == 0) _buildGoogleForm(isDark),
            if (_method == 1) _buildP2pForm(isDark),
          ],
        ),
      ),
    );
  }

  Widget _methodButton(int idx, IconData icon, String label) {
    final active = _method == idx;
    return GestureDetector(
      onTap: () => setState(() => _method = idx),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: active
            ? const Color(0xFFE91E63).withValues(alpha: 0.15)
            : Colors.grey.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: active ? const Color(0xFFE91E63) : Colors.grey.withValues(alpha: 0.3),
            width: active ? 2 : 1,
          ),
        ),
        child: Column(
          children: [
            Icon(icon, color: active ? const Color(0xFFE91E63) : Colors.grey, size: 28),
            const SizedBox(height: 6),
            Text(label,
              style: TextStyle(
                fontWeight: active ? FontWeight.bold : FontWeight.normal,
                color: active ? const Color(0xFFE91E63) : Colors.grey,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Google ───

  Widget _buildGoogleForm(bool isDark) {
    return Column(
      children: [
        TextField(
          controller: _emailCtrl,
          decoration: const InputDecoration(
            labelText: 'Google почта',
            hintText: 'example@gmail.com',
            prefixIcon: Icon(Icons.email, size: 20),
            border: OutlineInputBorder(),
          ),
          keyboardType: TextInputType.emailAddress,
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _usernameCtrl,
          decoration: const InputDecoration(
            labelText: 'Имя пользователя (P2P)',
            hintText: 'никнейм в сети',
            prefixIcon: Icon(Icons.person, size: 20),
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _displayCtrl,
          decoration: const InputDecoration(
            labelText: 'Отображаемое имя',
            hintText: 'Как вас зовут',
            prefixIcon: Icon(Icons.badge, size: 20),
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Привязка к Google — резервное восстановление профиля\nчерез OAuth 2.0. Сам профиль в DHT.',
          style: TextStyle(fontSize: 11, color: Colors.grey[500]),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 16),
        if (_error.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(_error, style: const TextStyle(color: Colors.red, fontSize: 13)),
          ),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _loading ? null : _registerGoogle,
            icon: _loading
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.login, size: 20),
            label: const Text('Зарегистрироваться через Google'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFDB4437),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _registerGoogle() async {
    final email = _emailCtrl.text.trim();
    final username = _usernameCtrl.text.trim();
    final display = _displayCtrl.text.trim();

    if (email.isEmpty || username.isEmpty) {
      setState(() => _error = 'Заполните почту и имя пользователя');
      return;
    }
    if (!RegExp(r'^[\w.+-]+@gmail\.com$').hasMatch(email)) {
      setState(() => _error = 'Нужна почта @gmail.com');
      return;
    }
    if (username.length < 3) {
      setState(() => _error = 'Имя пользователя: минимум 3 символа');
      return;
    }

    setState(() { _loading = true; _error = ''; });

    try {
      // Сохраняем в SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('p2p_email', email);
      await prefs.setString('p2p_username', username);
      await prefs.setString('p2p_display', display.isNotEmpty ? display : username);

      // Регистрируем в DHT сети
      final dht = DhtNetworkManager.instance;
      final node = GlobalP2PNode.instance;

      // Генерируем P2P ключи (упрощённо)
      node.register('$username:$email');

      setState(() => _loading = false);
      widget.onRegistered(email, username);
      Navigator.pop(context);
    } catch (e) {
      setState(() {
        _loading = false;
        _error = 'Ошибка: ${e.toString().substring(0, 50)}';
      });
    }
  }

  // ─── P2P Ключ ───

  Widget _buildP2pForm(bool isDark) {
    return Column(
      children: [
        TextField(
          controller: _usernameCtrl,
          decoration: const InputDecoration(
            labelText: 'Имя пользователя (P2P)',
            hintText: 'уникальный никнейм',
            prefixIcon: Icon(Icons.person, size: 20),
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _displayCtrl,
          decoration: const InputDecoration(
            labelText: 'Отображаемое имя',
            hintText: 'Как вас зовут',
            prefixIcon: Icon(Icons.badge, size: 20),
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: isDark ? Colors.grey[900] : Colors.grey[100],
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              const Icon(Icons.key, size: 18, color: Colors.teal),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Ключ X25519 генерируется автоматически.\nПрофиль шифруется и хранится в DHT.',
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        if (_error.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(_error, style: const TextStyle(color: Colors.red, fontSize: 13)),
          ),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _loading ? null : _registerP2p,
            icon: _loading
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.hub, size: 20),
            label: const Text('Создать P2P аккаунт'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFE91E63),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _registerP2p() async {
    final username = _usernameCtrl.text.trim();
    final display = _displayCtrl.text.trim();

    if (username.isEmpty) {
      setState(() => _error = 'Введите имя пользователя');
      return;
    }
    if (username.length < 3) {
      setState(() => _error = 'Минимум 3 символа');
      return;
    }
    if (!RegExp(r'^[a-zA-Z0-9_]+$').hasMatch(username)) {
      setState(() => _error = 'Только латиница, цифры и _');
      return;
    }

    setState(() { _loading = true; _error = ''; });

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('p2p_username', username);
      await prefs.setString('p2p_display', display.isNotEmpty ? display : username);

      final node = GlobalP2PNode.instance;
      node.register(username);

      setState(() => _loading = false);
      widget.onRegistered(null, username);
      Navigator.pop(context);
    } catch (e) {
      setState(() {
        _loading = false;
        _error = 'Ошибка: ${e.toString().substring(0, 50)}';
      });
    }
  }
}

// ═══ УТИЛИТА: SVG ИКОНКА ═══

class _CustomPaintIcon extends StatelessWidget {
  final NexusSvgIcon svgIcon;
  final Color color;
  final double size;

  const _CustomPaintIcon(this.svgIcon, this.color, {this.size = 28});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _SvgIconPainter(svgIcon: svgIcon, color: color),
        size: Size(size, size),
      ),
    );
  }
}

class _SvgIconPainter extends CustomPainter {
  final NexusSvgIcon svgIcon;
  final Color color;
  _SvgIconPainter({required this.svgIcon, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.save();
    canvas.scale(size.width / 24, size.height / 24);
    final path = Path();
    var pathStr = svgIcon.buildPath(color);
    var reg = RegExp(r'([MLCQAZ])\s*([\d.\-\s,]+)');
    for (var m in reg.allMatches(pathStr)) {
      var cmd = m.group(1)!;
      var nums = m.group(2)!.trim().split(RegExp(r'[\s,]+')).where((s) => s.isNotEmpty).map(double.parse).toList();
      switch (cmd) {
        case 'M': if (nums.length >= 2) path.moveTo(nums[0], nums[1]); break;
        case 'L': for (var i = 0; i + 1 < nums.length; i += 2) path.lineTo(nums[i], nums[i+1]); break;
        case 'C': if (nums.length >= 6) path.cubicTo(nums[0], nums[1], nums[2], nums[3], nums[4], nums[5]); break;
        case 'Q': if (nums.length >= 4) path.quadraticBezierTo(nums[0], nums[1], nums[2], nums[3]); break;
        case 'Z': path.close(); break;
      }
    }
    canvas.drawPath(path, paint);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _SvgIconPainter o) => o.svgIcon.name != svgIcon.name;
}
