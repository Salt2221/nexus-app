// ═══════════════════════════════════════════════════════════════
// NEXUS — Главный каркас приложения
//
// Структура:
//   [Главное меню] [Инструменты] [AI]
//
// Главное меню: VPN (1 кнопка), P2P чаты, Профиль, Настройки
// Инструменты: все остальные модули
// AI: Nexus AI чат + обучение модели
// ═══════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';

import 'home/home_screen.dart';
import 'services/menu_service.dart';
import 'vpn/ai_screen.dart';
import 'services/dht_network.dart';
import 'services/global_p2p_node.dart';
import 'services/model_train_service.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _currentIndex = 0;

  final _pages = <Widget>[
    const HomeScreen(),       // Главное меню
    const ToolsScreen(),      // Инструменты
    const NexusAiScreen(),    // AI
  ];

  @override
  void initState() {
    super.initState();
    _initAutoServices();
  }

  /// Запуск фоновых служб (P2P, обучение)
  void _initAutoServices() async {
    // DHT / P2P — автостарт, нельзя отключить
    try {
      final dht = DhtNetworkManager.instance;
      if (!dht.initialized) await dht.init();
    } catch (_) {}

    // Обучение нейросети — автостарт в фоне
    try {
      final train = ModelTrainService.instance;
      if (!train.running) await train.startBackground();
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF0D1117) : const Color(0xFFF5F5F5);
    final cardBg = isDark ? const Color(0xFF161B22) : Colors.white;

    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: _pages,
      ),
      bottomNavigationBar: _NexusBottomBar(
        currentIndex: _currentIndex,
        onTap: (i) => setState(() => _currentIndex = i),
      ),
    );
  }
}

/// Кастомный нижний бар NEXUS
class _NexusBottomBar extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;

  const _NexusBottomBar({required this.currentIndex, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF161B22) : Colors.white,
        border: Border(
          top: BorderSide(
            color: isDark ? const Color(0xFF30363D) : Colors.grey[200]!,
          ),
        ),
      ),
      child: SafeArea(
        child: Row(
          children: [
            _BarItem(
              icon: Icons.home,
              label: 'Главное',
              isActive: currentIndex == 0,
              isDark: isDark,
              onTap: () => onTap(0),
            ),
            _BarItem(
              icon: Icons.build,
              label: 'Инструменты',
              isActive: currentIndex == 1,
              isDark: isDark,
              onTap: () => onTap(1),
            ),
            _BarItem(
              icon: Icons.auto_awesome,
              label: 'AI',
              isActive: currentIndex == 2,
              isDark: isDark,
              onTap: () => onTap(2),
            ),
          ],
        ),
      ),
    );
  }
}

class _BarItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isActive;
  final bool isDark;
  final VoidCallback onTap;

  const _BarItem({required this.icon, required this.label, required this.isActive, required this.isDark, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: isActive ? Colors.amber : Colors.grey, size: 28),
              SizedBox(height: 2),
              Text(label,
                style: TextStyle(
                  fontSize: 11,
                  color: isActive ? Colors.amber : Colors.grey,
                  fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
