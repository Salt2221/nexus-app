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
import '../services/nexus_icons.dart';
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

class _ProfilePlaceholder extends StatelessWidget {
  const _ProfilePlaceholder();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      appBar: AppBar(title: Text('Профиль')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircleAvatar(
              radius: 48,
              backgroundColor: Color(0xFFE91E63),
              child: Icon(Icons.person, size: 48, color: Colors.white),
            ),
            SizedBox(height: 16),
            Text('P2P Аккаунт', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
            SizedBox(height: 8),
            Text('Войдите в P2P сеть', style: TextStyle(color: Colors.grey)),
            SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () {},
              icon: Icon(Icons.login),
              label: Text('Войти / Зарегистрироваться'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Color(0xFFE91E63),
                padding: EdgeInsets.symmetric(horizontal: 32, vertical: 16),
              ),
            ),
          ],
        ),
      ),
    );
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
