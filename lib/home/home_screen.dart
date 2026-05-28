import 'package:flutter/material.dart';
import '../auth/telegram_web_screen.dart';
import '../services/mesh_network.dart';
import '../settings/settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _searchController = TextEditingController();
  bool _showSearch = false;

  // Demo contacts — like Telegram contacts list
  final List<_NexusFeature> _features = <_NexusFeature>[
    _NexusFeature(Icons.cloud, 'Облачные чаты', 'Синхронизация с сервером', Colors.blue),
    _NexusFeature(Icons.send, 'Telegram Web', 'Веб-версия Telegram', const Color(0xFF0088CC)),
    _NexusFeature(Icons.auto_awesome, 'NEXUS AI', 'DeepSeek чат-бот', const Color(0xFF6C63FF)),
    _NexusFeature(Icons.shield, 'VPN + DPI', 'Защита трафика', Colors.green),
    _NexusFeature(Icons.sd_storage, 'Файловый менеджер', 'Управление файлами', Colors.orange),
    _NexusFeature(Icons.sticky_note_2, 'Заметки', 'Текстовые заметки', Colors.amber),
    _NexusFeature(Icons.music_note, 'Аудиоплеер', 'Воспроизведение музыки', Colors.pink),
    _NexusFeature(Icons.camera_alt, 'Камера', 'Съёмка фото/видео', Colors.cyan),
    _NexusFeature(Icons.location_on, 'Геолокация', 'Отправка местоположения', Colors.red),
    _NexusFeature(Icons.mic, 'Голосовые сообщения', 'Аудиозапись', Colors.purple),
    _NexusFeature(Icons.contacts, 'Контакты', 'Список контактов', Colors.teal),
    _NexusFeature(Icons.graphic_eq, 'Эквалайзер', 'Настройка звука', Colors.indigo),
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

          // Nearby devices / Mesh
          Text('УСТРОЙСТВА РЯДОМ',
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
                  Text('Устройства не найдены', style: TextStyle(color: Colors.grey[500], fontSize: 14)),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: () {
                      MeshNetworkManager.instance.init();
                      setState(() {});
                    },
                    icon: const Icon(Icons.search, size: 18),
                    label: const Text('Поиск'),
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
                subtitle: Text('Mesh', style: TextStyle(color: Colors.grey[500], fontSize: 12)),
                trailing: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.green.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text('Online', style: TextStyle(color: Colors.green[400], fontSize: 11)),
                ),
              ),
            )),
        ],
      ),
    );
  }

  Widget _buildFeatureCard(_NexusFeature feat, bool isDark) {
    return GestureDetector(
      onTap: () {
        if (feat.title == 'Telegram Web') {
          Navigator.push(context, MaterialPageRoute(builder: (_) => const TelegramWebChat()));
        } else if (feat.title == 'NEXUS AI') {
          // Switch to AI tab — handled by nav
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('${feat.title} — переключитесь на вкладку AI')),
          );
        } else if (feat.title == 'Заметки') {
          _showNotesSheet();
        } else if (feat.title == 'Контакты') {
          _showContactsSheet();
        } else if (feat.title == 'Голосовые сообщения') {
          _showVoiceSheet();
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('${feat.title} — в разработке')),
          );
        }
      },
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

  void _showNotesSheet() {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Заметки', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
            Container(
              height: 200,
              decoration: BoxDecoration(
                color: Colors.grey.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const TextField(
                maxLines: 10,
                decoration: InputDecoration(
                  hintText: 'Напишите заметку...',
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.all(16),
                ),
              ),
            ),
            const SizedBox(height: 16),
            FilledButton(child: const Text('Сохранить'), onPressed: () => Navigator.pop(ctx)),
          ],
        ),
      ),
    );
  }

  void _showContactsSheet() {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Контакты', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
            const ListTile(leading: CircleAvatar(child: Icon(Icons.person)), title: Text('Контакты из телефона'), subtitle: Text('Синхронизация не настроена')),
          ],
        ),
      ),
    );
  }

  void _showVoiceSheet() {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Голосовые сообщения'),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(32),
              decoration: BoxDecoration(
                color: const Color(0xFF6C63FF).withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.mic, size: 48, color: Color(0xFF6C63FF)),
            ),
            const SizedBox(height: 16),
            Text('Нажмите для записи', style: TextStyle(color: Colors.grey[500])),
          ],
        ),
      ),
    );
  }
}

class _NexusFeature {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  _NexusFeature(this.icon, this.title, this.subtitle, this.color);
}
