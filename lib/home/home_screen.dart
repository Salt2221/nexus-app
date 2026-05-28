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
  int _chatMode = 0; // 0 = Mesh, 1 = Telegram
  bool _meshReady = false;

  @override
  void initState() {
    super.initState();
    // Слушаем Mesh-сеть
    MeshNetworkManager.instance.addListener(_onMeshUpdate);
    _meshReady = MeshNetworkManager.instance.peers.isNotEmpty;
  }

  @override
  void dispose() {
    MeshNetworkManager.instance.removeListener(_onMeshUpdate);
    _searchController.dispose();
    super.dispose();
  }

  void _onMeshUpdate() {
    if (mounted) {
      setState(() {
        _meshReady = MeshNetworkManager.instance.peers.isNotEmpty;
      });
    }
  }

  List<MeshPeer> get _filteredPeers {
    final query = _searchController.text.toLowerCase().trim();
    if (query.isEmpty) return MeshNetworkManager.instance.peers;
    return MeshNetworkManager.instance.peers.where((p) =>
      p.name.toLowerCase().contains(query)
    ).toList();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF0D1117) : const Color(0xFFF0F2F5);

    if (_chatMode == 1) {
      return const TelegramWebChat();
    }

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
            : const Text('Mesh', style: TextStyle(fontWeight: FontWeight.bold)),
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
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() => _chatMode = 0),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        decoration: BoxDecoration(
                          color: _chatMode == 0 ? Colors.white.withOpacity(0.25) : Colors.transparent,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.hub, size: 16, color: Colors.white),
                            SizedBox(width: 6),
                            Text('Mesh', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() => _chatMode = 1),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        decoration: BoxDecoration(
                          color: _chatMode == 1 ? Colors.white.withOpacity(0.25) : Colors.transparent,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.send, size: 16, color: Colors.white),
                            SizedBox(width: 6),
                            Text('Telegram', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
      body: _filteredPeers.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.wifi_tethering, size: 72, color: Colors.grey[600]),
                  const SizedBox(height: 16),
                  Text('Устройства не найдены', style: TextStyle(color: Colors.grey[500], fontSize: 18)),
                  const SizedBox(height: 8),
                  Text('Убедитесь, что устройства\nрядом и Mesh включён',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey[600], fontSize: 13)),
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    onPressed: () {
                      MeshNetworkManager.instance.init();
                      setState(() {});
                    },
                    icon: const Icon(Icons.search),
                    label: const Text('Поиск устройств'),
                  ),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(8),
              itemCount: _filteredPeers.length,
              itemBuilder: (context, i) {
                final peer = _filteredPeers[i];
                return Card(
                  color: isDark ? const Color(0xFF161B22) : Colors.white,
                  margin: const EdgeInsets.symmetric(vertical: 4),
                  child: ListTile(
                    leading: Stack(
                      children: [
                        CircleAvatar(
                          backgroundColor: const Color(0xFF6C63FF),
                          child: Text(peer.name[0], style: const TextStyle(color: Colors.white)),
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
                    title: Text(peer.name, style: TextStyle(fontWeight: FontWeight.w600, color: isDark ? Colors.white : Colors.black87)),
                    subtitle: Text('Mesh-устройство', style: TextStyle(color: Colors.grey[500], fontSize: 12)),
                    trailing: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.green.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text('Online', style: TextStyle(color: Colors.green[400], fontSize: 11)),
                    ),
                    onTap: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Подключение к ${peer.name}...')),
                      );
                    },
                  ),
                );
              },
            ),
    );
  }
}
