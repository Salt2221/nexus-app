import 'package:flutter/material.dart';
import 'dart:async';
import '../services/nexus_zapret.dart';

class VpnScreen extends StatefulWidget {
  const VpnScreen({super.key});

  @override
  State<VpnScreen> createState() => _VpnScreenState();
}

class _VpnScreenState extends State<VpnScreen> {
  final _zapret = NexusZapret.instance;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _toggleVpn() async {
    if (_zapret.isRunning) {
      await _zapret.stopVpnService();
    } else {
      await _zapret.startVpnService();
    }
    if (mounted) setState(() {});
  }

  Future<void> _toggleMtproto(bool val) async {
    if (val) {
      await _zapret.startMtproto();
    } else {
      await _zapret.stopMtproto();
    }
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF0D1117) : const Color(0xFFF0F2F5);
    final cardColor = isDark ? const Color(0xFF161B22) : Colors.white;

    final vpnRunning = _zapret.isRunning;
    final uptime = _zapret.uptimeSeconds;
    final mtproxy = _zapret.mtprotoProxyEnabled;

    final hours = (uptime ~/ 3600).toString().padLeft(2, '0');
    final minutes = ((uptime % 3600) ~/ 60).toString().padLeft(2, '0');
    final seconds = (uptime % 60).toString().padLeft(2, '0');

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        title: const Text('VPN', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF6C63FF),
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Основной статус
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: cardColor,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: isDark ? const Color(0xFF30363D) : Colors.grey[200]!),
            ),
            child: Column(
              children: [
                Icon(
                  vpnRunning ? Icons.shield : Icons.shield_outlined,
                  size: 72,
                  color: vpnRunning ? const Color(0xFF6C63FF) : Colors.grey[400],
                ),
                const SizedBox(height: 12),
                Text(
                  vpnRunning ? 'Защищено' : 'Не защищено',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: vpnRunning ? const Color(0xFF6C63FF) : Colors.grey[500],
                  ),
                ),
                if (vpnRunning) ...[
                  const SizedBox(height: 8),
                  Text('$hours:$minutes:$seconds',
                    style: TextStyle(fontSize: 14, color: Colors.grey[400], fontFamily: 'monospace'),
                  ),
                ],
                const SizedBox(height: 20),
                GestureDetector(
                  onTap: _toggleVpn,
                  child: Container(
                    width: 72, height: 72,
                    decoration: BoxDecoration(
                      color: vpnRunning ? const Color(0xFF6C63FF) : Colors.grey[600],
                      borderRadius: BorderRadius.circular(36),
                    ),
                    child: Icon(
                      vpnRunning ? Icons.power_settings_new : Icons.play_arrow,
                      color: Colors.white, size: 36,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // MTProto Proxy (встроенный)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: cardColor,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: isDark ? const Color(0xFF30363D) : Colors.grey[200]!),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Icon(Icons.flash_on, color: mtproxy ? const Color(0xFF6C63FF) : Colors.grey[500]),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Встроенный MTProto Proxy',
                            style: TextStyle(fontWeight: FontWeight.w600, color: isDark ? Colors.white : Colors.black87)),
                          Text('Принимает MTProto и ретранслирует Telegram',
                            style: TextStyle(fontSize: 12, color: Colors.grey[500])),
                        ],
                      ),
                    ),
                    Switch(
                      value: mtproxy,
                      onChanged: vpnRunning ? _toggleMtproto : null,
                      activeColor: const Color(0xFF6C63FF),
                    ),
                  ],
                ),
                if (mtproxy) ...[
                  const Divider(),
                  Row(
                    children: [
                      Text('Прокси:', style: TextStyle(fontSize: 13, color: Colors.grey[500])),
                      const SizedBox(width: 8),
                      Text('127.0.0.1:1443', style: TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w600,
                        fontFamily: 'monospace',
                        color: isDark ? Colors.white : Colors.black87)),
                    ],
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Профили DPI
          Text('Профили обхода DPI',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold,
              color: isDark ? Colors.white : Colors.black87)),
          const SizedBox(height: 8),
          ..._zapret.profiles.map((profile) => Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: cardColor,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: isDark ? const Color(0xFF30363D) : Colors.grey[200]!),
            ),
            child: Row(
              children: [
                Icon(
                  profile.enabled ? Icons.check_circle : Icons.circle_outlined,
                  color: profile.enabled ? const Color(0xFF6C63FF) : Colors.grey[500],
                  size: 20,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(profile.name,
                        style: TextStyle(fontWeight: FontWeight.w500,
                          color: isDark ? Colors.white : Colors.black87)),
                      Text(profile.description,
                        style: TextStyle(fontSize: 12, color: Colors.grey[500])),
                    ],
                  ),
                ),
                Switch(
                  value: profile.enabled,
                  onChanged: vpnRunning ? (val) {
                    setState(() => profile.enabled = val);
                  } : null,
                  activeColor: const Color(0xFF6C63FF),
                ),
              ],
            ),
          )),

          // Инфо
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1A1E2E) : const Color(0xFFF0EEFF),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline, color: const Color(0xFF6C63FF), size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'VpnService перехватывает весь TCP-трафик и ретранслирует его. '
                    'Встроенный MTProto proxy на 127.0.0.1:1443 принимает MTProto-соединения '
                    'и напрямую подключается к Telegram DC, минуя DPI.',
                    style: TextStyle(fontSize: 12, color: Colors.grey[500], height: 1.4),
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
