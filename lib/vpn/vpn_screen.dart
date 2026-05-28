import 'package:flutter/material.dart';
import 'dart:async';
import '../services/nexus_zapret.dart';
import '../services/mtproto_proxy.dart';

// ════════════════════════════════════════════
// Единая система: Zapret (DPI-обход) + MTProto
// ════════════════════════════════════════════

class VpnScreen extends StatefulWidget {
  const VpnScreen({super.key});

  @override
  State<VpnScreen> createState() => _VpnScreenState();
}

class _VpnScreenState extends State<VpnScreen> with SingleTickerProviderStateMixin {
  bool _isActive = false;

  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  final _zapret = NexusZapret.instance;
  final _proxy = NexusMtprotoProxy.instance;
  Timer? _statsTimer;

  @override
  void initState() {
    super.initState();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 0.85, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _statsTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _statsTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF0D1117) : const Color(0xFFF0F2F5);

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        title: const Text('VPN', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF6C63FF),
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          if (_isActive)
            Container(
              margin: const EdgeInsets.only(right: 16),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.green.withOpacity(0.2),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.check_circle, color: Colors.green, size: 14),
                  SizedBox(width: 6),
                  Text('Активно', style: TextStyle(color: Colors.green, fontSize: 12)),
                ],
              ),
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildMainCard(isDark),
            const SizedBox(height: 24),
            _buildZapretSection(isDark),
            const SizedBox(height: 24),
            const Divider(height: 1),
            const SizedBox(height: 24),
            _buildMtprotoSection(isDark),
            const SizedBox(height: 16),
            Center(
              child: Text(
                'Работает полностью автономно\nбез внешних серверов',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey[500], fontSize: 12),
              ),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  // ═══ Главная карточка ═══

  Widget _buildMainCard(bool isDark) {
    final cardColor = isDark ? const Color(0xFF161B22) : Colors.white;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: _isActive
              ? [Colors.green.withOpacity(0.15), cardColor]
              : [const Color(0xFF6C63FF).withOpacity(0.1), cardColor],
          begin: Alignment.topLeft, end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: _isActive ? Colors.green.withOpacity(0.3) : const Color(0xFF6C63FF).withOpacity(0.2),
        ),
      ),
      child: Column(
        children: [
          AnimatedBuilder(
            animation: _pulseAnimation,
            builder: (context, child) => Transform.scale(
              scale: _isActive ? _pulseAnimation.value : 1.0,
              child: Container(
                width: 80, height: 80,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _isActive ? Colors.green.withOpacity(0.15) : const Color(0xFF6C63FF).withOpacity(0.1),
                  border: Border.all(
                    color: _isActive ? Colors.green.withOpacity(0.4) : const Color(0xFF6C63FF).withOpacity(0.3),
                    width: 2,
                  ),
                ),
                child: Icon(Icons.shield, size: 40,
                    color: _isActive ? Colors.green : const Color(0xFF6C63FF)),
              ),
            ),
          ),
          const SizedBox(height: 16),
          const Text('VPN', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text(
            'Zapret (DPI-обход) + MTProto Proxy\nавтономно, без внешних серверов',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey[500], fontSize: 13),
          ),
          const SizedBox(height: 28),
          SizedBox(
            width: double.infinity, height: 54,
            child: ElevatedButton.icon(
              onPressed: _toggle,
              icon: Icon(_isActive ? Icons.stop : Icons.play_arrow),
              label: Text(
                _isActive ? 'Остановить всё' : 'Запустить всё',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: _isActive ? Colors.red[400] : const Color(0xFF6C63FF),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ═══ Zapret ═══

  Widget _buildZapretSection(bool isDark) {
    final cardColor = isDark ? const Color(0xFF161B22) : Colors.white;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text('ПРОФИЛИ ОБХОДА DPI',
              style: TextStyle(color: Color(0xFF6C63FF), fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
            const Spacer(),
            Text('${_zapret.enabledProfiles.length} / ${_zapret.profiles.length}',
              style: TextStyle(color: Colors.grey[500], fontSize: 12)),
          ],
        ),
        const SizedBox(height: 12),
        ..._zapret.profiles.map((profile) => _buildProfileCard(profile, isDark, cardColor)),

        const SizedBox(height: 16),

        // DNS
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: cardColor, borderRadius: BorderRadius.circular(14),
            border: Border.all(color: isDark ? const Color(0xFF30363D) : Colors.grey[200]!),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: _zapret.activeDns != null ? Colors.green.withOpacity(0.15) : Colors.orange.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.dns,
                  color: _zapret.activeDns != null ? Colors.green : Colors.orange, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('DNS-over-HTTPS', style: TextStyle(fontWeight: FontWeight.w600)),
                    Text(_zapret.activeDns ?? 'DNS недоступен (системный)',
                      style: TextStyle(color: Colors.grey[500], fontSize: 12)),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: _zapret.activeDns != null ? Colors.green.withOpacity(0.15) : Colors.orange.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  _zapret.activeDns != null ? 'ОК' : 'WARN',
                  style: TextStyle(
                    color: _zapret.activeDns != null ? Colors.green : Colors.orange,
                    fontSize: 11, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 16),

        // Stats
        ..._buildStats(isDark),
      ],
    );
  }

  Widget _buildProfileCard(ZapretProfile profile, bool isDark, Color cardColor) {
    final enabled = _zapret.isProfileEnabled(profile.name);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: cardColor, borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: enabled ? Colors.green.withOpacity(0.3) : (isDark ? const Color(0xFF30363D) : Colors.grey[200]!),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: enabled ? Colors.green.withOpacity(0.15) : const Color(0xFF6C63FF).withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(enabled ? Icons.check_circle : Icons.shield_outlined,
                  color: enabled ? Colors.green : const Color(0xFF6C63FF), size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(profile.name,
                    style: TextStyle(fontWeight: FontWeight.w600,
                        color: enabled ? Colors.green : (isDark ? Colors.white : Colors.black87))),
                  const SizedBox(height: 2),
                  Text(profile.description,
                    style: TextStyle(color: Colors.grey[500], fontSize: 12)),
                ],
              ),
            ),
            Switch(
              value: enabled,
              activeColor: Colors.green,
              onChanged: (v) {
                setState(() {
                  if (v) _zapret.enableProfile(profile.name);
                  else _zapret.disableProfile(profile.name);
                });
              },
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildStats(bool isDark) {
    final stats = _zapret.getStats();
    final cardColor = isDark ? const Color(0xFF161B22) : Colors.white;
    return [
      Text('СТАТИСТИКА',
        style: TextStyle(color: const Color(0xFF6C63FF), fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
      const SizedBox(height: 8),
      _statRow('Техника', '${stats['technique']}', Icons.speed, isDark, cardColor),
      const SizedBox(height: 6),
      _statRow('Обработано', '${stats['packetsProcessed']}', Icons.swap_horiz, isDark, cardColor),
      const SizedBox(height: 6),
      _statRow('Обойдено', '${stats['packetsBypassed']}', Icons.check_circle_outline, isDark, cardColor),
    ];
  }

  Widget _statRow(String label, String value, IconData icon, bool isDark, Color cardColor) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cardColor, borderRadius: BorderRadius.circular(12),
        border: Border.all(color: isDark ? const Color(0xFF30363D) : Colors.grey[200]!),
      ),
      child: Row(
        children: [
          Icon(icon, color: const Color(0xFF6C63FF), size: 18),
          const SizedBox(width: 10),
          Text(label, style: TextStyle(color: isDark ? Colors.grey[400] : Colors.grey[700], fontSize: 14)),
          const Spacer(),
          Text(value, style: TextStyle(
            color: isDark ? Colors.grey[300] : Colors.black87,
            fontSize: 14, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  // ═══ MTProto ═══

  Widget _buildMtprotoSection(bool isDark) {
    final cardColor = isDark ? const Color(0xFF161B22) : Colors.white;
    final running = _proxy.status == MtprotoProxyStatus.running;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('MTProto PROXY (локальный)',
          style: TextStyle(color: Color(0xFF6C63FF), fontSize: 14, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
        const SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(
            color: cardColor, borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: running ? Colors.blue.withOpacity(0.3) : (isDark ? const Color(0xFF30363D) : Colors.grey[200]!)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: running ? Colors.blue.withOpacity(0.15) : Colors.grey.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(Icons.telegram, color: running ? Colors.blue : Colors.grey, size: 24),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('MTProto Proxy', style: TextStyle(fontWeight: FontWeight.w600)),
                          Text(running ? '🟢 Работает' : '🔴 Остановлен',
                            style: TextStyle(color: running ? Colors.green : Colors.grey[500], fontSize: 12)),
                        ],
                      ),
                    ),
                    Switch(
                      value: running,
                      activeColor: Colors.blue,
                      onChanged: (v) async {
                        if (v) await _proxy.start(); else await _proxy.stop();
                        if (mounted) setState(() {});
                      },
                    ),
                  ],
                ),
              ),
              if (running) ...[
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Text('Порт: ', style: TextStyle(color: Colors.grey[500], fontSize: 12)),
                        Text('${_proxy.port}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                      ]),
                      const SizedBox(height: 6),
                      Row(children: [
                        Text('Подключений: ', style: TextStyle(color: Colors.grey[500], fontSize: 12)),
                        Text('${_proxy.connectionsOpened}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                      ]),
                      const SizedBox(height: 6),
                      Row(children: [
                        Text('Secret: ', style: TextStyle(color: Colors.grey[500], fontSize: 12)),
                        Text(_proxy.secret.length > 16 ? '${_proxy.secret.substring(0, 16)}...' : _proxy.secret,
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                      ]),
                      const SizedBox(height: 12),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0xFF0D1117) : Colors.grey[100],
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: SelectableText(_proxy.proxyLink,
                          style: TextStyle(
                            fontSize: 11, fontFamily: 'monospace',
                            color: isDark ? Colors.grey[300] : Colors.black87,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.blue.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(children: [
                              Icon(Icons.info_outline, size: 16, color: Colors.blue[400]),
                              const SizedBox(width: 6),
                              Text('Как подключить Telegram:',
                                style: TextStyle(fontWeight: FontWeight.w600, color: Colors.blue[400], fontSize: 13)),
                            ]),
                            const SizedBox(height: 8),
                            _step('1', 'Открой Telegram → Настройки'),
                            _step('2', 'Перейди в "Данные и память"'),
                            _step('3', 'Нажми "Использовать прокси"'),
                            _step('4', 'Вставь ссылку выше или заполни вручную'),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _step(String num, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Container(
            width: 20, height: 20,
            decoration: BoxDecoration(
              color: Colors.blue.withOpacity(0.2),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Center(child: Text(num,
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.blue[400]))),
          ),
          const SizedBox(width: 8),
          Text(text, style: TextStyle(fontSize: 12, color: Colors.grey[300])),
        ],
      ),
    );
  }

  Future<void> _toggle() async {
    final shouldStart = !_isActive;
    if (shouldStart) {
      _zapret.start();
      await _proxy.start();
    } else {
      _zapret.stop();
      await _proxy.stop();
    }
    if (mounted) setState(() => _isActive = shouldStart);
  }
}
