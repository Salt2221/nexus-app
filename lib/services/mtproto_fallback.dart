// ═══════════════════════════════════════════════════════════════
// NEXUS MTProto Fallback — 5 цепей DC с автопереключением
//
//  1. DC1-5 основной порт 443
//  2. DC1-5 порт 80
//  3. DC IPv6 порт 443
//  4. HTTP туннель (CONNECT)
//  5. obfs2 обфускация
//
//  Каждая цепь имеет 5 DC, итого 25 комбинаций
// ═══════════════════════════════════════════════════════════════

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';

class MtprotoFallbackChain {
  final int chainId;
  final String name;
  final int port;
  final bool useIpv6;
  final bool httpTunnel;
  final bool obfs;

  MtprotoFallbackChain({
    required this.chainId,
    required this.name,
    required this.port,
    this.useIpv6 = false,
    this.httpTunnel = false,
    this.obfs = false,
  });
}

class MtprotoFallbackManager {
  MtprotoFallbackManager._();
  static final MtprotoFallbackManager instance = MtprotoFallbackManager._();

  // ═══ 5 цепей fallback ═══
  final List<MtprotoFallbackChain> chains = [
    MtprotoFallbackChain(chainId: 0, name: 'DC 443 (основной)', port: 443),
    MtprotoFallbackChain(chainId: 1, name: 'DC 80', port: 80),
    MtprotoFallbackChain(chainId: 2, name: 'DC IPv6 443', port: 443, useIpv6: true),
    MtprotoFallbackChain(chainId: 3, name: 'HTTP туннель', port: 443, httpTunnel: true),
    MtprotoFallbackChain(chainId: 4, name: 'obfs2', port: 443, obfs: true),
  ];

  // ═══ Telegram DC адреса ═══
  static const List<Map<String, dynamic>> dcList = [
    {'id': 1, 'ipv4': '149.154.175.53', 'ipv6': '2001:67c:4e8:f002::a'},
    {'id': 2, 'ipv4': '149.154.167.51', 'ipv6': '2001:67c:4e8:f002::b'},
    {'id': 3, 'ipv4': '149.154.175.100', 'ipv6': '2001:67c:4e8:f002::c'},
    {'id': 4, 'ipv4': '149.154.167.91', 'ipv6': '2001:67c:4e8:f002::d'},
    {'id': 5, 'ipv4': '149.154.171.5', 'ipv6': '2001:67c:4e8:f002::e'},
  ];

  int _currentChain = 0;
  int _currentDc = 0;
  int _failCount = 0;

  int get currentChain => _currentChain;
  int get currentDc => _currentDc;
  int get failCount => _failCount;

  /// Получить текущий адрес подключения
  Map<String, dynamic>? getCurrentTarget() {
    if (_currentChain >= chains.length) return null;
    if (_currentDc >= dcList.length) return null;

    final chain = chains[_currentChain];
    final dc = dcList[_currentDc];

    return {
      'chain': chain.chainId,
      'chainName': chain.name,
      'dcId': dc['id'],
      'address': chain.useIpv6 ? dc['ipv6'] : dc['ipv4'],
      'port': chain.port,
      'httpTunnel': chain.httpTunnel,
      'obfs': chain.obfs,
    };
  }

  /// Переключиться на следующий DC (через 5 DC каждой цепи)
  /// Всего 5 цепей × 5 DC = 25 комбинаций
  Map<String, dynamic>? next() {
    _currentDc++;
    if (_currentDc >= dcList.length) {
      _currentDc = 0;
      _currentChain++;

      if (_currentChain >= chains.length) {
        debugPrint('[MTProto] Все 25 комбинаций DC исчерпаны');
        _currentChain = 0;
        return getCurrentTarget();
      }

      debugPrint('[MTProto] Цепь: ${chains[_currentChain].name}');
    } else {
      debugPrint('[MTProto] DC${dcList[_currentDc]['id']} (цепь ${_currentChain})');
    }

    _failCount++;
    return getCurrentTarget();
  }

  /// Попробовать подключиться к текущему DC
  Future<bool> tryConnect({Duration timeout = const Duration(seconds: 5)}) async {
    final target = getCurrentTarget();
    if (target == null) return false;

    final address = target['address'] as String;
    final port = target['port'] as int;
    final httpTunnel = target['httpTunnel'] as bool? ?? false;

    try {
      if (httpTunnel) {
        // HTTP CONNECT туннель
        final socket = await Socket.connect(address, port, timeout: timeout);
        final connectReq = 'CONNECT 149.154.175.100:443 HTTP/1.1\r\nHost: 149.154.175.100\r\n\r\n';
        socket.add(connectReq.codeUnits);
        socket.close();
        await socket.drain();
        return true;
      }

      final socket = await Socket.connect(address, port, timeout: timeout);
      socket.close();
      return true;
    } catch (e) {
      debugPrint('[MTProto] DC ${target['dcId']} fail: $e');
      return false;
    }
  }

  /// Автоматический поиск работающего DC
  /// Пробует все комбинации до первого успеха
  Future<Map<String, dynamic>?> findWorking() async {
    for (int c = 0; c < chains.length; c++) {
      for (int d = 0; d < dcList.length; d++) {
        _currentChain = c;
        _currentDc = d;

        final ok = await tryConnect();
        if (ok) {
          debugPrint('[MTProto] Работает: ${chains[c].name} DC${dcList[d]['id']}');
          return getCurrentTarget();
        }

        // Следующий DC
        _currentDc++;
        _currentDc %= dcList.length;
      }
      _currentChain++;
    }

    debugPrint('[MTProto] Все DC недоступны');
    return null;
  }

  void reset() {
    _currentChain = 0;
    _currentDc = 0;
    _failCount = 0;
  }

  String getStatus() {
    final target = getCurrentTarget();
    if (target == null) return 'No DC';
    return '${target['chainName']} DC${target['dcId']} (chain ${target['chain']}/${chains.length})';
  }
}
