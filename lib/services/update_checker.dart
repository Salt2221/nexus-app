// ════════════════════════════════════════════
// NEXUS Auto Updater — GitHub Config/Data Updates
// Не скачивает APK, а обновляет конфигурацию, фичи,
// и данные приложения через GitHub API.
// ════════════════════════════════════════════

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

/// Информация о доступном обновлении
class UpdateInfo {
  final String versionName;
  final int versionCode;
  final String changelog;

  UpdateInfo({
    required this.versionName,
    required this.versionCode,
    required this.changelog,
  });

  factory UpdateInfo.fromJson(Map<String, dynamic> json) {
    return UpdateInfo(
      versionName: json['versionName'] as String? ?? '0.0.0',
      versionCode: json['versionCode'] as int? ?? 0,
      changelog: json['changelog'] as String? ?? '',
    );
  }
}

/// Конфигурация приложения, обновляемая через GitHub
class NexusConfig {
  List<String> proxyServers;
  List<String> bridgeUrls;
  Map<String, dynamic> features;
  int connectionTimeout;
  int reconnectDelay;

  NexusConfig({
    this.proxyServers = const ['wss://tgbridge.iamka.ru/ws'],
    this.bridgeUrls = const ['wss://tgbridge.iamka.ru/ws'],
    this.features = const {'telegram_proxy': true, 'mesh_network': false, 'vpn_service': true},
    this.connectionTimeout = 5000,
    this.reconnectDelay = 5000,
  });

  factory NexusConfig.fromJson(Map<String, dynamic> json) {
    return NexusConfig(
      proxyServers: (json['proxyServers'] as List?)?.cast<String>() ?? ['wss://tgbridge.iamka.ru/ws'],
      bridgeUrls: (json['bridgeUrls'] as List?)?.cast<String>() ?? ['wss://tgbridge.iamka.ru/ws'],
      features: (json['features'] as Map<String, dynamic>?) ?? {},
      connectionTimeout: json['connectionTimeout'] as int? ?? 5000,
      reconnectDelay: json['reconnectDelay'] as int? ?? 5000,
    );
  }

  Map<String, dynamic> toJson() => {
    'proxyServers': proxyServers,
    'bridgeUrls': bridgeUrls,
    'features': features,
    'connectionTimeout': connectionTimeout,
    'reconnectDelay': reconnectDelay,
  };
}

const currentVersionName = '1.0.0';
const currentVersionCode = 1;
const _repoOwner = 'Salt2221';
const _repoName = 'nexus-app';
const _configPath = 'nexus_config.json';

class UpdateChecker extends ChangeNotifier {
  UpdateChecker._();
  static final UpdateChecker instance = UpdateChecker._();

  bool _checking = false;
  bool _syncing = false;
  double _syncProgress = 0;
  String? _statusMessage;
  UpdateInfo? _availableUpdate;
  String? _error;
  NexusConfig? _latestConfig;

  bool get checking => _checking;
  bool get syncing => _syncing;
  double get syncProgress => _syncProgress;
  String? get statusMessage => _statusMessage;
  UpdateInfo? get availableUpdate => _availableUpdate;
  String? get error => _error;
  bool get hasUpdate => _availableUpdate != null;

  /// Проверка новой версии через GitHub Release
  Future<UpdateInfo?> checkForUpdate() async {
    if (_checking) return null;
    _checking = true;
    _error = null;
    _availableUpdate = null;
    notifyListeners();

    try {
      final url = Uri.parse('https://api.github.com/repos/$_repoOwner/$_repoName/releases/latest');
      final res = await http.get(
        url,
        headers: {
          'Accept': 'application/vnd.github.v3+json',
          'User-Agent': 'NEXUS-Android/1.0',
        },
      );

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        final tagName = data['tag_name'] as String? ?? 'v0.0.0';
        final versionName = tagName.replaceAll(RegExp(r'^v'), '');
        final body = data['body'] as String? ?? '';

        final parts = versionName.split('.').map((s) => int.tryParse(s) ?? 0).toList();
        final versionCode = (parts.isNotEmpty ? parts[0] : 0) * 10000 +
            (parts.isNotEmpty && parts.length > 1 ? parts[1] : 0) * 100 +
            (parts.isNotEmpty && parts.length > 2 ? parts[2] : 0);

        if (versionCode > currentVersionCode) {
          _availableUpdate = UpdateInfo(
            versionName: versionName,
            versionCode: versionCode,
            changelog: body,
          );
        }
      } else if (res.statusCode != 404) {
        _error = 'Ошибка сервера (${res.statusCode})';
      }
    } catch (e) {
      _error = 'Нет подключения к интернету';
    }

    _checking = false;
    notifyListeners();
    return _availableUpdate;
  }

  /// Синхронизация конфигурации с GitHub
  /// Обновляет: настройки прокси, фичи, параметры подключения
  Future<bool> syncConfiguration() async {
    _syncing = true;
    _syncProgress = 0;
    _statusMessage = 'Синхронизация конфигурации...';
    notifyListeners();

    try {
      // 1. Загружаем конфиг из GitHub
      final url = Uri.parse('https://raw.githubusercontent.com/$_repoOwner/$_repoName/main/$_configPath');
      final res = await http.get(url);

      if (res.statusCode == 200) {
        final json = jsonDecode(res.body) as Map<String, dynamic>;
        _latestConfig = NexusConfig.fromJson(json);
        _syncProgress = 0.5;
        _statusMessage = 'Конфигурация загружена';
        notifyListeners();

        // 2. Сохраняем в SharedPreferences
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('nexus_config', jsonEncode(_latestConfig!.toJson()));
        _syncProgress = 1.0;
        _statusMessage = 'Конфигурация применена';
        notifyListeners();

        return true;
      } else if (res.statusCode == 404) {
        // Конфиг ещё не создан на GitHub — не ошибка
        _statusMessage = 'Конфигурация не найдена на GitHub';
        _latestConfig = NexusConfig();
        notifyListeners();
        return true;
      } else {
        _error = 'Ошибка загрузки конфига (${res.statusCode})';
        notifyListeners();
        return false;
      }
    } catch (e) {
      _error = 'Ошибка синхронизации: $e';
      _syncing = false;
      notifyListeners();
      return false;
    }
  }

  /// Загружаем сохранённую конфигурацию
  Future<NexusConfig> loadConfig() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('nexus_config');
    if (saved != null) {
      try {
        return NexusConfig.fromJson(jsonDecode(saved));
      } catch (_) {}
    }
    return NexusConfig();
  }

  /// Применение обновления (синхронизация конфигурации и данных)
  Future<bool> applyUpdate() async {
    _statusMessage = 'Применение обновления...';
    notifyListeners();

    final configOk = await syncConfiguration();
    if (configOk) {
      _availableUpdate = null;
      _statusMessage = 'Приложение обновлено';
    } else {
      _statusMessage = 'Ошибка обновления';
    }
    notifyListeners();
    return configOk;
  }

  /// Сброс
  void clear() {
    _availableUpdate = null;
    _error = null;
    _syncing = false;
    _syncProgress = 0;
    _statusMessage = null;
    notifyListeners();
  }
}
