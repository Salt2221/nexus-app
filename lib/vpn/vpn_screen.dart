import 'dart:async';
import 'package:flutter/material.dart';
import '../services/mtproto_proxy.dart';
import '../services/socks5_proxy.dart';

class VpnScreen extends StatefulWidget {
  const VpnScreen({super.key});
  @override
  State<VpnScreen> createState() => _VpnScreenState();
}

class _VpnScreenState extends State<VpnScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _mt = NexusMtprotoProxy();
  final _socks = Socks5Proxy.instance;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _refreshTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {}); // обновляем UI раз в секунду
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _tabController.dispose();
    super.dispose();
  }

  String _fmtBytes(int b) {
    if (b < 1024) return '$b B';
    if (b < 1024 * 1024) return '${(b / 1024).toStringAsFixed(1)} KB';
    if (b < 1024 * 1024 * 1024) return '${(b / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(b / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Защита'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.shield), text: 'MTProto'),
            Tab(icon: Icon(Icons.vpn_lock), text: 'SOCKS5'),
            Tab(icon: Icon(Icons.dns), text: 'DPI'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildMtProtoTab(theme),
          _buildSocks5Tab(theme),
          _buildDpiTab(theme),
        ],
      ),
    );
  }

  // ======================== MTProto Tab ========================

  Widget _buildMtProtoTab(ThemeData theme) {
    final running = _mt.isRunning;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // Status card
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Icon(
                    running ? Icons.shield : Icons.shield_outlined,
                    size: 64,
                    color: running ? Colors.green : Colors.grey,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    running ? 'MTProto активен' : 'MTProto остановлен',
                    style: theme.textTheme.titleLarge,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '127.0.0.1:1443',
                    style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey),
                  ),
                  const SizedBox(height: 16),
                  Switch(
                    value: running,
                    onChanged: (v) async {
                      if (v) {
                        await _mt.start();
                      } else {
                        await _mt.stop();
                      }
                      if (mounted) setState(() {});
                    },
                  ),
                  if (running) ...[
                    const SizedBox(height: 8),
                    // Proxy link
                    SelectableText(
                      _mt.getProxyLink(),
                      style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Нажми и скопируй, вставь в Telegram',
                      style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Stats row
          if (running) ...[
            Row(
              children: [
                _statCard(theme, 'Статус', _mt.status, Icons.circle, _mt.status == 'running' ? Colors.green : Colors.orange),
                const SizedBox(width: 8),
                _statCard(theme, 'Подключений', '${_mt.connections}', Icons.link, Colors.blue),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                _statCard(theme, 'Релеи (вверх/вниз)', _fmtBytes(_mt.bytesRelayed), Icons.swap_vert, Colors.purple),
                const SizedBox(width: 8),
                _statCard(theme, 'DC', _mt.currentDc, Icons.dns, Colors.teal),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                _statCard(theme, 'Рукопожатий OK', '${_mt.handshakeOk}', Icons.check_circle, Colors.green),
                const SizedBox(width: 8),
                _statCard(theme, 'Ошибок', '${_mt.handshakeFail}', Icons.error, Colors.red),
              ],
            ),
            const SizedBox(height: 8),
            _statCardWide(theme, 'Протокол', _mt.protocol, Icons.lock, Colors.amber),
            const SizedBox(height: 16),
            // Secret display
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Secret', style: theme.textTheme.titleSmall),
                    const SizedBox(height: 4),
                    SelectableText(
                      _mt.secret,
                      style: const TextStyle(fontSize: 10, fontFamily: 'monospace'),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '0xDD = Fake TLS режим. Используй этот secret в настройках прокси Telegram.',
                      style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ======================== SOCKS5 Tab ========================

  Widget _buildSocks5Tab(ThemeData theme) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Icon(
                    _socks.isRunning ? Icons.vpn_lock : Icons.vpn_lock_outlined,
                    size: 64,
                    color: _socks.isRunning ? Colors.green : Colors.grey,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _socks.isRunning ? 'SOCKS5 активен' : 'SOCKS5 остановлен',
                    style: theme.textTheme.titleLarge,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '127.0.0.1:${_socks.port}',
                    style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey),
                  ),
                  const SizedBox(height: 16),
                  Switch(
                    value: _socks.isRunning,
                    onChanged: (v) async {
                      if (v) {
                        await _socks.start();
                      } else {
                        await _socks.stop();
                      }
                      if (mounted) setState(() {});
                    },
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          if (_socks.isRunning) ...[
            Row(
              children: [
                _statCard(theme, 'Соединений', '${_socks.connections}', Icons.link, Colors.blue),
                const SizedBox(width: 8),
                _statCard(theme, 'Передано', _fmtBytes(_socks.bytesTransferred), Icons.swap_vert, Colors.purple),
              ],
            ),
            const SizedBox(height: 8),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('SOCKS5 proxy config', style: theme.textTheme.titleSmall),
                    const SizedBox(height: 4),
                    SelectableText(
                      'socks5://127.0.0.1:${_socks.port}',
                      style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Укажи в настройках Telegram: Настройки → Данные → Использование прокси → SOCKS5',
                      style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ======================== DPI Tab ========================

  Widget _buildDpiTab(ThemeData theme) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Icon(
                    Icons.dns,
                    size: 64,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'DPI обход',
                    style: theme.textTheme.titleLarge,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Активен через VpnService — все пакеты обрабатываются',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '• TLS-пакеты: рандомная фрагментация, паддинг\n'
                    '• HTTP: сплит заголовков, случайные пробелы\n'
                    '• Multi-split для больших пакетов\n'
                    '• Автоматический выбор стратегии (5 методов)',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text('Стратегии DPI обхода', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          _strategyItem('TLS паддинг', 'Добавляет случайные TLS-записи в конце'),
          _strategyItem('TLS фрагментация', 'Разбивает ClientHello на части'),
          _strategyItem('SNI паддинг', 'Добавляет мусорные расширения в SNI'),
          _strategyItem('HTTP сплит', 'Разделяет строку метод-путь символом \\n'),
          _strategyItem('Multi-split', 'Случайно мультиплексирует пакеты'),
        ],
      ),
    );
  }

  Widget _strategyItem(String name, String desc) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Card(
        child: ListTile(
          leading: const Icon(Icons.check_circle, color: Colors.green, size: 20),
          title: Text(name, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
          subtitle: Text(desc, style: const TextStyle(fontSize: 12)),
        ),
      ),
    );
  }

  // ======================== Helpers ========================

  Widget _statCard(ThemeData theme, String label, String value, IconData icon, Color color) {
    return Expanded(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(height: 4),
              Text(value, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: color)),
              Text(label, style: theme.textTheme.bodySmall),
            ],
          ),
        ),
      ),
    );
  }

  Widget _statCardWide(ThemeData theme, String label, String value, IconData icon, Color color) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(value, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: color)),
                Text(label, style: theme.textTheme.bodySmall),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
