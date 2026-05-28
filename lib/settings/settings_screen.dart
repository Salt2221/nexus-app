import 'package:flutter/material.dart';
import 'customization_screen.dart';
import '../services/customization_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _notifications = true;
  bool _autoBrowser = true;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF0D1117) : const Color(0xFFF0F2F5);
    final cardColor = isDark ? const Color(0xFF161B22) : Colors.white;
    final titleColor = isDark ? Colors.white : Colors.black87;
    final subtitleColor = isDark ? Colors.grey[500] : Colors.grey[600];

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        title: const Text('Настройки', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF6C63FF),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSection('ОФОРМЛЕНИЕ', isDark),
            const SizedBox(height: 8),
            _buildNavCard(
              icon: Icons.palette,
              title: 'Тема & Кастомизация',
              subtitle: 'Акцентный цвет, фон чатов, шрифт, анимации',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const CustomizationScreen()),
              ),
              isDark: isDark, cardColor: cardColor, titleColor: titleColor, subtitleColor: subtitleColor,
            ),
            const SizedBox(height: 24),
            _buildSection('УВЕДОМЛЕНИЯ', isDark),
            const SizedBox(height: 8),
            _buildSwitchTile(
              icon: Icons.notifications_outlined,
              title: 'Уведомления',
              subtitle: 'Push-уведомления о новых сообщениях',
              value: _notifications,
              onChanged: (v) => setState(() => _notifications = v),
              isDark: isDark, cardColor: cardColor, titleColor: titleColor, subtitleColor: subtitleColor,
            ),
            const SizedBox(height: 24),
            _buildSection('ССЫЛКИ', isDark),
            const SizedBox(height: 8),
            _buildSwitchTile(
              icon: Icons.open_in_browser,
              title: 'Встроенный браузер',
              subtitle: 'Открывать ссылки внутри приложения',
              value: _autoBrowser,
              onChanged: (v) => setState(() => _autoBrowser = v),
              isDark: isDark, cardColor: cardColor, titleColor: titleColor, subtitleColor: subtitleColor,
            ),
            const SizedBox(height: 24),
            _buildSection('О ПРИЛОЖЕНИИ', isDark),
            const SizedBox(height: 8),
            _buildInfoTile(icon: Icons.info_outline, title: 'Версия', value: '1.0.1', isDark: isDark, cardColor: cardColor, titleColor: titleColor, subtitleColor: subtitleColor),
            _buildInfoTile(icon: Icons.code, title: 'Сборка', value: 'debug arm64', isDark: isDark, cardColor: cardColor, titleColor: titleColor, subtitleColor: subtitleColor),
            _buildInfoTile(icon: Icons.flutter_dash, title: 'Flutter', value: '3.32.0', isDark: isDark, cardColor: cardColor, titleColor: titleColor, subtitleColor: subtitleColor),
            _buildInfoTile(icon: Icons.auto_awesome, title: 'AI', value: 'DeepSeek Chat', isDark: isDark, cardColor: cardColor, titleColor: titleColor, subtitleColor: subtitleColor),
            const SizedBox(height: 32),
            Center(
              child: Text(
                'NEXUS v1.0.1',
                textAlign: TextAlign.center,
                style: TextStyle(color: subtitleColor, fontSize: 12),
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildSection(String title, bool isDark) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 4),
      child: Text(title, style: TextStyle(
        color: const Color(0xFF6C63FF), fontSize: 12,
        fontWeight: FontWeight.bold, letterSpacing: 1.2,
      )),
    );
  }

  Widget _buildNavCard({
    required IconData icon, required String title, required String subtitle,
    required VoidCallback onTap, required bool isDark,
    required Color cardColor, required Color titleColor, Color? subtitleColor,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: cardColor, borderRadius: BorderRadius.circular(16),
          border: Border.all(color: isDark ? const Color(0xFF30363D) : Colors.grey[200]!),
        ),
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 44, height: 44,
              decoration: BoxDecoration(
                color: const Color(0xFF6C63FF).withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: const Color(0xFF6C63FF), size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: TextStyle(color: titleColor, fontWeight: FontWeight.w600, fontSize: 15)),
                  const SizedBox(height: 2),
                  Text(subtitle, style: TextStyle(color: subtitleColor, fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: isDark ? Colors.grey[700] : Colors.grey[400], size: 22),
          ],
        ),
      ),
    );
  }

  Widget _buildSwitchTile({
    required IconData icon, required String title, required String subtitle,
    required bool value, required ValueChanged<bool> onChanged,
    required bool isDark, required Color cardColor,
    required Color titleColor, Color? subtitleColor,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: cardColor, borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isDark ? const Color(0xFF30363D) : Colors.grey[200]!),
      ),
      child: SwitchListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16),
        secondary: Container(
          width: 36, height: 36,
          decoration: BoxDecoration(
            color: const Color(0xFF6C63FF).withOpacity(0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: const Color(0xFF6C63FF), size: 20),
        ),
        title: Text(title, style: TextStyle(color: titleColor, fontWeight: FontWeight.w500)),
        subtitle: Text(subtitle, style: TextStyle(color: subtitleColor, fontSize: 12)),
        value: value, onChanged: onChanged,
        activeColor: const Color(0xFF6C63FF),
      ),
    );
  }

  Widget _buildInfoTile({
    required IconData icon, required String title, required String value,
    required bool isDark, required Color cardColor,
    required Color titleColor, Color? subtitleColor,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: cardColor, borderRadius: BorderRadius.circular(14),
        border: Border.all(color: isDark ? const Color(0xFF30363D) : Colors.grey[200]!),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16),
        leading: Container(
          width: 36, height: 36,
          decoration: BoxDecoration(
            color: const Color(0xFF6C63FF).withOpacity(0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: const Color(0xFF6C63FF), size: 20),
        ),
        title: Text(title, style: TextStyle(color: titleColor)),
        trailing: Text(value, style: TextStyle(color: subtitleColor)),
      ),
    );
  }
}
