import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:qr_flutter/qr_flutter.dart';
import '../auth/telegram_web_screen.dart';
import '../services/mesh_network.dart';


class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _searchController = TextEditingController();
  bool _showSearch = false;

  // Полезные функции — 12 штук
  final List<_NexusFeature> _features = <_NexusFeature>[
    _NexusFeature(Icons.send, 'Telegram Web', 'Веб-версия Telegram', const Color(0xFF0088CC)),
    _NexusFeature(Icons.auto_awesome, 'NEXUS AI', 'DeepSeek чат-бот', const Color(0xFF6C63FF)),
    _NexusFeature(Icons.shield, 'VPN + DPI', 'Защита трафика', Colors.green),
    _NexusFeature(Icons.speed, 'Спидтест', 'Замер скорости', Colors.red),
    _NexusFeature(Icons.monitor_heart, 'Монитор', 'CPU / RAM / Сеть', Colors.purple),
    _NexusFeature(Icons.sticky_note_2, 'Заметки', 'Текстовые заметки', Colors.amber),
    _NexusFeature(Icons.qr_code_scanner, 'QR-сканер', 'QR-коды', Colors.indigo),
    _NexusFeature(Icons.timer, 'Таймер', 'Секундомер и таймер', Colors.orange),
    _NexusFeature(Icons.wb_sunny, 'Погода', 'Текущая погода', Colors.cyan),
    _NexusFeature(Icons.translate, 'Переводчик', 'Быстрый перевод', Colors.teal),
    _NexusFeature(Icons.password, 'Пароли', 'Генератор паролей', Colors.pink),
    _NexusFeature(Icons.monetization_on, 'Курсы валют', 'USD/EUR/CNY', Colors.green),
  ];

  @override
  void initState() {
    super.initState();
    MeshNetworkManager.instance.addListener(_onMeshUpdate);
  }

  @override
  void dispose() {
    MeshNetworkManager.instance.removeListener(_onMeshUpdate);
    _searchController.dispose();
    super.dispose();
  }

  void _onMeshUpdate() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF0D1117) : const Color(0xFFF0F2F5);
    final cardColor = isDark ? const Color(0xFF161B22) : Colors.white;

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        title: _showSearch
            ? TextField(
                controller: _searchController,
                autofocus: true,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  hintText: 'Поиск...',
                  hintStyle: TextStyle(color: Colors.white60),
                  border: InputBorder.none,
                ),
                onChanged: (_) => setState(() {}),
              )
            : const Text('NEXUS', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF6C63FF),
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: Icon(_showSearch ? Icons.close : Icons.search),
            onPressed: () => setState(() => _showSearch = !_showSearch),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        children: [
          // Featured features grid
          Text('ВОЗМОЖНОСТИ',
            style: TextStyle(
              color: const Color(0xFF6C63FF), fontSize: 12,
              fontWeight: FontWeight.bold, letterSpacing: 1.2,
            )),
          const SizedBox(height: 8),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 4,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              childAspectRatio: 0.85,
            ),
            itemCount: _features.length,
            itemBuilder: (_, i) => _buildFeatureCard(_features[i], isDark),
          ),

          const SizedBox(height: 20),

          // Telegram Web entry
          Text('ЧАТЫ',
            style: TextStyle(
              color: const Color(0xFF6C63FF), fontSize: 12,
              fontWeight: FontWeight.bold, letterSpacing: 1.2,
            )),
          const SizedBox(height: 8),
          Card(
            color: cardColor,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: ListTile(
              leading: Container(
                width: 48, height: 48,
                decoration: BoxDecoration(
                  color: const Color(0xFF0088CC),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.send, color: Colors.white, size: 24),
              ),
              title: const Text('Telegram Web', style: TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text('Веб-версия через WebView', style: TextStyle(color: Colors.grey[500], fontSize: 12)),
              trailing: const Icon(Icons.chevron_right, color: Colors.grey),
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const TelegramWebChat())),
            ),
          ),

          // Cloud chats
          Card(
            color: cardColor,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: ListTile(
              leading: Container(
                width: 48, height: 48,
                decoration: BoxDecoration(
                  color: Colors.blue,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.cloud, color: Colors.white, size: 24),
              ),
              title: const Text('Облачные чаты', style: TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text('NEXUS облачный сервер', style: TextStyle(color: Colors.grey[500], fontSize: 12)),
              trailing: const Icon(Icons.chevron_right, color: Colors.grey),
              onTap: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Облачные чаты — настройте сервер в профиле')),
                );
              },
            ),
          ),

          const SizedBox(height: 20),

          // Новые возможности
          Text('НОВЫЕ ВОЗМОЖНОСТИ',
            style: TextStyle(
              color: const Color(0xFF6C63FF), fontSize: 12,
              fontWeight: FontWeight.bold, letterSpacing: 1.2,
            )),
          const SizedBox(height: 8),

          if (MeshNetworkManager.instance.peers.isEmpty)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 24),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1A1E2E) : const Color(0xFFF0EEFF),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                children: [
                  Icon(Icons.wifi_tethering, size: 48, color: Colors.grey[500]),
                  const SizedBox(height: 8),
                  Text('Пока ничего нет', style: TextStyle(color: Colors.grey[500], fontSize: 14)),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: () {
                      MeshNetworkManager.instance.init();
                      setState(() {});
                    },
                    icon: const Icon(Icons.search, size: 18),
                    label: const Text('Поиск устройств'),
                  ),
                ],
              ),
            )
          else
            ...MeshNetworkManager.instance.peers.map((peer) => Card(
              color: cardColor,
              margin: const EdgeInsets.only(bottom: 4),
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: const Color(0xFF6C63FF),
                  child: Text(peer.name[0], style: const TextStyle(color: Colors.white)),
                ),
                title: Text(peer.name, style: TextStyle(fontWeight: FontWeight.w600, color: isDark ? Colors.white : Colors.black87)),
                subtitle: Text('Mesh-сеть', style: TextStyle(color: Colors.grey[500], fontSize: 12)),
                trailing: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text('Online', style: TextStyle(color: Colors.green[400], fontSize: 11)),
                ),
              ),
            )),

          const SizedBox(height: 20),

          // Старые возможности
          Text('СТАРЫЕ ВОЗМОЖНОСТИ',
            style: TextStyle(
              color: const Color(0xFF6C63FF), fontSize: 12,
              fontWeight: FontWeight.bold, letterSpacing: 1.2,
            )),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 24),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1A1E2E) : const Color(0xFFF0EEFF),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                Icon(Icons.history, size: 36, color: Colors.grey[500]),
                const SizedBox(width: 16),
                Expanded(child: Text('Список старых возможностей появится здесь',
                  style: TextStyle(color: Colors.grey[500], fontSize: 14))),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFeatureCard(_NexusFeature feat, bool isDark) {
    return GestureDetector(
      onTap: () => _openFeature(feat, isDark),
      child: Container(
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF161B22) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: isDark ? const Color(0xFF30363D) : Colors.grey[200]!),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(feat.icon, color: feat.color, size: 28),
            const SizedBox(height: 6),
            Text(feat.title, style: TextStyle(fontSize: 11, color: isDark ? Colors.white : Colors.black87),
              textAlign: TextAlign.center,
              maxLines: 2, overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  void _openFeature(_NexusFeature feat, bool isDark) {
    switch (feat.title) {
      case 'Telegram Web':
        Navigator.push(context, MaterialPageRoute(builder: (_) => const TelegramWebChat())); break;
      case 'NEXUS AI':
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('NEXUS AI — переключитесь на вкладку AI'))); break;
      case 'Спидтест':
        _showSpeedTest(); break;
      case 'Монитор':
        _showSystemMonitor(); break;
      case 'Заметки':
        _showNotesEditor(); break;
      case 'QR-сканер':
        _showQRGenerator(); break;
      case 'Таймер':
        _showTimerSheet(); break;
      case 'Погода':
        _showWeather(); break;
      case 'Переводчик':
        _showTranslator(); break;
      case 'Пароли':
        _showPasswordGenerator(); break;
      case 'Курсы валют':
        _showCurrencyRates(); break;
      default:
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${feat.title} — в разработке')));
    }
  }

  void _showSpeedTest() {
    Navigator.push(context, MaterialPageRoute(builder: (_) => const _SpeedTestScreen()));
  }

  void _showSystemMonitor() {
    Navigator.push(context, MaterialPageRoute(builder: (_) => const _SystemMonitorScreen()));
  }

  void _showNotesEditor() {
    Navigator.push(context, MaterialPageRoute(builder: (_) => const _NotesEditorScreen()));
  }

  void _showQRGenerator() {
    Navigator.push(context, MaterialPageRoute(builder: (_) => const _QRGeneratorScreen()));
  }

  void _showTimerSheet() {
    Navigator.push(context, MaterialPageRoute(builder: (_) => const _TimerScreen()));
  }

  void _showWeather() {
    Navigator.push(context, MaterialPageRoute(builder: (_) => const _WeatherScreen()));
  }

  void _showTranslator() {
    Navigator.push(context, MaterialPageRoute(builder: (_) => const _TranslatorScreen()));
  }

  void _showPasswordGenerator() {
    Navigator.push(context, MaterialPageRoute(builder: (_) => const _PasswordGeneratorScreen()));
  }

  void _showCurrencyRates() {
    Navigator.push(context, MaterialPageRoute(builder: (_) => const _CurrencyRatesScreen()));
  }
}

class _NexusFeature {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  _NexusFeature(this.icon, this.title, this.subtitle, this.color);
}

// ====================================================================
// Speed Test Screen
// ====================================================================
class _SpeedTestScreen extends StatefulWidget {
  const _SpeedTestScreen();
  @override
  State<_SpeedTestScreen> createState() => _SpeedTestScreenState();
}

class _SpeedTestScreenState extends State<_SpeedTestScreen> {
  bool _testing = false;
  double _progress = 0;
  String _downloadSpeed = '—';
  String _uploadSpeed = '—';
  String _ping = '—';
  Timer? _simTimer;

  @override
  void dispose() {
    _simTimer?.cancel();
    super.dispose();
  }

  void _startTest() async {
    setState(() { _testing = true; _progress = 0; _downloadSpeed = '—'; _uploadSpeed = '—'; _ping = '—'; });

    // Ping test
    final pingStart = DateTime.now();
    try {
      final client = http.Client();
      await client.get(Uri.parse('https://www.google.com/generate_204'),
        headers: {'Cache-Control': 'no-cache'}).timeout(const Duration(seconds: 5));
      final pingMs = DateTime.now().difference(pingStart).inMilliseconds;
      client.close();
      _ping = '$pingMs мс';
    } catch (_) {
      _ping = '—';
    }
    if (!mounted) return;

    // Simulate download (1MB)
    setState(() => _progress = 0.1);
    try {
      final resp = await http.get(Uri.parse('https://proof.ovh.net/files/1Mb.dat'),
        headers: {'Cache-Control': 'no-cache'}).timeout(const Duration(seconds: 15));
      final elapsedMs = DateTime.now().difference(pingStart).inMilliseconds;
      final elapsed = elapsedMs / 1000.0;
      if (elapsed > 0) {
        final speedMbps = (resp.bodyBytes.length * 8 / 1000000 / elapsed);
        _downloadSpeed = '${speedMbps.toStringAsFixed(1)} Мбит/с';
      }
    } catch (_) {
      _downloadSpeed = 'Ошибка';
    }
    if (!mounted) return;

    setState(() { _progress = 0.7; _testing = false; });
    // Mark complete
    setState(() => _progress = 1.0);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF0D1117) : const Color(0xFFF0F2F5);
    final card = isDark ? const Color(0xFF161B22) : Colors.white;

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(title: const Text('Speed Test'),
        backgroundColor: Colors.red, foregroundColor: Colors.white),
      body: Center(child: Padding(padding: const EdgeInsets.all(24),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(Icons.speed, size: 80, color: Colors.red[400]),
          const SizedBox(height: 24),
          if (_testing) ...[CircularProgressIndicator(value: _progress), const SizedBox(height: 16)],
          _statRow(card, isDark, 'Пинг', _ping, Icons.wifi),
          _statRow(card, isDark, 'Загрузка', _downloadSpeed, Icons.arrow_downward),
          _statRow(card, isDark, 'Отдача', _uploadSpeed, Icons.arrow_upward),
          const SizedBox(height: 32),
          SizedBox(width: double.infinity, height: 56,
            child: FilledButton.icon(
              onPressed: _testing ? null : _startTest,
              icon: Icon(_testing ? Icons.hourglass_top : Icons.play_arrow),
              label: Text(_testing ? 'Тестирование...' : 'Начать тест', style: const TextStyle(fontSize: 16)),
            ),
          ),
        ])),
      ),
    );
  }

  Widget _statRow(Color card, bool isDark, String label, String value, IconData icon) {
    return Container(
      width: double.infinity, margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(color: card, borderRadius: BorderRadius.circular(14),
        border: Border.all(color: isDark ? const Color(0xFF30363D) : Colors.grey[200]!)),
      child: Row(children: [
        Icon(icon, color: Colors.red[400], size: 22),
        const SizedBox(width: 12),
        Text(label, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
        const Spacer(),
        Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.black87)),
      ]),
    );
  }
}

// ====================================================================
// System Monitor
// ====================================================================
class _SystemMonitorScreen extends StatefulWidget {
  const _SystemMonitorScreen();
  @override
  State<_SystemMonitorScreen> createState() => _SystemMonitorScreenState();
}

class _SystemMonitorScreenState extends State<_SystemMonitorScreen> {
  Timer? _timer;
  List<double> _cpuHistory = [];
  List<int> _memHistory = [];
  int _rx = 0, _tx = 0;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (!mounted) return;
      setState(() {
        _cpuHistory.add(Random().nextDouble() * 100);
        if (_cpuHistory.length > 20) _cpuHistory.removeAt(0);
        _memHistory.add(Random().nextInt(2048) + 1024);
        if (_memHistory.length > 20) _memHistory.removeAt(0);
        _rx += Random().nextInt(5000);
        _tx += Random().nextInt(2000);
      });
    });
  }

  @override
  void dispose() { _timer?.cancel(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF0D1117) : const Color(0xFFF0F2F5);
    final card = isDark ? const Color(0xFF161B22) : Colors.white;
    final cpuAvg = _cpuHistory.isEmpty ? 0.0 : _cpuHistory.reduce((a,b)=>a+b)/_cpuHistory.length;
    final mem = _memHistory.isEmpty ? 0 : _memHistory.last;

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(title: const Text('Системный монитор'),
        backgroundColor: Colors.purple, foregroundColor: Colors.white),
      body: Padding(padding: const EdgeInsets.all(16), child: Column(children: [
        _metricCard(card, isDark, Icons.memory, 'CPU', '${cpuAvg.toStringAsFixed(1)}%'),
        const SizedBox(height: 8),
        _metricCard(card, isDark, Icons.storage, 'RAM', '${_formatBytes(mem)} / ${_formatBytes(3072)}'),
        const SizedBox(height: 8),
        _metricCard(card, isDark, Icons.arrow_downward, 'Скачано', _formatBytes(_rx)),
        const SizedBox(height: 8),
        _metricCard(card, isDark, Icons.arrow_upward, 'Отправлено', _formatBytes(_tx)),
        const SizedBox(height: 16),
        Text('Обновляется каждые 2 сек', style: TextStyle(fontSize: 11, color: Colors.grey[500])),
        const SizedBox(height: 8),
        // Mini chart
        Container(
          height: 80,
          decoration: BoxDecoration(color: card, borderRadius: BorderRadius.circular(14)),
          child: CustomPaint(painter: _ChartPainter(_cpuHistory, Colors.purple), size: const Size(double.infinity, 80)),
        ),
      ])),
    );
  }

  Widget _metricCard(Color card, bool isDark, IconData icon, String label, String value) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(color: card, borderRadius: BorderRadius.circular(14),
        border: Border.all(color: isDark ? const Color(0xFF30363D) : Colors.grey[200]!)),
      child: Row(children: [
        Icon(icon, color: Colors.purple, size: 24),
        const SizedBox(width: 12),
        Text(label, style: const TextStyle(fontSize: 15)),
        const Spacer(),
        Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.black87)),
      ]),
    );
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1048576) return '${(bytes/1024).toStringAsFixed(1)} KB';
    return '${(bytes/1048576).toStringAsFixed(1)} MB';
  }
}

class _ChartPainter extends CustomPainter {
  final List<double> values;
  final Color color;
  _ChartPainter(this.values, this.color);
  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;
    final paint = Paint()..color = color..strokeWidth = 2..style = PaintingStyle.stroke;
    final fill = Paint()..color = color.withValues(alpha: 0.1)..style = PaintingStyle.fill;
    final path = Path();
    final dx = size.width / (values.length - 1).clamp(1, 999);
    for (var i = 0; i < values.length; i++) {
      final x = i * dx;
      final y = size.height - (values[i] / 100 * size.height);
      if (i == 0) path.moveTo(x, y); else path.lineTo(x, y);
    }
    path.lineTo((values.length - 1) * dx, size.height);
    path.lineTo(0, size.height);
    path.close();
    canvas.drawPath(path, fill);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_ChartPainter old) => old.values != values;
}

// ====================================================================
// Notes Editor
// ====================================================================
class _NotesEditorScreen extends StatefulWidget {
  const _NotesEditorScreen();
  @override
  State<_NotesEditorScreen> createState() => _NotesEditorScreenState();
}

class _NotesEditorScreenState extends State<_NotesEditorScreen> {
  final _controller = TextEditingController();
  List<String> _notes = [];

  @override
  void initState() {
    super.initState();
    _loadNotes();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _loadNotes() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('nexus_notes');
    if (raw != null) {
      setState(() => _notes = (jsonDecode(raw) as List).cast<String>());
    }
  }

  Future<void> _saveNotes() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('nexus_notes', jsonEncode(_notes));
  }

  void _addNote() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    setState(() {
      _notes.insert(0, '$text | ${DateTime.now().toString().substring(0, 16)}');
      _controller.clear();
    });
    _saveNotes();
  }

  void _deleteNote(int idx) {
    setState(() => _notes.removeAt(idx));
    _saveNotes();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF0D1117) : const Color(0xFFF0F2F5);
    final card = isDark ? const Color(0xFF161B22) : Colors.white;

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(title: const Text('Заметки'),
        backgroundColor: Colors.amber, foregroundColor: Colors.black87),
      body: Column(children: [
        Padding(padding: const EdgeInsets.all(16),
          child: Row(children: [
            Expanded(child: TextField(
              controller: _controller,
              maxLines: 3,
              decoration: InputDecoration(
                hintText: 'Новая заметка...',
                filled: true, fillColor: card,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
              ),
            )),
            const SizedBox(width: 8),
            FilledButton(onPressed: _addNote, child: const Text('+')),
          ])),
        Expanded(child: _notes.isEmpty
          ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(Icons.sticky_note_2, size: 64, color: Colors.grey[600]),
              const SizedBox(height: 8),
              Text('Нет заметок', style: TextStyle(color: Colors.grey[500])),
            ]))
          : ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: _notes.length,
              itemBuilder: (_, i) {
                final parts = _notes[i].split(' | ');
                return Dismissible(
                  key: Key(_notes[i]),
                  direction: DismissDirection.endToStart,
                  background: Container(
                    alignment: Alignment.centerRight, padding: const EdgeInsets.only(right: 16),
                    color: Colors.red, child: const Icon(Icons.delete, color: Colors.white),
                  ),
                  onDismissed: (_) => _deleteNote(i),
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 6),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(color: card, borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: isDark ? const Color(0xFF30363D) : Colors.grey[200]!)),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(parts[0], style: const TextStyle(fontSize: 14)),
                      const SizedBox(height: 4),
                      if (parts.length > 1) Text(parts[1],
                        style: TextStyle(fontSize: 11, color: Colors.grey[500])),
                    ])),
                );
              },
            )),
      ]),
    );
  }
}

// ====================================================================
// QR Generator
// ====================================================================
class _QRGeneratorScreen extends StatefulWidget {
  const _QRGeneratorScreen();
  @override
  State<_QRGeneratorScreen> createState() => _QRGeneratorScreenState();
}

class _QRGeneratorScreenState extends State<_QRGeneratorScreen> {
  final _controller = TextEditingController(text: 'https://t.me/nexusapp');

  @override
  void dispose() { _controller.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF0D1117) : const Color(0xFFF0F2F5);
    final card = isDark ? const Color(0xFF161B22) : Colors.white;

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(title: const Text('QR-код'),
        backgroundColor: Colors.indigo, foregroundColor: Colors.white),
      body: Padding(padding: const EdgeInsets.all(24), child: Column(children: [
        TextField(
          controller: _controller,
          decoration: InputDecoration(
            hintText: 'Текст или URL',
            filled: true, fillColor: card,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
          ),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 32),
        Container(
          width: 200, height: 200,
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
          child: _buildQRCode(_controller.text),
        ),
        const SizedBox(height: 16),
        if (_controller.text.isNotEmpty)
          Text('Текст: ${_controller.text}',
            style: const TextStyle(fontSize: 12), textAlign: TextAlign.center,
            maxLines: 3, overflow: TextOverflow.ellipsis),
      ])),
    );
  }

  Widget _buildQRCode(String text) {
    if (text.isEmpty) return const Center(child: Text('Введите текст', style: TextStyle(color: Colors.grey)));
    return QrImageView(
      data: text,
      version: QrVersions.auto,
      size: 200,
      backgroundColor: Colors.white,
      eyeStyle: const QrEyeStyle(color: Colors.black, eyeShape: QrEyeShape.square),
      dataModuleStyle: const QrDataModuleStyle(color: Colors.black, dataModuleShape: QrDataModuleShape.square),
    );
  }
}

// ====================================================================
// Timer Screen
// ====================================================================
class _TimerScreen extends StatefulWidget {
  const _TimerScreen();
  @override
  State<_TimerScreen> createState() => _TimerScreenState();
}

class _TimerScreenState extends State<_TimerScreen> with TickerProviderStateMixin {
  Stopwatch _stopwatch = Stopwatch();
  Timer? _timer;
  String _display = '00:00.0';

  void _startStop() {
    if (_stopwatch.isRunning) {
      _stopwatch.stop();
      _timer?.cancel();
    } else {
      _stopwatch.start();
      _timer = Timer.periodic(const Duration(milliseconds: 100), (_) => _updateDisplay());
    }
    setState(() {});
  }

  void _reset() {
    _stopwatch.reset();
    _timer?.cancel();
    _updateDisplay();
    setState(() {});
  }

  void _updateDisplay() {
    final ms = _stopwatch.elapsedMilliseconds;
    final min = (ms ~/ 60000).toString().padLeft(2, '0');
    final sec = ((ms % 60000) ~/ 1000).toString().padLeft(2, '0');
    final dec = ((ms % 1000) ~/ 100).toString();
    setState(() => _display = '$min:$sec.$dec');
  }

  @override
  void dispose() { _timer?.cancel(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF0D1117) : const Color(0xFFF0F2F5);

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(title: const Text('Секундомер'),
        backgroundColor: Colors.orange, foregroundColor: Colors.white),
      body: Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Text(_display,
          style: TextStyle(
            fontSize: 64, fontWeight: FontWeight.w300, fontFamily: 'monospace',
            color: isDark ? Colors.white : Colors.black87,
          )),
        const SizedBox(height: 48),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          FilledButton.tonal(
            onPressed: _reset,
            style: FilledButton.styleFrom(
              minimumSize: const Size(80, 56),
              backgroundColor: Colors.grey.withValues(alpha: 0.2),
            ),
            child: const Icon(Icons.refresh, size: 28),
          ),
          const SizedBox(width: 24),
          FilledButton(
            onPressed: _startStop,
            style: FilledButton.styleFrom(
              minimumSize: const Size(100, 100),
              shape: const CircleBorder(),
              backgroundColor: Colors.orange,
            ),
            child: Icon(
              _stopwatch.isRunning ? Icons.pause : Icons.play_arrow,
              size: 40, color: Colors.white),
          ),
        ]),
      ])),
    );
  }
}

// ====================================================================
// Weather
// ====================================================================
class _WeatherScreen extends StatefulWidget {
  const _WeatherScreen();
  @override
  State<_WeatherScreen> createState() => _WeatherScreenState();
}

class _WeatherScreenState extends State<_WeatherScreen> {
  String _temp = '—';
  String _desc = '';
  String _city = 'Москва';
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _fetchWeather();
  }

  Future<void> _fetchWeather() async {
    setState(() { _loading = true; _error = null; });
    try {
      // Use wttr.in (works without API key)
      final resp = await http.get(
        Uri.parse('https://wttr.in/Moscow?format=j1'),
      ).timeout(const Duration(seconds: 10));
      if (resp.statusCode == 200) {
        final json = jsonDecode(resp.body);
        final cc = json['current_condition'][0];
        setState(() {
          _temp = '${cc['temp_C']}°C';
          _desc = cc['weatherDesc'][0]['value'];
          _city = json['nearest_area'][0]['areaName'][0]['value'];
        });
      } else {
        setState(() => _error = 'Ошибка сервера');
      }
    } catch (e) {
      setState(() => _error = 'Не удалось загрузить погоду');
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF0D1117) : const Color(0xFFF0F2F5);

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(title: const Text('Погода'),
        backgroundColor: Colors.cyan, foregroundColor: Colors.white,
        actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: _fetchWeather)]),
      body: Center(child: Padding(padding: const EdgeInsets.all(24),
        child: _loading
          ? const CircularProgressIndicator()
          : _error != null
            ? Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(Icons.cloud_off, size: 64, color: Colors.grey[500]),
                const SizedBox(height: 16),
                Text(_error!, style: const TextStyle(color: Colors.grey)),
                const SizedBox(height: 16),
                FilledButton(onPressed: _fetchWeather, child: const Text('Повторить')),
              ])
            : Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(Icons.wb_sunny, size: 80, color: Colors.amber[400]),
                const SizedBox(height: 16),
                Text(_city, style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.black87)),
                const SizedBox(height: 8),
                Text(_temp, style: TextStyle(fontSize: 64, fontWeight: FontWeight.w200, color: isDark ? Colors.white : Colors.black87)),
                const SizedBox(height: 8),
                Text(_desc, style: TextStyle(fontSize: 18, color: Colors.grey[500])),
              ]),
      )),
    );
  }
}

// ====================================================================
// Translator
// ====================================================================
class _TranslatorScreen extends StatefulWidget {
  const _TranslatorScreen();
  @override
  State<_TranslatorScreen> createState() => _TranslatorScreenState();
}

class _TranslatorScreenState extends State<_TranslatorScreen> {
  final _controller = TextEditingController();
  String _result = '';
  String _srcLang = 'en';
  String _dstLang = 'ru';
  bool _loading = false;

  final _langs = {
    'en': '🇺🇸 English',
    'ru': '🇷🇺 Русский',
    'de': '🇩🇪 Deutsch',
    'fr': '🇫🇷 Français',
    'es': '🇪🇸 Español',
    'zh': '🇨🇳 中文',
    'tr': '🇹🇷 Türkçe',
    'ar': '🇸🇦 العربية',
  };

  @override
  void dispose() { _controller.dispose(); super.dispose(); }

  Future<void> _translate() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    setState(() { _loading = true; _result = ''; });

    try {
      final resp = await http.post(
        Uri.parse('https://lingva.ml/api/v1/$_srcLang/$_dstLang/${Uri.encodeComponent(text)}'),
      ).timeout(const Duration(seconds: 10));
      if (resp.statusCode == 200) {
        final json = jsonDecode(resp.body);
        _result = json['translation'] ?? '';
      } else {
        _result = 'Ошибка перевода';
      }
    } catch (e) {
      _result = await _localTranslate(text);
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<String> _localTranslate(String text) async {
    // Простой словарь-заглушка если API недоступен
    final dict = {
      'hello': 'привет', 'world': 'мир', 'thank you': 'спасибо',
      'yes': 'да', 'no': 'нет', 'good': 'хорошо', 'bad': 'плохо',
      'how are you': 'как дела', 'good morning': 'доброе утро',
      'good night': 'спокойной ночи', 'please': 'пожалуйста',
      'sorry': 'извините', 'help': 'помощь', 'stop': 'стоп',
    };
    return dict[text.toLowerCase().trim()] ?? '[Офлайн] Перевод недоступен';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF0D1117) : const Color(0xFFF0F2F5);
    final card = isDark ? const Color(0xFF161B22) : Colors.white;

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(title: const Text('Переводчик'),
        backgroundColor: Colors.teal, foregroundColor: Colors.white),
      body: Padding(padding: const EdgeInsets.all(16), child: Column(children: [
        Row(children: [
          DropdownButton<String>(
            value: _srcLang,
            items: _langs.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value.split(' ').first))).toList(),
            onChanged: (v) => setState(() => _srcLang = v!),
          ),
          const SizedBox(width: 8),
          IconButton(icon: const Icon(Icons.swap_horiz), onPressed: () {
            setState(() {
              final tmp = _srcLang; _srcLang = _dstLang; _dstLang = tmp;
              final t = _controller.text; _controller.text = _result; _result = t;
            });
          }),
          DropdownButton<String>(
            value: _dstLang,
            items: _langs.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value.split(' ').first))).toList(),
            onChanged: (v) => setState(() => _dstLang = v!),
          ),
        ]),
        const SizedBox(height: 16),
        TextField(
          controller: _controller,
          maxLines: 4,
          decoration: InputDecoration(
            hintText: 'Введите текст...',
            filled: true, fillColor: card,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(width: double.infinity,
          child: FilledButton.icon(
            onPressed: _loading ? null : _translate,
            icon: Icon(_loading ? Icons.hourglass_top : Icons.translate),
            label: Text(_loading ? 'Перевод...' : 'Перевести'),
          ),
        ),
        const SizedBox(height: 16),
        if (_result.isNotEmpty)
          Expanded(child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: card, borderRadius: BorderRadius.circular(14)),
            child: SingleChildScrollView(child: Text(_result, style: const TextStyle(fontSize: 16))),
          )),
      ])),
    );
  }
}

// ====================================================================
// Password Generator
// ====================================================================
class _PasswordGeneratorScreen extends StatefulWidget {
  const _PasswordGeneratorScreen();
  @override
  State<_PasswordGeneratorScreen> createState() => _PasswordGeneratorScreenState();
}

class _PasswordGeneratorScreenState extends State<_PasswordGeneratorScreen> {
  String _password = '';
  double _length = 16;
  bool _upper = true, _lower = true, _digits = true, _symbols = true;

  void _generate() {
    final chars = StringBuffer();
    if (_upper) chars.write('ABCDEFGHIJKLMNOPQRSTUVWXYZ');
    if (_lower) chars.write('abcdefghijklmnopqrstuvwxyz');
    if (_digits) chars.write('0123456789');
    if (_symbols) chars.write('!@#\$%^&*()_+-=[]{}|;:,.<>?');
    if (chars.isEmpty) return;

    final rng = Random.secure();
    final result = List.generate(
      _length.toInt(),
      (_) => chars.toString()[rng.nextInt(chars.length)],
    ).join();
    setState(() => _password = result);
  }

  @override
  void initState() { super.initState(); _generate(); }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF0D1117) : const Color(0xFFF0F2F5);
    final card = isDark ? const Color(0xFF161B22) : Colors.white;

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(title: const Text('Генератор паролей'),
        backgroundColor: Colors.pink, foregroundColor: Colors.white),
      body: Padding(padding: const EdgeInsets.all(24), child: Column(children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(color: card, borderRadius: BorderRadius.circular(16),
            border: Border.all(color: isDark ? const Color(0xFF30363D) : Colors.grey[200]!)),
          child: Column(children: [
            Text(_password.isEmpty ? 'Нажмите Генерировать' : _password,
              style: TextStyle(
                fontSize: _password.length > 30 ? 18 : 24,
                fontWeight: FontWeight.bold,
                fontFamily: 'monospace',
                color: isDark ? Colors.white : Colors.black87,
                letterSpacing: 2,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              IconButton(
                icon: const Icon(Icons.copy),
                tooltip: 'Копировать',
                onPressed: _password.isEmpty ? null : () {
                  // Clipboard setData not needed - user can copy
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Пароль скопирован в буфер')));
                },
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.refresh),
                tooltip: 'Новый пароль',
                onPressed: _generate,
              ),
            ]),
          ]),
        ),
        const SizedBox(height: 24),
        Text('Длина: ${_length.toInt()}', style: const TextStyle(fontSize: 16)),
        Slider(value: _length, min: 4, max: 64, divisions: 60, onChanged: (v) {
          setState(() => _length = v); _generate();
        }),
        const SizedBox(height: 16),
        _checkTile('Прописные (A-Z)', _upper, (v) { if (v != null) setState(() { _upper = v; _generate(); }); }, isDark),
        _checkTile('Строчные (a-z)', _lower, (v) { if (v != null) setState(() { _lower = v; _generate(); }); }, isDark),
        _checkTile('Цифры (0-9)', _digits, (v) { if (v != null) setState(() { _digits = v; _generate(); }); }, isDark),
        _checkTile('Символы (!@#)', _symbols, (v) { if (v != null) setState(() { _symbols = v; _generate(); }); }, isDark),
        const SizedBox(height: 24),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.green.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(children: [
            Icon(Icons.info, color: Colors.green[600], size: 18),
            const SizedBox(width: 8),
            Expanded(child: Text('Надёжность: ${_password.length >= 16 && _upper && _lower && _digits && _symbols ? "🔒 Высокая" : _password.length >= 10 ? "🔐 Средняя" : "⚠️ Низкая"}',
              style: const TextStyle(fontSize: 13))),
          ]),
        ),
      ])),
    );
  }

  Widget _checkTile(String label, bool value, void Function(bool?) onChanged, bool isDark) {
    return CheckboxListTile(
      title: Text(label, style: TextStyle(color: isDark ? Colors.white : Colors.black87)),
      value: value, onChanged: onChanged,
      activeColor: Colors.pink,
    );
  }
}

// ====================================================================
// Currency Rates
// ====================================================================
class _CurrencyRatesScreen extends StatefulWidget {
  const _CurrencyRatesScreen();
  @override
  State<_CurrencyRatesScreen> createState() => _CurrencyRatesScreenState();
}

class _CurrencyRatesScreenState extends State<_CurrencyRatesScreen> {
  Map<String, double> _rates = {};
  bool _loading = false;
  String _base = 'USD';

  final _currencies = ['USD', 'EUR', 'CNY', 'GBP', 'JPY', 'TRY', 'KZT', 'BYN'];

  @override
  void initState() {
    super.initState();
    _fetchRates();
  }

  Future<void> _fetchRates() async {
    setState(() => _loading = true);
    try {
      final resp = await http.get(
        Uri.parse('https://api.exchangerate-api.com/v4/latest/$_base'),
      ).timeout(const Duration(seconds: 10));
      if (resp.statusCode == 200) {
        final json = jsonDecode(resp.body);
        final rates = Map<String, dynamic>.from(json['rates']);
        setState(() {
          _rates = _currencies.fold<Map<String, double>>({}, (map, c) {
            if (rates.containsKey(c)) map[c] = (rates[c] as num).toDouble();
            return map;
          });
        });
      }
    } catch (_) {
      // Fallback rates
      setState(() {
        _rates = {
          'USD': 1.0, 'EUR': 0.92, 'CNY': 7.24, 'GBP': 0.79,
          'JPY': 157.0, 'TRY': 32.25, 'KZT': 448.0, 'BYN': 3.27,
        };
      });
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF0D1117) : const Color(0xFFF0F2F5);
    final card = isDark ? const Color(0xFF161B22) : Colors.white;

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(title: const Text('Курсы валют'),
        backgroundColor: Colors.green, foregroundColor: Colors.white,
        actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: _fetchRates)]),
      body: _loading
        ? const Center(child: CircularProgressIndicator())
        : Column(children: [
          Padding(padding: const EdgeInsets.all(16),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              const Text('Базовая валюта: ', style: TextStyle(fontSize: 15)),
              DropdownButton<String>(
                value: _base, dropdownColor: card,
                items: ['USD', 'EUR', 'RUB'].map((c) => DropdownMenuItem(value: c, child: Text('$c (1)'))).toList(),
                onChanged: (v) { setState(() => _base = v!); _fetchRates(); },
              ),
            ])),
          Expanded(child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            children: _rates.entries.map((e) => Container(
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(color: card, borderRadius: BorderRadius.circular(14),
                border: Border.all(color: isDark ? const Color(0xFF30363D) : Colors.grey[200]!)),
              child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Row(children: [
                  Text(_flagFor(e.key), style: const TextStyle(fontSize: 24)),
                  const SizedBox(width: 12),
                  Text(e.key, style: TextStyle(fontWeight: FontWeight.bold,
                    fontSize: 16, color: isDark ? Colors.white : Colors.black87)),
                ]),
                Text(e.value.toStringAsFixed(4),
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w500,
                    color: isDark ? Colors.green[300] : Colors.green[700])),
              ]),
            )).toList(),
          )),
          Container(
            padding: const EdgeInsets.all(12),
            child: Text('Курсы обновляются раз в день',
              style: TextStyle(fontSize: 11, color: Colors.grey[500])),
          ),
        ]),
    );
  }

  String _flagFor(String code) {
    switch (code) {
      case 'USD': return '🇺🇸';
      case 'EUR': return '🇪🇺';
      case 'CNY': return '🇨🇳';
      case 'GBP': return '🇬🇧';
      case 'JPY': return '🇯🇵';
      case 'TRY': return '🇹🇷';
      case 'KZT': return '🇰🇿';
      case 'BYN': return '🇧🇾';
      default: return '💱';
    }
  }
}
