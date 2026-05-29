// ═══════════════════════════════════════════════════════════════
// NEXUS Инструменты — все дополнительные модули
//
// Здесь: Заметки, SDR, Edge Storage, Volunteer Compute,
//        Погода, Переводчик, Пароли, QR, Таймер, Курсы,
//        HR Ассистент, DHT Настройки
// ═══════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';

class ToolsScreen extends StatelessWidget {
  const ToolsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF0D1117) : const Color(0xFFF5F5F5);

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        title: Text('Инструменты'),
        backgroundColor: isDark ? const Color(0xFF161B22) : Colors.white,
        elevation: 0,
      ),
      body: Padding(
        padding: EdgeInsets.all(12),
        child: GridView.builder(
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
            childAspectRatio: 0.9,
          ),
          itemCount: _tools.length,
          itemBuilder: (_, i) => _ToolCard(tool: _tools[i], isDark: isDark, onTap: _tools[i].onTap),
        ),
      ),
    );
  }
}

class _Tool {
  final IconData icon;
  final String name;
  final Color color;
  final VoidCallback? onTap;
  const _Tool({required this.icon, required this.name, required this.color, this.onTap});
}

final _tools = [
  _Tool(icon: Icons.edit_note, name: 'Заметки', color: Colors.amber, onTap: null),
  _Tool(icon: Icons.radio, name: 'SDR', color: Colors.teal, onTap: null),
  _Tool(icon: Icons.cloud, name: 'Edge Storage', color: Colors.purple, onTap: null),
  _Tool(icon: Icons.memory, name: 'Compute', color: Colors.indigo, onTap: null),
  _Tool(icon: Icons.wb_sunny, name: 'Погода', color: Colors.cyan, onTap: null),
  _Tool(icon: Icons.translate, name: 'Переводчик', color: Colors.teal, onTap: null),
  _Tool(icon: Icons.password, name: 'Пароли', color: Colors.pink, onTap: null),
  _Tool(icon: Icons.qr_code, name: 'QR-коды', color: Colors.indigo, onTap: null),
  _Tool(icon: Icons.timer, name: 'Таймер', color: Colors.orange, onTap: null),
  _Tool(icon: Icons.monetization_on, name: 'Курсы валют', color: Colors.green, onTap: null),
  _Tool(icon: Icons.record_voice_over, name: 'HR Ассистент', color: Colors.deepPurple, onTap: null),
  _Tool(icon: Icons.settings_ethernet, name: 'DHT Настройки', color: Colors.brown, onTap: null),
];

class _ToolCard extends StatelessWidget {
  final _Tool tool;
  final bool isDark;
  final VoidCallback? onTap;

  const _ToolCard({required this.tool, required this.isDark, this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF161B22) : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: isDark ? const Color(0xFF30363D) : Colors.grey[200]!),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(tool.icon, color: tool.color, size: 32),
            SizedBox(height: 6),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 4),
              child: Text(tool.name,
                style: TextStyle(fontSize: 11, color: isDark ? Colors.white : Colors.black87),
                textAlign: TextAlign.center,
                maxLines: 2, overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
