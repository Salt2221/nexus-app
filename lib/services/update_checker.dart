// ════════════════════════════════════════════
// NEXUS Auto Updater — локальная проверка версий
// ════════════════════════════════════════════

import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;

class UpdateInfo {
  final String versionName;
  final int versionCode;
  final String downloadUrl;
  final String changelog;

  UpdateInfo({
    required this.versionName,
    required this.versionCode,
    required this.downloadUrl,
    required this.changelog,
  });

  factory UpdateInfo.fromJson(Map<String, dynamic> json) {
    return UpdateInfo(
      versionName: json['versionName'] as String? ?? '0.0.0',
      versionCode: json['versionCode'] as int? ?? 0,
      downloadUrl: json['downloadUrl'] as String? ?? '',
      changelog: json['changelog'] as String? ?? '',
    );
  }
}

/// Текущая версия приложения (железно прописана)
const currentVersionName = '1.0.1';
const currentVersionCode = 2;

class UpdateChecker {
  UpdateChecker._();
  static final UpdateChecker instance = UpdateChecker._();

  Future<UpdateInfo?> checkForUpdate() async {
    try {
      final jsonStr = await rootBundle.loadString('assets/version.json');
      final remote = UpdateInfo.fromJson(json.decode(jsonStr) as Map<String, dynamic>);

      if (remote.versionCode > currentVersionCode) {
        return remote;
      }
      return null; // up to date
    } catch (e) {
      print('Update check failed: $e');
      return null;
    }
  }
}
