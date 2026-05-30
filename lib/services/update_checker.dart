// ═══════════════════════════════════════════════════════════════
// NEXUS Auto Updater — загрузка APK с GitHub Releases
//
// - Проверка новой версии через GitHub API
// - Загрузка APK из release assets
// - Установка через Intent (SAF или открытие apk)
// - Отслеживание прогресса скачивания
// ═══════════════════════════════════════════════════════════════

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String _repoOwner = 'Salt2221';
const String _repoName = 'nexus-app';

class UpdateInfo {
  final String versionName;
  final int versionCode;
  final String changelog;
  final String apkUrl;
  final int apkSize;

  UpdateInfo({
    required this.versionName,
    required this.versionCode,
    required this.changelog,
    required this.apkUrl,
    required this.apkSize,
  });

  String get formattedSize {
    if (apkSize < 1024 * 1024) return '${(apkSize / 1024).toStringAsFixed(0)} KB';
    return '${(apkSize / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  factory UpdateInfo.fromJson(Map<String, dynamic> json) {
    return UpdateInfo(
      versionName: json['tag_name'] as String? ?? 'v0.0.0',
      versionCode: json['version_code'] as int? ?? 0,
      changelog: json['body'] as String? ?? '',
      apkUrl: json['apk_url'] as String? ?? '',
      apkSize: json['apk_size'] as int? ?? 0,
    );
  }
}

class UpdateChecker extends ChangeNotifier {
  UpdateChecker._();
  static final UpdateChecker instance = UpdateChecker._();

  bool _checking = false;
  bool _downloading = false;
  double _downloadProgress = 0;
  String _downloadSpeed = '';
  UpdateInfo? _availableUpdate;
  String? _error;
  String? _statusMessage;

  bool get checking => _checking;
  bool get downloading => _downloading;
  double get downloadProgress => _downloadProgress;
  String get downloadSpeed => _downloadSpeed;
  UpdateInfo? get availableUpdate => _availableUpdate;
  String? get error => _error;
  String? get statusMessage => _statusMessage;
  bool get hasUpdate => _availableUpdate != null;

  // Текущая версия приложения
  String get currentVersionName {
    try {
      // Совет: при релизе обновляется вручную
      return '1.0.9';
    } catch (_) { return '0.0.0'; }
  }

  int get currentVersionCode {
    try {
      // v1.0.9 => 10009
      final parts = currentVersionName.split('.');
      return (int.parse(parts[0]) * 10000) +
             (int.parse(parts[1]) * 100) +
             (int.parse(parts[2]));
    } catch (_) { return 0; }
  }

  /// Проверка новой версии через GitHub Releases
  Future<UpdateInfo?> checkForUpdate() async {
    if (_checking) return null;
    _checking = true;
    _error = null;
    _availableUpdate = null;
    _statusMessage = 'Проверка обновлений...';
    notifyListeners();

    try {
      final url = Uri.parse('https://api.github.com/repos/$_repoOwner/$_repoName/releases/latest');
      final res = await http.get(url, headers: {
        'Accept': 'application/vnd.github.v3+json',
        'User-Agent': 'NEXUS/1.0',
      });

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        final tagName = (data['tag_name'] as String?)?.replaceAll(RegExp(r'^v'), '') ?? '0.0.0';
        final body = data['body'] as String? ?? '';

        final tagParts = tagName.split('.').map((s) => int.tryParse(s) ?? 0).toList();
        final tagCode = (tagParts.isNotEmpty ? tagParts[0] : 0) * 10000 +
            (tagParts.isNotEmpty && tagParts.length > 1 ? tagParts[1] : 0) * 100 +
            (tagParts.isNotEmpty && tagParts.length > 2 ? tagParts[2] : 0);

        // Ищем APK в assets
        String apkUrl = '';
        int apkSize = 0;
        final assets = data['assets'] as List? ?? [];
        for (var asset in assets) {
          final name = (asset['name'] as String? ?? '').toLowerCase();
          if (name.endsWith('.apk')) {
            apkUrl = asset['browser_download_url'] as String? ?? '';
            apkSize = asset['size'] as int? ?? 0;
            break;
          }
        }

        // Если нет APK в assets, формируем URL вручную
        if (apkUrl.isEmpty) {
          apkUrl = 'https://github.com/$_repoOwner/$_repoName/releases/download/v$tagName/app-debug.apk';
        }

        _statusMessage = 'Найдена версия v$tagName';
        notifyListeners();

        if (tagCode > currentVersionCode && apkUrl.isNotEmpty) {
          _availableUpdate = UpdateInfo(
            versionName: tagName,
            versionCode: tagCode,
            changelog: body,
            apkUrl: apkUrl,
            apkSize: apkSize,
          );
          _statusMessage = 'Доступно обновление v$tagName';
        } else if (tagCode <= currentVersionCode) {
          _statusMessage = 'У вас актуальная версия';
        } else {
          _statusMessage = 'APK не найден в релизе';
        }
      } else if (res.statusCode == 404) {
        _statusMessage = 'Релизов пока нет';
      } else if (res.statusCode == 403) {
        _error = 'Превышен лимит GitHub API';
        _statusMessage = 'Ошибка: лимит запросов';
      } else {
        _error = 'HTTP ${res.statusCode}';
        _statusMessage = 'Ошибка сервера';
      }
    } catch (e) {
      _error = 'Нет подключения';
      _statusMessage = 'Проверьте интернет';
    }

    _checking = false;
    notifyListeners();
    return _availableUpdate;
  }

  /// Скачивание APK
  Future<bool> downloadUpdate() async {
    if (_downloading || _availableUpdate == null) return false;
    _downloading = true;
    _downloadProgress = 0;
    _statusMessage = 'Скачивание...';
    notifyListeners();

    try {
      final dir = await getApplicationDocumentsDirectory();
      final apkPath = '${dir.path}/nexus_update.apk';
      final file = File(apkPath);

      final url = Uri.parse(_availableUpdate!.apkUrl);
      final request = http.Request('GET', url);

      final streamed = await request.send();
      if (streamed.statusCode != 200) {
        _error = 'HTTP ${streamed.statusCode}';
        _statusMessage = 'Ошибка скачивания';
        _downloading = false;
        notifyListeners();
        return false;
      }

      final totalBytes = streamed.contentLength ?? 1;
      int received = 0;
      final sink = file.openWrite();
      final startTime = DateTime.now();

      await for (var chunk in streamed.stream) {
        sink.add(chunk);
        received += chunk.length;
        _downloadProgress = received / totalBytes;

        // Скорость
        final elapsed = DateTime.now().difference(startTime).inSeconds;
        if (elapsed > 0) {
          final bytesPerSec = received / elapsed;
          _downloadSpeed = bytesPerSec > 1024 * 1024
              ? '${(bytesPerSec / (1024 * 1024)).toStringAsFixed(1)} MB/s'
              : '${(bytesPerSec / 1024).toStringAsFixed(0)} KB/s';
        }

        notifyListeners();
      }

      await sink.flush();
      await sink.close();

      _downloadProgress = 1.0;
      _statusMessage = 'Скачан (${_availableUpdate!.formattedSize})';

      // Запоминаем путь к apk
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('update_apk_path', apkPath);

      _downloading = false;
      notifyListeners();

      // Открываем установщик
      _installApk(apkPath);

      return true;

    } catch (e) {
      _error = 'Ошибка: $e';
      _statusMessage = 'Скачивание прервано';
      _downloading = false;
      notifyListeners();
      return false;
    }
  }

  /// Открыть APK через системный установщик
  void _installApk(String path) {
    try {
      if (Platform.isAndroid) {
        // Используем Intent через MethodChannel
        // Временно — debug info
        debugPrint('[Update] APK готов: $path');
      }
    } catch (e) {
      debugPrint('[Update] Install error: $e');
    }
  }

  void clear() {
    _availableUpdate = null;
    _error = null;
    _downloading = false;
    _downloadProgress = 0;
    _statusMessage = null;
    notifyListeners();
  }
}
