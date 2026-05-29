// ═══════════════════════════════════════════════════════════════
// NEXUS Настройки
//
// - Тема (тёмная/светлая)
// - Размер шрифта (12-24)
// - Скругление UI (4-32)
// - Обновления (проверка + скачивание)
// - О приложении
// ═══════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/customization_service.dart';
import '../services/update_checker.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _custom = CustomizationService.instance;
  final _updater = UpdateChecker.instance;
  String? _lastCheckResult;
  bool _fontSizeChanged = false;
  bool _radiusChanged = false;

  @override
  void initState() {
    super.initState();
    _updater.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _updater.removeListener(() => setState(() {}));
    super.dispose();
  }

  Future<void> _checkUpdates() async {
    final result = await _updater.checkForUpdate();
    if (mounted) {
      setState(() {
        if (result != null) {
          _lastCheckResult = 'Доступна версия ${result.versionName} (${result.formattedSize})';
        } else if (_updater.error != null) {
          _lastCheckResult = 'Ошибка: ${_updater.error}';
        } else {
          _lastCheckResult = 'У вас актуальная версия';
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = _custom.darkMode;
    final bg = isDark ? const Color(0xFF0D1117) : const Color(0xFFF5F5F5);
    final cardBg = isDark ? const Color(0xFF161B22) : Colors.white;
    final textColor = isDark ? Colors.white : Colors.black87;
    final subColor = isDark ? Colors.grey[500]! : Colors.grey[600]!;

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        title: Text('Настройки', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: cardBg,
        elevation: 0,
      ),
      body: ListView(
        padding: EdgeInsets.all(16),
        children: [
          // ═══ ВНЕШНИЙ ВИД ═══
          _SectionHeader(title: 'Внешний вид', isDark: isDark),

          Card(
            color: cardBg,
            child: Column(
              children: [
                SwitchListTile(
                  title: Text('Тёмная тема', style: TextStyle(color: textColor)),
                  subtitle: Text('Переключить оформление', style: TextStyle(color: subColor, fontSize: 12)),
                  value: _custom.darkMode,
                  activeColor: Colors.amber,
                  onChanged: (v) {
                    _custom.darkMode = v;
                    setState(() {});
                    _custom.notifyListeners();
                  },
                ),
                Divider(height: 1),

                // Размер шрифта
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(
                    children: [
                      Icon(Icons.text_fields, color: subColor, size: 20),
                      SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Размер шрифта', style: TextStyle(color: textColor)),
                            Text('${(_custom.messageFontSize).toInt()} pt', style: TextStyle(color: subColor, fontSize: 12)),
                          ],
                        ),
                      ),
                      SizedBox(
                        width: 120,
                        child: Slider(
                          value: _custom.messageFontSize,
                          min: 12,
                          max: 24,
                          divisions: 12,
                          activeColor: Colors.amber,
                          onChanged: (v) {
                            _custom.messageFontSize = v;
                            _fontSizeChanged = true;
                            setState(() {});
                          },
                          onChangeEnd: (v) {
                            if (_fontSizeChanged) {
                              _custom.notifyListeners();
                              _fontSizeChanged = false;
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                ),
                Divider(height: 1),

                // Скругление
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(
                    children: [
                      Icon(Icons.rounded_corner, color: subColor, size: 20),
                      SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Скругление UI', style: TextStyle(color: textColor)),
                            Text('${(_custom.cornerRadius).toInt()} px', style: TextStyle(color: subColor, fontSize: 12)),
                          ],
                        ),
                      ),
                      SizedBox(
                        width: 120,
                        child: Slider(
                          value: _custom.cornerRadius,
                          min: 4,
                          max: 32,
                          divisions: 14,
                          activeColor: Colors.amber,
                          onChanged: (v) {
                            _custom.cornerRadius = v;
                            _radiusChanged = true;
                            setState(() {});
                          },
                          onChangeEnd: (v) {
                            if (_radiusChanged) {
                              _custom.notifyListeners();
                              _radiusChanged = false;
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          SizedBox(height: 16),

          // ═══ ОБНОВЛЕНИЯ ═══
          _SectionHeader(title: 'Обновления', isDark: isDark),

          Card(
            color: cardBg,
            child: Column(
              children: [
                ListTile(
                  leading: Icon(_updater.hasUpdate ? Icons.system_update : Icons.check_circle,
                    color: _updater.hasUpdate ? Colors.amber : Colors.green),
                  title: Text('Версия ${_updater.currentVersionName ?? '0.0.0'}', style: TextStyle(color: textColor)),
                  subtitle: Text(
                    _updater.statusMessage ?? (_updater.hasUpdate ? 'Доступно обновление' : 'Актуальная версия'),
                    style: TextStyle(color: subColor, fontSize: 12),
                  ),
                  trailing: _updater.downloading
                      ? SizedBox(
                          width: 24, height: 24,
                          child: CircularProgressIndicator(strokeWidth: 2, value: _updater.downloadProgress),
                        )
                      : (_updater.hasUpdate
                          ? ElevatedButton(
                              onPressed: () => _updater.downloadUpdate(),
                              child: Text('Скачать'),
                            )
                          : null),
                ),
                if (_updater.downloading)
                  Padding(
                    padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: Row(
                      children: [
                        Expanded(child: LinearProgressIndicator(value: _updater.downloadProgress)),
                        SizedBox(width: 8),
                        Text('${(_updater.downloadProgress * 100).toStringAsFixed(0)}%', style: TextStyle(fontSize: 11, color: subColor)),
                      ],
                    ),
                  ),
                if (_lastCheckResult != null && !_updater.hasUpdate)
                  Padding(
                    padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: Text(_lastCheckResult!, style: TextStyle(fontSize: 12, color: subColor)),
                  ),
                Divider(height: 1),
                InkWell(
                  onTap: _checkUpdates,
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (_updater.checking)
                          SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                        if (_updater.checking) SizedBox(width: 8),
                        Icon(Icons.refresh, size: 16, color: Colors.amber),
                        SizedBox(width: 8),
                        Text(_updater.checking ? 'Проверка...' : 'Проверить обновления',
                          style: TextStyle(color: Colors.amber, fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          SizedBox(height: 16),

          // ═══ О ПРИЛОЖЕНИИ ═══
          _SectionHeader(title: 'О приложении', isDark: isDark),

          Card(
            color: cardBg,
            child: Column(
              children: [
                ListTile(
                  leading: Icon(Icons.info_outline, color: Colors.blue),
                  title: Text('NEXUS', style: TextStyle(color: textColor)),
                  subtitle: Text('v${_updater.currentVersionName ?? '0.0.0'}', style: TextStyle(color: subColor, fontSize: 12)),
                ),
                ListTile(
                  leading: Icon(Icons.developer_mode, color: Colors.teal),
                  title: Text('Разработчик', style: TextStyle(color: textColor)),
                  subtitle: Text('Salt2221', style: TextStyle(color: subColor, fontSize: 12)),
                ),
                ListTile(
                  leading: Icon(Icons.code, color: Colors.amber),
                  title: Text('GitHub', style: TextStyle(color: textColor)),
                  subtitle: Text('github.com/Salt2221/nexus-app', style: TextStyle(color: subColor, fontSize: 12)),
                ),
              ],
            ),
          ),

          SizedBox(height: 32),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final bool isDark;

  const _SectionHeader({required this.title, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: 8, left: 4),
      child: Text(title,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.bold,
          color: isDark ? Colors.grey[400] : Colors.grey[700],
        ),
      ),
    );
  }
}
