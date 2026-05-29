import 'package:flutter/material.dart';
import '../services/customization_service.dart';

class CustomizationScreen extends StatefulWidget {
  const CustomizationScreen({super.key});

  @override
  State<CustomizationScreen> createState() => _CustomizationScreenState();
}

class _CustomizationScreenState extends State<CustomizationScreen> {
  final _service = CustomizationService.instance;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF0D1117) : const Color(0xFFF0F2F5);
    final cardColor = isDark ? const Color(0xFF161B22) : Colors.white;

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        title: const Text('Тема и кастомизация',
            style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF6C63FF),
        foregroundColor: Colors.white,
      ),
      body: ListenableBuilder(
        listenable: _service,
        builder: (context, _) => SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _section('ТЕМА'),
              _card(cardColor, isDark, Column(
                children: [
                  _switchTile(Icons.brightness_6, 'Тёмная тема',
                      _service.darkMode, (v) => _service.setDarkMode(v)),
                  const Divider(height: 1),
                  _switchTile(Icons.hearing_disabled, 'Уменьшить анимации',
                      _service.reducedMotion, (v) => _service.setReducedMotion(v)),
                ],
              )),
              const SizedBox(height: 24),

              _section('АКЦЕНТНЫЙ ЦВЕТ'),
              _card(cardColor, isDark, _buildColorPicker()),
              const SizedBox(height: 24),

              _section('ЧАТ'),
              _card(cardColor, isDark, Column(
                children: [
                  _sliderTile(Icons.text_fields, 'Размер шрифта',
                      _service.messageFontSize, 12, 24, (v) => _service.setMessageFontSize(v)),
                  const Divider(height: 1),
                  _sliderTile(Icons.rounded_corner, 'Скругление',
                      _service.cornerRadius, 4, 32, (v) => _service.setCornerRadius(v)),
                  const Divider(height: 1),
                  _switchTile(Icons.face, 'Аватарки',
                      _service.showAvatars, (v) => _service.setShowAvatars(v)),
                  const Divider(height: 1),
                  _switchTile(Icons.badge, 'Имена',
                      _service.showNames, (v) => _service.setShowNames(v)),
                  const Divider(height: 1),
                  _switchTile(Icons.access_time, 'Время',
                      _service.showTimestamps, (v) => _service.setShowTimestamps(v)),
                ],
              )),
              const SizedBox(height: 24),

              _section('НАВИГАЦИЯ'),
              _card(cardColor, isDark, Column(
                children: [
                  _switchTile(Icons.density_small, 'Компактная навигация',
                      _service.compactNav, (v) => _service.setCompactNav(v)),
                ],
              )),
              const SizedBox(height: 24),

              _section('ЗВУКИ'),
              _card(cardColor, isDark, Column(
                children: [
                  _switchTile(Icons.volume_up, 'Звуки уведомлений',
                      _service.notificationSounds, (v) => _service.setNotificationSounds(v)),
                  const Divider(height: 1),
                  _switchTile(Icons.vibration, 'Вибрация',
                      _service.vibration, (v) => _service.setVibration(v)),
                ],
              )),
              const SizedBox(height: 24),

              _section('ПРИВАТНОСТЬ'),
              _card(cardColor, isDark, Column(
                children: [
                  _switchTile(Icons.lock, 'Блокировка экрана',
                      _service.appLock, (v) => _service.setAppLock(v)),
                  const Divider(height: 1),
                  _switchTile(Icons.visibility_off, 'Скрыть предпросмотр',
                      _service.hidePreview, (v) => _service.setHidePreview(v)),
                ],
              )),
              const SizedBox(height: 24),

              _section('ЯЗЫК'),
              _card(cardColor, isDark, _buildLangSelector()),
              const SizedBox(height: 32),

              Center(
                child: TextButton.icon(
                  onPressed: () {
                    showDialog(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text('Сбросить настройки'),
                        content: const Text('Все настройки вернутся к стандартным.'),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(ctx),
                              child: const Text('Отмена')),
                          FilledButton(onPressed: () {
                            _service.resetAll();
                            Navigator.pop(ctx);
                          }, child: const Text('Сбросить')),
                        ],
                      ),
                    );
                  },
                  icon: const Icon(Icons.restore),
                  label: const Text('Сбросить настройки'),
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  Widget _section(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(title, style: const TextStyle(
        color: Color(0xFF6C63FF), fontSize: 12,
        fontWeight: FontWeight.bold, letterSpacing: 1.2,
      )),
    );
  }

  Widget _card(Color cardColor, bool isDark, Widget child) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: isDark ? const Color(0xFF30363D) : Colors.grey[200]!),
      ),
      child: child,
    );
  }

  Widget _switchTile(IconData icon, String title, bool value,
      ValueChanged<bool> onChanged) {
    return SwitchListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      secondary: Icon(icon, color: const Color(0xFF6C63FF), size: 20),
      title: Text(title, style: const TextStyle(fontSize: 14)),
      value: value,
      onChanged: onChanged,
      activeColor: const Color(0xFF6C63FF),
    );
  }

  Widget _sliderTile(IconData icon, String label, double value,
      double min, double max, ValueChanged<double> onChanged) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Row(
        children: [
          Icon(icon, color: const Color(0xFF6C63FF), size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(fontSize: 14)),
                Slider(value: value, min: min, max: max,
                    divisions: 28, onChanged: onChanged),
              ],
            ),
          ),
          Text('${value.toInt()}',
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildColorPicker() {
    const colors = [
      Color(0xFF6C63FF), // фиолетовый
      Color(0xFF2196F3), // синий
      Color(0xFF4CAF50), // зелёный
      Color(0xFFFF9800), // оранжевый
      Color(0xFFF44336), // красный
      Color(0xFFE91E63), // розовый
      Color(0xFF9C27B0), // глубокий фиолетовый
      Color(0xFF00BCD4), // циан
      Color(0xFF607D8B), // сине-серый
      Color(0xFF795548), // коричневый
    ];

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Wrap(
        spacing: 12,
        runSpacing: 12,
        children: colors.map((c) => GestureDetector(
          onTap: () => _service.setPrimaryColor(c),
          child: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: c,
              shape: BoxShape.circle,
              border: _service.primaryColor == c
                  ? Border.all(color: Colors.white, width: 3)
                  : null,
              boxShadow: _service.primaryColor == c
                  ? [BoxShadow(color: c.withValues(alpha: 0.5), blurRadius: 8)]
                  : null,
            ),
            child: _service.primaryColor == c
                ? const Icon(Icons.check, color: Colors.white, size: 20)
                : null,
          ),
        )).toList(),
      ),
    );
  }

  Widget _buildLangSelector() {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Wrap(
        spacing: 8,
        children: [
          _langChip('🇷🇺 Русский', 'ru', _service.language),
          _langChip('🇺🇸 English', 'en', _service.language),
          _langChip('🇪🇸 Español', 'es', _service.language),
          _langChip('🇩🇪 Deutsch', 'de', _service.language),
        ],
      ),
    );
  }

  Widget _langChip(String label, String code, String current) {
    final sel = current == code;
    return ChoiceChip(
      label: Text(label, style: const TextStyle(fontSize: 13)),
      selected: sel,
      selectedColor: const Color(0xFF6C63FF).withValues(alpha: 0.2),
      onSelected: (v) {
        if (v) _service.setLanguage(code);
      },
    );
  }
}
