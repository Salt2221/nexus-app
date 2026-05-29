import 'package:flutter/material.dart';
import 'customization_screen.dart';
import '../services/customization_service.dart';
import '../services/update_checker.dart' show UpdateChecker, UpdateInfo, currentVersionName;
import '../services/auth_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _notifications = true;
  bool _autoBrowser = true;
  bool _checkingUpdate = false;
  String? _updateError;
  bool _updateFound = false;

  @override
  void initState() {
    super.initState();
    UpdateChecker.instance.addListener(_onUpdateState);
  }

  @override
  void dispose() {
    UpdateChecker.instance.removeListener(_onUpdateState);
    super.dispose();
  }

  void _onUpdateState() {
    if (mounted) setState(() {
      _checkingUpdate = UpdateChecker.instance.checking;
      _updateError = UpdateChecker.instance.error;
      _updateFound = UpdateChecker.instance.hasUpdate;
    });
  }

  Future<void> _checkForUpdate() async {
    setState(() => _checkingUpdate = true);
    final update = await UpdateChecker.instance.checkForUpdate();
    if (mounted) {
      setState(() {
        _checkingUpdate = false;
        _updateFound = update != null;
      });
      if (update != null) {
        _showUpdateDialog(update);
      } else if (UpdateChecker.instance.error != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(UpdateChecker.instance.error!), backgroundColor: Colors.red[700]),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('У вас актуальная версия'), backgroundColor: Colors.green),
        );
      }
    }
  }

  void _showUpdateDialog(UpdateInfo update) {
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final uc = UpdateChecker.instance;
          return AlertDialog(
            title: const Text('Доступно обновление'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (uc.syncing) ...[
                  const Text('Обновление...', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  LinearProgressIndicator(value: uc.syncProgress > 0 ? uc.syncProgress : null),
                  const SizedBox(height: 8),
                  Text(uc.statusMessage ?? '', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                ] else ...[
                  Row(
                    children: [
                      const Text('Версия: ', style: TextStyle(fontWeight: FontWeight.bold)),
                      Text(update.versionName, style: const TextStyle(color: Color(0xFF6C63FF))),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (update.changelog.isNotEmpty) ...[
                    const Text('Что нового:', style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Text(update.changelog, style: const TextStyle(fontSize: 13)),
                  ],
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF6C63FF).withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.sync, size: 16, color: Color(0xFF6C63FF)),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Обновление синхронизирует настройки, прокси и фичи приложения',
                            style: TextStyle(fontSize: 11, color: Color(0xFF6C63FF)),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
            actions: [
              if (!uc.syncing)
                TextButton(
                  onPressed: () {
                    uc.clear();
                    Navigator.pop(ctx);
                  },
                  child: const Text('Позже'),
                ),
              if (!uc.syncing)
                FilledButton.icon(
                  onPressed: () async {
                    setDialogState(() {});
                    await uc.applyUpdate();
                    if (ctx.mounted) {
                      setDialogState(() {});
                    }
                    if (uc.statusMessage == 'Приложение обновлено') {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Конфигурация обновлена!'), backgroundColor: Colors.green),
                      );
                    }
                  },
                  icon: const Icon(Icons.sync, size: 18),
                  label: const Text('Обновить'),
                ),
              if (uc.syncing && uc.syncProgress >= 1.0)
                FilledButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Готово'),
                ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF0D1117) : const Color(0xFFF0F2F5);
    final cardColor = isDark ? const Color(0xFF161B22) : Colors.white;
    final titleColor = isDark ? Colors.white : Colors.black87;
    final subtitleColor = isDark ? Colors.grey[500] : Colors.grey[600];
    final userName = NexusAuthService.instance.userName ?? 'Пользователь';

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        title: const Text('Профиль', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF6C63FF),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Profile card
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: cardColor,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: isDark ? const Color(0xFF30363D) : Colors.grey[200]!),
              ),
              child: Column(
                children: [
                  CircleAvatar(
                    radius: 40,
                    backgroundColor: const Color(0xFF6C63FF),
                    child: Text(
                      userName[0].toUpperCase(),
                      style: const TextStyle(fontSize: 32, color: Colors.white, fontWeight: FontWeight.bold),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(userName,
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: titleColor)),
                  const SizedBox(height: 4),
                  Text('NEXUS пользователь',
                      style: TextStyle(fontSize: 13, color: subtitleColor)),
                  const SizedBox(height: 16),
                  FilledButton.tonalIcon(
                    onPressed: () {
                      NexusAuthService.instance.signOut();
                      setState(() {});
                    },
                    icon: const Icon(Icons.logout, size: 18),
                    label: const Text('Выйти'),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            _buildSection('НАСТРОЙКИ', isDark),
            const SizedBox(height: 8),
            _buildNavCard(
              icon: Icons.palette,
              title: 'Тема и Кастомизация',
              subtitle: 'Акцентный цвет, фон чатов, шрифт, анимации',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const CustomizationScreen()),
              ),
              isDark: isDark, cardColor: cardColor, titleColor: titleColor, subtitleColor: subtitleColor,
            ),
            const SizedBox(height: 8),
            _buildSwitchTile(
              icon: Icons.notifications_outlined,
              title: 'Уведомления',
              subtitle: 'Push-уведомления о новых сообщениях',
              value: _notifications,
              onChanged: (v) => setState(() => _notifications = v),
              isDark: isDark, cardColor: cardColor, titleColor: titleColor, subtitleColor: subtitleColor,
            ),
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

            _buildSection('ОБНОВЛЕНИЯ', isDark),
            const SizedBox(height: 8),
            _buildNavCard(
              icon: Icons.system_update,
              title: 'Поиск обновлений',
              subtitle: _checkingUpdate
                  ? 'Проверка...'
                  : _updateFound
                      ? 'Доступно обновление!'
                      : _updateError ?? 'Нажмите для проверки',
              onTap: _checkForUpdate,
              isDark: isDark, cardColor: cardColor, titleColor: titleColor, subtitleColor: subtitleColor,
            ),

            const SizedBox(height: 24),

            _buildSection('О ПРИЛОЖЕНИИ', isDark),
            const SizedBox(height: 8),
            _buildInfoTile(icon: Icons.info_outline, title: 'Версия', value: currentVersionName, isDark: isDark, cardColor: cardColor, titleColor: titleColor, subtitleColor: subtitleColor),
            _buildInfoTile(icon: Icons.code, title: 'Сборка', value: 'debug arm64', isDark: isDark, cardColor: cardColor, titleColor: titleColor, subtitleColor: subtitleColor),
            _buildInfoTile(icon: Icons.flutter_dash, title: 'Flutter', value: '3.32.0', isDark: isDark, cardColor: cardColor, titleColor: titleColor, subtitleColor: subtitleColor),

            const SizedBox(height: 32),
            Center(
              child: Text('NEXUS v$currentVersionName',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: subtitleColor, fontSize: 12)),
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
                color: const Color(0xFF6C63FF).withValues(alpha: 0.1),
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
            color: const Color(0xFF6C63FF).withValues(alpha: 0.1),
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
            color: const Color(0xFF6C63FF).withValues(alpha: 0.1),
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
