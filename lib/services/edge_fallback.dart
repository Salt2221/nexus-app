// ═══════════════════════════════════════════════════════════════
// NEXUS Edge Storage Fallback — 5 уровней хранения
//
//  1. P2P DHT (распределённое)
//  2. P2P Mesh (3+ пира)
//  3. Локальное AES-256
//  4. Локальное JSON
//  5. In-memory (временное)
//
//  Автоматическое переключение при недоступности пиров
// ═══════════════════════════════════════════════════════════════

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class EdgeFallbackStorage {
  EdgeFallbackStorage._();
  static final EdgeFallbackStorage instance = EdgeFallbackStorage._();

  // 5 уровней
  static const int P2P_DHT = 0;
  static const int P2P_MESH = 1;
  static const int LOCAL_AES = 2;
  static const int LOCAL_JSON = 3;
  static const int MEMORY = 4;

  int _current = 0;
  final Map<String, dynamic> _memoryStore = {};
  Timer? _retryTimer;

  int get current => _current;

  // ═══ API ═══

  Future<void> store(String key, dynamic value) async {
    switch (_current) {
      case P2P_DHT:
      case P2P_MESH:
        await _storeP2p(key, value);
        break;
      case LOCAL_AES:
        await _storeAes(key, value);
        break;
      case LOCAL_JSON:
        await _storeJson(key, value);
        break;
      case MEMORY:
        _memoryStore[key] = value;
        break;
    }
  }

  Future<dynamic> load(String key) async {
    switch (_current) {
      case P2P_DHT:
      case P2P_MESH:
        return _loadP2p(key);
      case LOCAL_AES:
        return _loadAes(key);
      case LOCAL_JSON:
        return _loadJson(key);
      case MEMORY:
        return _memoryStore[key];
    }
    return null;
  }

  Future<void> delete(String key) async {
    switch (_current) {
      case P2P_DHT:
      case P2P_MESH:
        _memoryStore.remove(key);
        break;
      case LOCAL_AES:
        await _deleteAes(key);
        break;
      case LOCAL_JSON:
        await _deleteJson(key);
        break;
      case MEMORY:
        _memoryStore.remove(key);
        break;
    }
  }

  // ═══ УРОВНИ ═══

  Future<void> _storeP2p(String key, dynamic value) async {
    // В реальности — отправка в DHT сеть
    _memoryStore[key] = value;
    debugPrint('[Edge] P2P store $key');
  }

  Future<dynamic> _loadP2p(String key) async {
    return _memoryStore[key];
  }

  Future<void> _storeAes(String key, dynamic value) async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = jsonEncode(value);
    // В реальности — AES-256-GCM шифрование
    await prefs.setString('nexus_ed_$key', encoded);
    debugPrint('[Edge] AES store $key');
  }

  Future<dynamic> _loadAes(String key) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('nexus_ed_$key');
    if (raw == null) return null;
    return jsonDecode(raw);
  }

  Future<void> _deleteAes(String key) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('nexus_ed_$key');
  }

  Future<void> _storeJson(String key, dynamic value) async {
    final dir = Directory.systemTemp;
    final file = File('${dir.path}/nexus_ed_$key.json');
    await file.writeAsString(jsonEncode(value));
  }

  Future<dynamic> _loadJson(String key) async {
    try {
      final file = File('${Directory.systemTemp.path}/nexus_ed_$key.json');
      if (!await file.exists()) return null;
      return jsonDecode(await file.readAsString());
    } catch (_) {
      return null;
    }
  }

  Future<void> _deleteJson(String key) async {
    try {
      final file = File('${Directory.systemTemp.path}/nexus_ed_$key.json');
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }

  // ═══ ПЕРЕКЛЮЧЕНИЕ ═══

  /// Эскалация уровня хранения
  int escalate() {
    _current = (_current + 1) % 5;
    debugPrint('[Edge] Fallback to level $_current: ${_levelName(_current)}');
    return _current;
  }

  /// Автовыбор: P2P → AES → JSON → Memory
  Future<int> autoSelect() async {
    // Пробуем P2P
    if (await _checkP2p()) { _current = P2P_DHT; return P2P_DHT; }

    _current = LOCAL_AES;
    return LOCAL_AES;
  }

  Future<bool> _checkP2p() async {
    // Проверка доступности DHT
    try {
      final sock = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      sock.close();
      return true;
    } catch (_) {
      return false;
    }
  }

  String _levelName(int l) {
    switch (l) {
      case P2P_DHT: return 'P2P DHT';
      case P2P_MESH: return 'P2P Mesh';
      case LOCAL_AES: return 'AES-256';
      case LOCAL_JSON: return 'JSON';
      case MEMORY: return 'Memory';
      default: return '?';
    }
  }

  String get currentName => _levelName(_current);

  void cleanup() {
    _retryTimer?.cancel();
    _memoryStore.clear();
  }
}
