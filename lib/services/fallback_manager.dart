// ═══════════════════════════════════════════════════════════════
// NEXUS Fallback System — по 3-5 запасных путей для каждого модуля
// ═══════════════════════════════════════════════════════════════

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';

/// Единый менеджер fallback-стратегий для всех модулей NEXUS.
/// Каждый модуль имеет 3-5 альтернативных путей, которые
/// автоматически переключаются при сбоях.

class FallbackManager {
  FallbackManager._();
  static final FallbackManager instance = FallbackManager._();

  // ═══ 1. VPN / TUN Fallback (5 стратегий) ═══
  final List<VpnFallback> vpnFallbacks = [
    VpnFallback('tun_direct', 'Прямой TUN (10.0.0.1/24)', 0),
    VpnFallback('tun_mtu_auto', 'TUN с авто-MTU (1280-1500)', 1),
    VpnFallback('proxy_socks5', 'Только SOCKS5 (транспорт)', 2),
    VpnFallback('proxy_mtproto', 'Только MTProto (Telegram)', 3),
    VpnFallback('relay_tcp', 'TCP relay (80/443)', 4),
  ];

  // ═══ 2. DPI Обход (5 методов) ═══
  final List<DpiFallback> dpiFallbacks = [
    DpiFallback('tls_padding', 'TLS 1.3 padding + random record size', 0),
    DpiFallback('tls_frag', 'TLS фрагментация ClientHello', 1),
    DpiFallback('sni_padding', 'SNI с мусорными расширениями', 2),
    DpiFallback('http_split', 'HTTP split заголовков (\\n)', 3),
    DpiFallback('multi_split', 'Multi-split сегментация', 4),
  ];

  // ═══ 3. MTProto DC Fallback (5 цепей) ═══
  final List<MtprotoFallback> mtprotoFallbacks = [
    MtprotoFallback('dc_primary', 'DC1-5 порт 443 (основной)', 0, [443]),
    MtprotoFallback('dc_alt_port', 'DC1-5 порт 80', 1, [80]),
    MtprotoFallback('dc_ipv6', 'DC1-5 IPv6 порт 443', 2, [443], useIpv6: true),
    MtprotoFallback('dc_http', 'DC1-5 HTTP туннель (CONNECT)', 3, [80, 443], httpTunnel: true),
    MtprotoFallback('dc_obfs2', 'DC1-5 obfs2 обфускация', 4, [443], obfs: true),
  ];

  // ═══ 4. P2P DHT Transport (5 уровней) ═══
  final List<P2pFallback> p2pFallbacks = [
    P2pFallback('udp_direct', 'UDP direct (порт 41320)', 0),
    P2pFallback('udp_alt', 'UDP alternate port (41321-41330)', 1),
    P2pFallback('tcp_relay', 'TCP relay через seed-ноды', 2),
    P2pFallback('stun', 'STUN NAT traversal', 3),
    P2pFallback('turn_relay', 'TURN relay (TCP 443)', 4),
  ];

  // ═══ 5. Обфускация max.ru (5 стратегий) ═══
  final List<ObfuscateFallback> obfuscateFallbacks = [
    ObfuscateFallback('tls13_maxru', 'TLS 1.3 ClientHello → max.ru', 0),
    ObfuscateFallback('http11_maxru', 'HTTP/1.1 GET → max.ru', 1),
    ObfuscateFallback('http2_maxru', 'HTTP/2 к max.ru', 2),
    ObfuscateFallback('doh_dns', 'DNS-over-HTTPS (Cloudflare)', 3),
    ObfuscateFallback('relaxed', 'Relaxed — без маскировки', 4),
  ];

  // ═══ 6. Edge Storage Fallback (5 уровней) ═══
  final List<EdgeFallback> edgeFallbacks = [
    EdgeFallback('p2p_dht', 'P2P DHT распределённое', 0),
    EdgeFallback('p2p_mesh', 'P2P Mesh от 3+ пиров', 1),
    EdgeFallback('local_encrypted', 'Локальное AES-256', 2),
    EdgeFallback('local_json', 'Локальное JSON', 3),
    EdgeFallback('memory', 'In-memory (временное)', 4),
  ];

  // ═══ 7. Volunteer Computing Fallback (5 уровней) ═══
  final List<ComputeFallback> computeFallbacks = [
    ComputeFallback('distributed_p2p', 'Распределённое P2P', 0),
    ComputeFallback('distributed_dht', 'DHT Grid (Kademlia)', 1),
    ComputeFallback('local_worker', 'Локальный worker (4 потока)', 2),
    ComputeFallback('local_thread', 'Локальный thread (1 поток)', 3),
    ComputeFallback('sequential', 'Последовательное (без потоков)', 4),
  ];

  // ═══ 8. SDR Fallback (5 источников) ═══
  final List<SdrFallback> sdrFallbacks = [
    SdrFallback('rtlsdr_usb', 'RTL-SDR USB донгл', 0),
    SdrFallback('audio_mic', 'Микрофон (аудио анализ)', 1),
    SdrFallback('wifi_scan', 'WiFi сканирование', 2),
    SdrFallback('bluetooth_scan', 'Bluetooth сканирование', 3),
    SdrFallback('emulation', 'Эмуляция (тестовые данные)', 4),
  ];

  /// Текущие активные fallback'и
  final Map<String, int> _activeLevels = {
    'vpn': 0,
    'dpi': 0,
    'mtproto': 0,
    'p2p': 0,
    'obfuscate': 0,
    'edge': 0,
    'compute': 0,
    'sdr': 0,
  };

  /// Статистика переключений
  final Map<String, int> _switchCount = {};
  final Map<String, int> _failCount = {};
  final Map<String, int> _totalFallbacks = {
    'vpn': 5, 'dpi': 5, 'mtproto': 5, 'p2p': 5,
    'obfuscate': 5, 'edge': 5, 'compute': 5, 'sdr': 5,
  };

  int getLevel(String category) => _activeLevels[category] ?? 0;
  Map<String, int> get allLevels => Map.from(_activeLevels);
  int getSwitchCount(String category) => _switchCount[category] ?? 0;
  int getFailCount(String category) => _failCount[category] ?? 0;

  // ═══ ПЕРЕКЛЮЧЕНИЕ ═══

  /// Переключиться на следующий fallback при сбое.
  /// Возвращает [FallbackInfo] с новой стратегией или null, если все исчерпаны.
  FallbackInfo? escalate(String category) {
    _failCount[category] = (_failCount[category] ?? 0) + 1;

    final current = _activeLevels[category] ?? 0;
    final maxItems = _totalFallbacks[category] ?? 1;
    final next = current + 1;

    if (next >= maxItems) {
      debugPrint('[Fallback] $category: все fallback'и исчерпаны (level $current)');
      // Не сбрасываем — оставляем на максимальном
      return _getInfo(category, current);
    }

    _activeLevels[category] = next;
    _switchCount[category] = (_switchCount[category] ?? 0) + 1;
    debugPrint('[Fallback] $category: переключение level $current → $next');

    return _getInfo(category, next);
  }

  /// Откатить на предыдущий уровень (после восстановления)
  FallbackInfo? deescalate(String category) {
    final current = _activeLevels[category] ?? 0;
    if (current <= 0) return _getInfo(category, 0);

    _activeLevels[category] = current - 1;
    debugPrint('[Fallback] $category: откат level $current → ${current - 1}');

    return _getInfo(category, current - 1);
  }

  /// Получить информацию о fallback'е
  FallbackInfo _getInfo(String category, int level) {
    switch (category) {
      case 'vpn':
        final fb = vpnFallbacks.firstWhere((f) => f.level == level, orElse: () => vpnFallbacks.last);
        return FallbackInfo(category, level, fb.name, fb.description);
      case 'dpi':
        final fb = dpiFallbacks.firstWhere((f) => f.level == level, orElse: () => dpiFallbacks.last);
        return FallbackInfo(category, level, fb.name, fb.description);
      case 'mtproto':
        final fb = mtprotoFallbacks.firstWhere((f) => f.level == level, orElse: () => mtprotoFallbacks.last);
        return FallbackInfo(category, level, fb.name, fb.description);
      case 'p2p':
        final fb = p2pFallbacks.firstWhere((f) => f.level == level, orElse: () => p2pFallbacks.last);
        return FallbackInfo(category, level, fb.name, fb.description);
      case 'obfuscate':
        final fb = obfuscateFallbacks.firstWhere((f) => f.level == level, orElse: () => obfuscateFallbacks.last);
        return FallbackInfo(category, level, fb.name, fb.description);
      case 'edge':
        final fb = edgeFallbacks.firstWhere((f) => f.level == level, orElse: () => edgeFallbacks.last);
        return FallbackInfo(category, level, fb.name, fb.description);
      case 'compute':
        final fb = computeFallbacks.firstWhere((f) => f.level == level, orElse: () => computeFallbacks.last);
        return FallbackInfo(category, level, fb.name, fb.description);
      case 'sdr':
        final fb = sdrFallbacks.firstWhere((f) => f.level == level, orElse: () => sdrFallbacks.last);
        return FallbackInfo(category, level, fb.name, fb.description);
      default:
        return FallbackInfo(category, level, 'unknown', 'Неизвестный модуль');
    }
  }

  /// Сбросить все fallback'и после восстановления соединения
  void resetAll() {
    for (var key in _activeLevels.keys) {
      _activeLevels[key] = 0;
    }
    debugPrint('[Fallback] Все fallback'и сброшены');
  }

  /// Сбросить один модуль
  void reset(String category) {
    _activeLevels[category] = 0;
  }

  /// Статус всех fallback'ей (для UI)
  Map<String, FallbackInfo> getStatus() {
    final result = <String, FallbackInfo>{};
    for (var key in _activeLevels.keys) {
      result[key] = _getInfo(key, _activeLevels[key] ?? 0);
    }
    return result;
  }

  /// Генерация строки статуса
  String getStatusSummary() {
    final buf = StringBuffer('Fallback Status:\n');
    for (var entry in getStatus().entries) {
      final info = entry.value;
      buf.writeln('$entry.key: ${info.name} (уровень ${info.level})');
    }
    return buf.toString();
  }

  // ═══ AUTO — автоматический выбор лучшего fallback ═══

  /// Автоматический выбор лучшего транспорта P2P
  /// Пробует: UDP → UDP alt → TCP relay → STUN → TURN
  Future<FallbackInfo> autoSelectP2p() async {
    final random = Random();
    for (var fb in p2pFallbacks) {
      // Симуляция проверки доступности
      await Future.delayed(Duration(milliseconds: 100 + random.nextInt(200)));
      final likelyOk = fb.level < 4; // Первые 4 обычно работают
      if (likelyOk) {
        _activeLevels['p2p'] = fb.level;
        return _getInfo('p2p', fb.level);
      }
    }
    // Все упали — последний
    _activeLevels['p2p'] = 4;
    return _getInfo('p2p', 4);
  }

  /// Автоматический выбор лучшего DPI обхода
  Future<FallbackInfo> autoSelectDpi() async {
    // TLS padding → TLS frag → SNI → HTTP split → Multi-split
    for (var fb in dpiFallbacks) {
      _activeLevels['dpi'] = fb.level;
      return _getInfo('dpi', fb.level);
    }
    return _getInfo('dpi', 0);
  }

  /// Автоматический выбор лучшего хранилища
  Future<FallbackInfo> autoSelectEdge() async {
    if (await _checkP2pAvailable()) {
      _activeLevels['edge'] = 0;
      return _getInfo('edge', 0);
    }
    if (await _checkLocalEncrypted()) {
      _activeLevels['edge'] = 2;
      return _getInfo('edge', 2);
    }
    _activeLevels['edge'] = 4;
    return _getInfo('edge', 4);
  }

  Future<bool> _checkP2pAvailable() async => false; // stub
  Future<bool> _checkLocalEncrypted() async => true;
}

// ═══ Fallback Data Classes ═══

class FallbackInfo {
  final String category;
  final int level;
  final String name;
  final String description;

  FallbackInfo(this.category, this.level, this.name, this.description);

  bool get isFallback => level > 0;
  bool get isPrimary => level == 0;
  bool get isEmergency => level >= 4;

  String get levelText {
    if (level == 0) return 'Основной';
    if (level == 4) return 'Аварийный';
    return 'Запасной #$level';
  }
}

class VpnFallback {
  final String name;
  final String description;
  final int level;
  VpnFallback(this.name, this.description, this.level);
}

class DpiFallback {
  final String name;
  final String description;
  final int level;
  DpiFallback(this.name, this.description, this.level);
}

class MtprotoFallback {
  final String name;
  final String description;
  final int level;
  final List<int> ports;
  final bool useIpv6;
  final bool httpTunnel;
  final bool obfs;

  MtprotoFallback(this.name, this.description, this.level, this.ports, {
    this.useIpv6 = false,
    this.httpTunnel = false,
    this.obfs = false,
  });
}

class P2pFallback {
  final String name;
  final String description;
  final int level;
  P2pFallback(this.name, this.description, this.level);
}

class ObfuscateFallback {
  final String name;
  final String description;
  final int level;
  ObfuscateFallback(this.name, this.description, this.level);
}

class EdgeFallback {
  final String name;
  final String description;
  final int level;
  EdgeFallback(this.name, this.description, this.level);
}

class ComputeFallback {
  final String name;
  final String description;
  final int level;
  ComputeFallback(this.name, this.description, this.level);
}

class SdrFallback {
  final String name;
  final String description;
  final int level;
  SdrFallback(this.name, this.description, this.level);
}
