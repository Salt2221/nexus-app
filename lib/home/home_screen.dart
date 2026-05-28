import 'package:flutter/material.dart';
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

  List<MeshPeer> get _filteredPeers {
    final query = _searchController.text.toLowerCase().trim();
    if (query.isEmpty) return MeshNetworkManager.instance.peers;
    return MeshNetworkManager.instance.peers.where((p) =>
      p.name.toLowerCase().contains(query)).toList();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF0D1117) : const Color(0xFFF0F2F5);

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
            onPressed: () {
              setState(() {
                _showSearch = !_showSearch;
                if (!_showSearch) _searchController.clear();
              });
            },
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              MeshNetworkManager.instance.init();
              setState(() {});
            },
          ),
        ],
      ),
      body: ListView(
        children: [
          // 🌐 Telegram WebView entry
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Card(
              color: isDark ? const Color(0xFF161B22) : Colors.white,
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
                title: const Text('Telegram', style: TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text('Веб-версия через WebView', style: TextStyle(color: Colors.grey[500], fontSize: 12)),
                trailing: const Icon(Icons.chevron_right, color: Colors.grey),
                onTap: () {
                  Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const TelegramWebChat()));
                },
              ),
            ),
          ),

          // 📡 Mesh устройства
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text(
              'УСТРОЙСТВА РЯДОМ',
              style: TextStyle(
                color: const Color(0xFF6C63FF), fontSize: 12,
                fontWeight: FontWeight.bold, letterSpacing: 1.2,
              ),
            ),
          ),

          if (_filteredPeers.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 32),
              child: Column(
                children: [
                  Icon(Icons.wifi_tethering, size: 64, color: Colors.grey[600]),
                  const SizedBox(height: 12),
                  Text('Устройства не найдены',
                      style: TextStyle(color: Colors.grey[500], fontSize: 16)),
                  const SizedBox(height: 4),
                  Text('Mesh-сеть сканирует устройства рядом',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey[600], fontSize: 12)),
                  const SizedBox(height: 20),
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
            ),

          // Список устройств Mesh
          ..._filteredPeers.map((peer) => Card(
            color: isDark ? const Color(0xFF161B22) : Colors.white,
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: ListTile(
              leading: Stack(
                children: [
                  CircleAvatar(
                    backgroundColor: const Color(0xFF6C63FF),
                    child: Text(peer.name.isNotEmpty ? peer.name[0] : '?',
                        style: const TextStyle(color: Colors.white)),
                  ),
                  if (peer.isOnline)
                    Positioned(
                      bottom: 0, right: 0,
                      child: Container(
                        width: 12, height: 12,
                        decoration: BoxDecoration(
                          color: Colors.green,
                          shape: BoxShape.circle,
                          border: Border.all(color: isDark ? const Color(0xFF161B22) : Colors.white, width: 2),
                        ),
                      ),
                    ),
                ],
              ),
              title: Text(peer.name,
                  style: TextStyle(fontWeight: FontWeight.w600, color: isDark ? Colors.white : Colors.black87)),
              subtitle: Text('Mesh-устройство',
                  style: TextStyle(color: Colors.grey[500], fontSize: 12)),
              trailing: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text('Online',
                    style: TextStyle(color: Colors.green[400], fontSize: 11)),
              ),
              onTap: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Подключение к ${peer.name}...')),
                );
              },
            ),
          )),
        ],
      ),
    );
  }
}
