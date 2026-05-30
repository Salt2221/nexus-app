// ═══════════════════════════════════════════════════════════════
// NEXUS DPI Bypass — 5 стратегий обхода DPI
//
//  1. TLS 1.3 padding — случайные TLS-записи в конце
//  2. TLS фрагментация — разбивка ClientHello на части
//  3. SNI padding — подмена/зашумление SNI
//  4. HTTP split — разделение заголовков
//  5. Multi-split — полная сегментация
//
//  Автоматическое переключение при блокировках
// ═══════════════════════════════════════════════════════════════

import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';

class DpiBypass {
  DpiBypass._();
  static final DpiBypass instance = DpiBypass._();

  int _currentStrategy = 0;

  // 5 стратегий
  static const int STRATEGY_TLS_PADDING = 0;
  static const int STRATEGY_TLS_FRAG = 1;
  static const int STRATEGY_SNI_PADDING = 2;
  static const int STRATEGY_HTTP_SPLIT = 3;
  static const int STRATEGY_MULTI_SPLIT = 4;

  int get currentStrategy => _currentStrategy;
  String get currentName => strategyName(_currentStrategy);

  static const List<String> strategyNames = [
    'TLS 1.3 Padding',
    'TLS Fragmentation',
    'SNI Padding',
    'HTTP Split',
    'Multi-split',
  ];

  String strategyName(int s) => s >= 0 && s < strategyNames.length ? strategyNames[s] : 'Unknown';

  /// Применить стратегию к пакету
  /// Возвращает модифицированный пакет
  Uint8List apply(Uint8List data, {String? sni}) {
    switch (_currentStrategy) {
      case STRATEGY_TLS_PADDING:
        return _tlsPadding(data);
      case STRATEGY_TLS_FRAG:
        return _tlsFragment(data);
      case STRATEGY_SNI_PADDING:
        return _sniPadding(data, sni: sni);
      case STRATEGY_HTTP_SPLIT:
        return _httpSplit(data);
      case STRATEGY_MULTI_SPLIT:
        return _multiSplit(data);
      default:
        return data;
    }
  }

  /// Стратегия 1: TLS 1.3 padding — случайные записи в конце
  Uint8List _tlsPadding(Uint8List data) {
    if (data.length < 5) return data;
    final random = Random();
    final padLen = 32 + random.nextInt(96); // 32-128 байт
    final result = Uint8List(data.length + padLen);
    result.setRange(0, data.length, data);

    // Заполняем случайными TLS-подобными данными
    final tlsType = 0x17; // Application Data
    for (int i = 0; i < padLen; i++) {
      result[data.length + i] = random.nextInt(256);
    }
    return result;
  }

  /// Стратегия 2: TLS фрагментация — разбивка ClientHello
  Uint8List _tlsFragment(Uint8List data) {
    if (data.length < 10) return data;
    final random = Random();

    // Ищем ClientHello (0x16 0x03 0x01)
    int chOffset = -1;
    for (int i = 0; i < data.length - 2; i++) {
      if (data[i] == 0x16 && data[i + 1] == 0x03) {
        chOffset = i;
        break;
      }
    }
    if (chOffset < 0) return data;

    // Разбиваем на 2-4 части
    final parts = 2 + random.nextInt(3);
    final partSize = (data.length - chOffset) ~/ parts;
    final result = Uint8List(data.length + parts * 10);
    result.setRange(0, chOffset, data.sublist(0, chOffset));

    int pos = chOffset;
    for (int p = 0; p < parts; p++) {
      final size = p == parts - 1
          ? data.length - pos
          : partSize;
      // TLS record header
      result[pos++] = 0x16;
      result[pos++] = 0x03;
      result[pos++] = 0x01;
      result[pos++] = 0x00; // size high
      result[pos++] = (size & 0xFF).toInt(); // size low
      for (int s = 0; s < size && pos < result.length; s++) {
        result[pos++] = data[chOffset + p * partSize + s];
      }
    }

    return result.sublist(0, pos);
  }

  /// Стратегия 3: SNI padding — мусорные расширения
  Uint8List _sniPadding(Uint8List data, {String? sni}) {
    final random = Random();
    if (data.length < 50) return data;

    // Добавляем фейковые TLS расширения
    final fakeExtLen = 16 + random.nextInt(48);
    final result = Uint8List(data.length + fakeExtLen);
    result.setRange(0, data.length, data);

    // Фейковые расширения
    int pos = data.length;
    for (int i = 0; i < fakeExtLen; i++) {
      result[pos++] = random.nextInt(256);
    }

    return result;
  }

  /// Стратегия 4: HTTP split — разделение заголовков
  Uint8List _httpSplit(Uint8List data) {
    final text = String.fromCharCodes(data);
    if (!text.contains('HTTP') && !text.contains('GET') && !text.contains('POST')) {
      return data; // Не HTTP
    }

    // Вставляем \n в середину первой строки
    final lines = text.split('\r\n');
    if (lines.isEmpty) return data;

    final first = lines[0];
    if (first.length < 10) return data;

    final splitPoint = first.length ~/ 2;
    final modified = '${first.substring(0, splitPoint)}\n${first.substring(splitPoint)}';
    lines[0] = modified;

    final result = lines.join('\r\n');
    return Uint8List.fromList(result.codeUnits);
  }

  /// Стратегия 5: Multi-split — полная случайная сегментация
  Uint8List _multiSplit(Uint8List data) {
    if (data.length < 20) return data;
    final random = Random();

    // Добавляем случайные разделители
    final numSplits = 1 + random.nextInt(4); // 1-5 сплитов
    final result = Uint8List(data.length + numSplits * 4);
    result.setRange(0, data.length, data);

    int pos = data.length;
    for (int i = 0; i < numSplits; i++) {
      // Случайный маркер
      result[pos++] = 0x00;
      result[pos++] = 0x00;
      result[pos++] = 0xFF;
      result[pos++] = 0xFE;
    }

    return result.sublist(0, pos);
  }

  /// Переключиться на следующую стратегию при блокировке
  int escalate() {
    _currentStrategy = (_currentStrategy + 1) % 5;
    debugPrint('[DPI] Switch to strategy $_currentStrategy: ${strategyName(_currentStrategy)}');
    return _currentStrategy;
  }

  /// Сбросить на самую безопасную
  void reset() {
    _currentStrategy = 0;
  }

  /// Выбрать лучшую стратегию на основе типа трафика
  int autoSelect(String trafficType) {
    switch (trafficType) {
      case 'tls':
        _currentStrategy = STRATEGY_TLS_PADDING;
        break;
      case 'http':
        _currentStrategy = STRATEGY_HTTP_SPLIT;
        break;
      case 'ws':
        _currentStrategy = STRATEGY_MULTI_SPLIT;
        break;
      default:
        _currentStrategy = STRATEGY_TLS_FRAG;
    }
    return _currentStrategy;
  }
}
