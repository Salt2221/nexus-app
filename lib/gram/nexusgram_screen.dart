// ═══════════════════════════════════════════════════════════════
// NEXUSGram — Фейковый Telegram-клиент
//
// Встроенный WebView Telegram (web.telegram.org) не работает через
// локальный MTProto/SOCKS5, поэтому это просто экран-заглушка с:
//   - Заголовком "NexusGram"
//   - Кнопкой "Open Telegram" → открывает в настоящем приложении
//   - Кнопкой "Open Web" → обычный браузер
//   - Визуальным интерфейсом, похожим на Telegram
// ═══════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class NexusGramScreen extends StatefulWidget {
  const NexusGramScreen({super.key});

  @override
  State<NexusGramScreen> createState() => _NexusGramScreenState();
}

class _NexusGramScreenState extends State<NexusGramScreen> {
  // Вся "история" — фейковая, для атмосферы
  final _chats = [
    _ChatPreview('Антон', 'Привет, как дела?', DateTime.now().subtract(const Duration(minutes: 3))),
    _ChatPreview('Семья', 'Мама: Ужин готов 🍕', DateTime.now().subtract(const Duration(minutes: 15))),
    _ChatPreview('Работа', 'Пуш: созвон в 15:00', DateTime.now().subtract(const Duration(hours: 1))),
    _ChatPreview('Канал DEV', 'Nexus v2 вышел! 🚀', DateTime.now().subtract(const Duration(hours: 2))),
    _ChatPreview('Алиса', 'Скинь фото 🙈', DateTime.now().subtract(const Duration(hours: 3))),
  ];

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF0D1117) : const Color(0xFFF0F2F5);
    final cardBg = isDark ? const Color(0xFF161B22) : Colors.white;

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        title: const Row(
          children: [
            Icon(Icons.send, size: 20, color: Colors.white),
            SizedBox(width: 8),
            Text(
              'NexusGram',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 18,
                color: Colors.white,
              ),
            ),
          ],
        ),
        backgroundColor: const Color(0xFF0088CC),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.search, color: Colors.white),
            onPressed: () {},
          ),
          IconButton(
            icon: const Icon(Icons.more_vert, color: Colors.white),
            onPressed: () {},
          ),
        ],
      ),
      body: Column(
        children: [
          // ═══ Баннер: как открыть настоящий Telegram ═══
          Container(
            padding: const EdgeInsets.all(12),
            color: isDark ? Colors.grey[900] : Colors.blue[50],
            child: Column(
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0088CC).withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.info_outline, color: Color(0xFF0088CC), size: 18),
                    ),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        'Веб-версия Telegram не работает через VPN/MTProto.\n'
                        'Открой приложение Telegram или браузер.',
                        style: TextStyle(fontSize: 12, height: 1.4),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _OpenButton(
                        icon: Icons.open_in_new,
                        label: 'Open Telegram',
                        color: const Color(0xFF0088CC),
                        onTap: () async {
                          // Попытка открыть реальное приложение Telegram
                          try {
                            // Пробуем tg:// — откроет приложение если установлено
                            await _launchUrl('tg://resolve?domain=telegram');
                          } catch (_) {
                            // Если не сработало — показываем сообщение
                            _showOpenGuide(context);
                          }
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _OpenButton(
                        icon: Icons.language,
                        label: 'Web Version',
                        color: Colors.grey,
                        onTap: () async {
                          await _launchUrl('https://web.telegram.org/k/');
                        },
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // ═══ Фейковый список чатов ═══
          Expanded(
            child: ListView.builder(
              itemCount: _chats.length,
              itemBuilder: (_, i) => _buildChatItem(_chats[i], isDark, cardBg),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChatItem(_ChatPreview chat, bool isDark, Color cardBg) {
    final avatarColors = [
      Colors.red, Colors.blue, Colors.green, Colors.purple, Colors.orange,
    ];
    final avatarColor = avatarColors[chat.title.hashCode.abs() % avatarColors.length];

    return Container(
      decoration: BoxDecoration(
        color: cardBg,
        border: Border(
          bottom: BorderSide(color: isDark ? const Color(0xFF30363D) : Colors.grey[200]!, width: 0.5),
        ),
      ),
      child: ListTile(
        leading: CircleAvatar(
          radius: 24,
          backgroundColor: avatarColor,
          child: Text(
            chat.title[0].toUpperCase(),
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
          ),
        ),
        title: Text(
          chat.title,
          style: TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 15,
            color: isDark ? Colors.white : Colors.black87,
          ),
        ),
        subtitle: Text(
          chat.lastMessage,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 13, color: Colors.grey[500]),
        ),
        trailing: Text(
          _formatTime(chat.time),
          style: TextStyle(fontSize: 11, color: Colors.grey[500]),
        ),
        onTap: () {
          // Просто открываем настоящий Telegram
          _launchUrl('tg://resolve?domain=telegram');
        },
      ),
    );
  }

  String _formatTime(DateTime dt) {
    final now = DateTime.now();
    if (dt.day == now.day) {
      return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    }
    return '${dt.day}.${dt.month.toString().padLeft(2, '0')}';
  }

  Future<void> _launchUrl(String url) async {
    try {
      final uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        _showOpenGuide(context);
      }
    } catch (e) {
      _showOpenGuide(context);
    }
  }

  void _showOpenGuide(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Открыть Telegram'),
        content: const Text(
          'Для использования Telegram через NEXUS:\n\n'
          '1. Установи приложение Telegram\n'
          '2. Настрой прокси: Настройки → Данные → Использование прокси\n'
          '3. Укажи SOCKS5: 127.0.0.1:${_socks5Port}\n'
          'Или MTProto: скопируй ссылку из раздела "Защита"',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Понятно'),
          ),
        ],
      ),
    );
  }

  int get _socks5Port => 1443;

  @override
  void dispose() {
    super.dispose();
  }
}

// ═══ Data ═══

class _ChatPreview {
  final String title;
  final String lastMessage;
  final DateTime time;
  const _ChatPreview(this.title, this.lastMessage, this.time);
}

// ═══ Кнопка ═══

class _OpenButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _OpenButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
