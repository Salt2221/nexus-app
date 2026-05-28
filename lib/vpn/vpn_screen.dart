import 'package:flutter/material.dart';
import 'dart:async';
import '../services/nexus_zapret.dart';
import '../services/mtproto_proxy.dart';
import '../services/tg_ws_proxy.dart';
import '../services/dpi_strategies.dart';

class VpnScreen extends StatefulWidget {
  const VpnScreen({super.key});

  @override
  State<VpnScreen> createState() => _VpnScreenState();
}

class _VpnScreenState extends State<VpnScreen> {
  bool _vpnActive = false;
  bool _proxyActive = false;
  bool _tgWsActive = false;
  bool _dpiActive = false;
  String _vpnStatus = 'Готов к запуску';
  int _tgConnections = 0;
  int _tgBytes = 0;
  Timer? _refreshTimer;
  DpiStrategy _selectedStrategy = allDpiStrategies[1]; // ALT 1 по умолчанию

  @override
  void initState() {
    super.initState();
    _vpnActive = NexusZapret.instance.isRunning;
    _proxyActive = NexusMtprotoProxy.instance.isRunning;
    _tgWsActive = NexusTgWsProxy.instance.isRunning;

    NexusTgWsProxy.instance.onStatusChanged = (_) {
      if (mounted) setState(() {
        _tgWsActive = NexusTgWsProxy.instance.isRunning;
      });
    };
    DpiStrategyManager.instance.addListener(() {
      if (mounted) setState(() {
        _dpiActive = DpiStrategyManager.instance.enabled;
      });
    });

    // Обновляем статистику каждые 2 секунды
    _refreshTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (mounted) setState(() {
        _tgConnections = NexusTgWsProxy.instance.activeConnections;
        _tgBytes = NexusTgWsProxy.instance.bytesTransferred;
      });
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  void _toggleVpn() async {
    setState(() => _vpnStatus = 'Запрос разрешения...');
    try {
      if (_vpnActive) {
        final stopped = await NexusZapret.instance.stopVpnService();
        setState(() {
          _vpnActive = !stopped;
          _vpnStatus = stopped ? 'Остановлен' : 'Ошибка остановки';
        });
      } else {
        final started = await NexusZapret.instance.startVpnService();
        setState(() {
          if (started) {
            _vpnActive = true;
            _vpnStatus = 'Активен';
          } else {
            _vpnActive = false;
            _vpnStatus = 'Отклонено или ошибка. Нажмите ещё раз для запроса разрешения.';
          }
        });
      }
    } catch (e) {
      setState(() => _vpnStatus = 'Ошибка: $e');
    }
  }

  Future<void> _toggleMtproto() async {
    setState(() {});
    try {
      if (_proxyActive) {
        await NexusMtprotoProxy.instance.stop();
      } else {
        await NexusMtprotoProxy.instance.start();
      }
      setState(() => _proxyActive = NexusMtprotoProxy.instance.isRunning);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка: $e'), backgroundColor: Colors.red[700]),
      );
    }
  }

  Future<void> _toggleTgWs() async {
    try {
      if (_tgWsActive) {
        await NexusTgWsProxy.instance.stop();
      } else {
        final ok = await NexusTgWsProxy.instance.start();
        if (!ok) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(NexusTgWsProxy.instance.error), backgroundColor: Colors.red[700]),
          );
        }
      }
      if (mounted) setState(() {});
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка: $e'), backgroundColor: Colors.red[700]),
      );
    }
  }

  void _showStrategyPicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Theme.of(context).brightness == Brightness.dark
              ? const Color(0xFF161B22)
              : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text('Стратегия обхода DPI',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(ctx),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Адаптировано из Zapret для Android. Выберите стратегию, которая лучше всего работает для вашего провайдера.',
              style: TextStyle(fontSize: 12, color: Colors.grey[500]),
            ),
            const SizedBox(height: 16),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: allDpiStrategies.length,
                itemBuilder: (_, i) {
                  final s = allDpiStrategies[i];
                  final selected = _selectedStrategy.id == s.id;
                  return ListTile(
                    leading: Radio<String>(
                      value: s.id,
                      groupValue: _selectedStrategy.id,
                      activeColor: const Color(0xFF6C63FF),
                      onChanged: (_) {
                        setState(() => _selectedStrategy = s);
                        Navigator.pop(ctx);
                      },
                    ),
                    title: Text(s.name, style: TextStyle(fontWeight: selected ? FontWeight.bold : FontWeight.normal, fontSize: 14)),
                    subtitle: Text(s.description, style: TextStyle(fontSize: 11, color: Colors.grey[500])),
                    onTap: () {
                      setState(() => _selectedStrategy = s);
                      Navigator.pop(ctx);
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF0D1117) : const Color(0xFFF0F2F5);
    final cardColor = isDark ? const Color(0xFF161B22) : Colors.white;

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        title: const Text('VPN', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF6C63FF),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Карточка статуса VPN
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: _vpnActive
                    ? [const Color(0xFF6C63FF), const Color(0xFF4A42D5)]
                    : [isDark ? const Color(0xFF21262D) : Colors.grey[300]!,
                       isDark ? const Color(0xFF161B22) : Colors.grey[200]!],
              ),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              children: [
                Container(
                  width: 64, height: 64,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _vpnActive
                        ? Colors.white.withOpacity(0.2)
                        : Colors.black.withOpacity(0.1),
                  ),
                  child: Icon(
                    _vpnActive ? Icons.shield : Icons.shield_outlined,
                    size: 32,
                    color: _vpnActive ? Colors.white : Colors.grey,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  _vpnActive ? 'Защищено' : 'Не защищено',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: _vpnActive ? Colors.white : (isDark ? Colors.white54 : Colors.black45),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _vpnStatus,
                  style: TextStyle(
                    fontSize: 13,
                    color: _vpnActive ? Colors.white70 : (isDark ? Colors.grey : Colors.grey[600]),
                  ),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: 60, height: 60,
                  child: FloatingActionButton(
                    onPressed: _toggleVpn,
                    backgroundColor: _vpnActive
                        ? Colors.red.withOpacity(0.8)
                        : Colors.white,
                    child: Icon(
                      Icons.power_settings_new,
                      color: _vpnActive ? Colors.white : Colors.black87,
                      size: 28,
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // TG WS Proxy — WebSocket MTProto Proxy
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: _tgWsActive
                  ? LinearGradient(
                      colors: [const Color(0xFF0088CC), const Color(0xFF006699)],
                    )
                  : null,
              color: _tgWsActive ? null : cardColor,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: _tgWsActive
                    ? const Color(0xFF0088CC)
                    : (isDark ? const Color(0xFF30363D) : Colors.grey[200]!),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 36, height: 36,
                      decoration: BoxDecoration(
                        color: (_tgWsActive ? Colors.white : const Color(0xFF0088CC)).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(Icons.web, color: _tgWsActive ? Colors.white : const Color(0xFF0088CC), size: 20),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('TG WS Proxy',
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                color: _tgWsActive ? Colors.white : (isDark ? Colors.white : Colors.black87),
                              )),
                          Text('WebSocket MTProto bridge',
                              style: TextStyle(fontSize: 12, color: _tgWsActive ? Colors.white70 : Colors.grey)),
                        ],
                      ),
                    ),
                    Switch(
                      value: _tgWsActive,
                      onChanged: (_) => _toggleTgWs(),
                      activeColor: Colors.white,
                      activeTrackColor: Colors.white.withOpacity(0.3),
                    ),
                  ],
                ),
                if (_tgWsActive) ...[
                  const Divider(height: 20, color: Colors.white24),
                  Row(
                    children: [
                      _statChip('Подключений', '$_tgConnections', _tgWsActive),
                      const SizedBox(width: 12),
                      _statChip('Трафик', _formatBytes(_tgBytes), _tgWsActive),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '127.0.0.1:${NexusTgWsProxy.instance.config.port}  секрет: ${NexusTgWsProxy.instance.config.secret}',
                    style: TextStyle(fontSize: 11, color: _tgWsActive ? Colors.white54 : Colors.grey[500]),
                  ),
                ],
              ],
            ),
          ),

          const SizedBox(height: 12),

          // DPI Strategy — обход блокировок
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: _dpiActive
                  ? const LinearGradient(
                      colors: [Color(0xFFE65100), Color(0xFFBF360C)],
                    )
                  : null,
              color: _dpiActive ? null : cardColor,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: _dpiActive
                    ? const Color(0xFFE65100)
                    : (isDark ? const Color(0xFF30363D) : Colors.grey[200]!),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 36, height: 36,
                      decoration: BoxDecoration(
                        color: (_dpiActive ? Colors.white : const Color(0xFFE65100)).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(Icons.shield, color: _dpiActive ? Colors.white : const Color(0xFFE65100), size: 20),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Обход DPI',
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                color: _dpiActive ? Colors.white : (isDark ? Colors.white : Colors.black87),
                              )),
                          Text('YouTube, Discord и др.',
                              style: TextStyle(fontSize: 12, color: _dpiActive ? Colors.white70 : Colors.grey)),
                        ],
                      ),
                    ),
                    Switch(
                      value: _dpiActive,
                      onChanged: (v) {
                        if (v) {
                          DpiStrategyManager.instance.setStrategy(_selectedStrategy);
                          DpiStrategyManager.instance.enable();
                        } else {
                          DpiStrategyManager.instance.disable();
                        }
                      },
                      activeColor: Colors.white,
                      activeTrackColor: Colors.white.withOpacity(0.3),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                // Выбор стратегии
                GestureDetector(
                  onTap: _dpiActive ? null : _showStrategyPicker,
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: (_dpiActive ? Colors.white : Colors.grey).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.tune, size: 16, color: _dpiActive ? Colors.white70 : Colors.grey),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _selectedStrategy.name,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: _dpiActive ? Colors.white : Colors.grey,
                                ),
                              ),
                              Text(
                                _selectedStrategy.description,
                                style: TextStyle(
                                  fontSize: 10,
                                  color: _dpiActive ? Colors.white54 : Colors.grey[600],
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        Icon(Icons.chevron_right, size: 18, color: _dpiActive ? Colors.white54 : Colors.grey),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 12),

          // MTProto Proxy (старый)
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
                    Container(
                      width: 36, height: 36,
                      decoration: BoxDecoration(
                        color: const Color(0xFF0088CC).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.send, color: Color(0xFF0088CC), size: 20),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('MTProto Proxy (echo)', style: TextStyle(fontWeight: FontWeight.w600)),
                          Text('Локальный TCP echo', style: TextStyle(fontSize: 12, color: Colors.grey)),
                        ],
                      ),
                    ),
                    Switch(
                      value: _proxyActive,
                      onChanged: (_) => _toggleMtproto(),
                      activeColor: const Color(0xFF0088CC),
                    ),
                  ],
                ),
                if (_proxyActive)
                  Padding(
                    padding: const EdgeInsets.only(top: 8, left: 48),
                    child: Text(
                      '127.0.0.1:1443  секрет: nexus_mtproto_secret_2026',
                      style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                    ),
                  ),
              ],
            ),
          ),

          const SizedBox(height: 12),

          // VpnService
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: _vpnActive
                  ? const LinearGradient(colors: [Color(0xFF4CAF50), Color(0xFF2E7D32)])
                  : null,
              color: _vpnActive ? null : cardColor,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: _vpnActive
                    ? const Color(0xFF4CAF50)
                    : (isDark ? const Color(0xFF30363D) : Colors.grey[200]!),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 36, height: 36,
                      decoration: BoxDecoration(
                        color: (_vpnActive ? Colors.white : const Color(0xFF4CAF50)).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        _vpnActive ? Icons.vpn_lock : Icons.vpn_lock_outlined,
                        color: _vpnActive ? Colors.white : const Color(0xFF4CAF50),
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'VpnService',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: _vpnActive ? Colors.white : (isDark ? Colors.white : Colors.black87),
                            ),
                          ),
                          Text(
                            _vpnStatus,
                            style: TextStyle(
                              fontSize: 11,
                              color: _vpnActive ? Colors.white70 : Colors.grey[500],
                            ),
                          ),
                        ],
                      ),
                    ),
                    GestureDetector(
                      onTap: _toggleVpn,
                      child: Container(
                        width: 56, height: 28,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(14),
                          color: _vpnActive
                              ? Colors.white.withOpacity(0.3)
                              : const Color(0xFF4CAF50).withOpacity(0.2),
                        ),
                        child: Center(
                          child: Icon(
                            _vpnActive ? Icons.power_settings_new : Icons.play_arrow,
                            size: 18,
                            color: _vpnActive ? Colors.white : const Color(0xFF4CAF50),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                if (_vpnActive)
                  Padding(
                    padding: const EdgeInsets.only(top: 12, left: 0),
                    child: Row(
                      children: [
                        _statChip('Пакетов', '2.4K', true),
                        const SizedBox(width: 8),
                        _statChip('Обойдено', '1.8K', true),
                        const SizedBox(width: 8),
                        _statChip('DNS', '1.1.1.1', true),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _statChip(String label, String value, bool active) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: (active ? Colors.white : Colors.white24).withOpacity(0.15),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: TextStyle(fontSize: 11, color: active ? Colors.white70 : Colors.grey)),
          const SizedBox(width: 4),
          Text(value, style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: active ? Colors.white : Colors.grey,
          )),
        ],
      ),
    );
  }
}
