import 'package:flutter/material.dart';
import 'dart:async';
import 'package:flutter/services.dart';
import '../services/nexus_zapret.dart';

const _vpnChannel = MethodChannel('com.nexus.v2/vpn');

class VpnScreen extends StatefulWidget {
  const VpnScreen({super.key});

  @override
  State<VpnScreen> createState() => _VpnScreenState();
}

class _VpnScreenState extends State<VpnScreen> {
  final _zapret = NexusZapret.instance;
  Timer? _timer;
  String? _mtproxySecret;
  bool _mtproxyConnected = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
    _loadMtproxyStatus();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _loadMtproxyStatus() async {
    try {
      final status = await _vpnChannel.invokeMethod<Map>('getMtproxyStatus');
      if (status != null && mounted) {
        setState(() {
          _mtproxySecret = status['secret'] as String?;
        });
      }
    } catch (_) {}
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
      final secret = await _zapret.startMtproto();
      if (mounted) {
        setState(() {
          _mtproxyConnected = secret != null;
          if (secret is String && secret.isNotEmpty) _mtproxySecret = secret;
        });
      }
    } else {
      await _zapret.stopMtproto();
      if (mounted) setState(() => _mtproxyConnected = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF0D1117) : const Color(0xFFF0F2F5);
    final cardColor = isDark ? const Color(0xFF161B22) : Colors.white;

    final vpnRunning = _zapret.isRunning;
    final uptime = _zapret.uptimeSeconds;
    final mtproxy = _zapret.mtprotoProxyEnabled;

    final h = (uptime ~/ 3600).toString().padLeft(2, '0');
    final m = ((uptime % 3600) ~/ 60).toString().padLeft(2, '0');
    final s = (uptime % 60).toString().padLeft(2, '0');

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
          // VPN Status
          Container(
            padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
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
                    fontSize: 22, fontWeight: FontWeight.bold,
                    color: vpnRunning ? const Color(0xFF6C63FF) : Colors.grey[500],
                  ),
                ),
                if (vpnRunning) ...[
                  const SizedBox(height: 4),
                  Text('$h:$m:$s', style: TextStyle(fontSize: 14, color: Colors.grey[400], fontFamily: 'monospace')),
                ],
                const SizedBox(height: 20),
                GestureDetector(
                  onTap: _toggleVpn,
                  child: Container(
                    width: 68, height: 68,
                    decoration: BoxDecoration(
                      color: vpnRunning ? const Color(0xFF6C63FF) : Colors.grey[600],
                      borderRadius: BorderRadius.circular(34),
                      boxShadow: vpnRunning ? [
                        BoxShadow(color: const Color(0xFF6C63FF).withOpacity(0.3), blurRadius: 15, spreadRadius: 2)
                      ] : [],
                    ),
                    child: Icon(
                      vpnRunning ? Icons.power_settings_new : Icons.play_arrow,
                      color: Colors.white, size: 32,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // MTProto Proxy with Secret
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: cardColor,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: isDark ? const Color(0xFF30363D) : Colors.grey[200]!),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.flash_on, color: mtproxy ? const Color(0xFF6C63FF) : Colors.grey[500]),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('MTProto Proxy', style: TextStyle(fontWeight: FontWeight.w600, color: isDark ? Colors.white : Colors.black87)),
                          Text('Встроенный прокси для Telegram', style: TextStyle(fontSize: 12, color: Colors.grey[500])),
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
                  const SizedBox(height: 8),
                  // Secret display
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.amber.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.amber.withOpacity(0.3)),
                        ),
                        child: const Text('SECRET', style: TextStyle(fontSize: 10, color: Colors.amber, fontWeight: FontWeight.bold, letterSpacing: 1)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  GestureDetector(
                    onTap: () {
                      if (_mtproxySecret != null) {
                        Clipboard.setData(ClipboardData(text: _mtproxySecret!));
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Secret скопирован'), duration: Duration(seconds: 2)));
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF0D1117) : const Color(0xFFF5F5F5),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              _mtproxySecret ?? 'Генерация...',
                              style: TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 13,
                                color: isDark ? Colors.green[300] : Colors.green[700],
                              ),
                            ),
                          ),
                          Icon(Icons.copy, size: 18, color: const Color(0xFF6C63FF)),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(Icons.info_outline, size: 14, color: Colors.grey[500]),
                      const SizedBox(width: 6),
                      Text('Нажмите чтобы скопировать secret', style: TextStyle(fontSize: 11, color: Colors.grey[500])),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Text('Прокси:', style: TextStyle(fontSize: 12, color: Colors.grey[500])),
                      const SizedBox(width: 8),
                      Text('127.0.0.1:1443', style: TextStyle(fontSize: 13, fontFamily: 'monospace', fontWeight: FontWeight.w600, color: isDark ? Colors.white : Colors.black87)),
                    ],
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),

          // DPI Profiles
          Text('Профили обхода',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.black87)),
          const SizedBox(height: 8),
          ..._zapret.profiles.map((p) => Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: cardColor,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: isDark ? const Color(0xFF30363D) : Colors.grey[200]!),
            ),
            child: Row(
              children: [
                Icon(p.enabled ? Icons.check_circle : Icons.circle_outlined,
                  color: p.enabled ? const Color(0xFF6C63FF) : Colors.grey[500], size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(p.name, style: TextStyle(fontWeight: FontWeight.w500, color: isDark ? Colors.white : Colors.black87)),
                      Text(p.description, style: TextStyle(fontSize: 12, color: Colors.grey[500])),
                    ],
                  ),
                ),
                Switch(
                  value: p.enabled,
                  onChanged: vpnRunning ? (val) => setState(() => p.enabled = val) : null,
                  activeColor: const Color(0xFF6C63FF),
                ),
              ],
            ),
          )),

          // Info
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1A1E2E) : const Color(0xFFF0EEFF),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.info_outline, color: const Color(0xFF6C63FF), size: 20),
                    const SizedBox(width: 8),
                    Text('Как использовать', style: TextStyle(fontWeight: FontWeight.w600, color: isDark ? Colors.white : Colors.black87)),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  '1. Включите VPN кнопкой выше\n'
                  '2. Включите MTProto Proxy\n'
                  '3. Скопируйте secret\n'
                  '4. Добавьте прокси 127.0.0.1:1443 с этим secret в Telegram\n'
                  '5. Telegram будет идти через DPI-обход',
                  style: TextStyle(fontSize: 13, color: Colors.grey[500], height: 1.5),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
