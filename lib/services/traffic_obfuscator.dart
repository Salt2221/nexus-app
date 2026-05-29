// ═══════════════════════════════════════════════════════════════
// NEXUS Traffic Obfuscation — 5 стратегий маскировки
//
//  ВСЁ маскируется под HTTPS к max.ru
//  1. TLS 1.3 ClientHello → max.ru
//  2. HTTP/1.1 → max.ru
//  3. HTTP/2 → max.ru
//  4. DoH (DNS-over-HTTPS) → Cloudflare
//  5. Relaxed (минимальная маскировка)
//
//  Автопереключение + фейковый трафик
// ═══════════════════════════════════════════════════════════════

import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';

class TrafficObfuscator {
  TrafficObfuscator._();
  static final TrafficObfuscator instance = TrafficObfuscator._();

  // 5 стратегий
  static const int OBF_TLS13 = 0;
  static const int OBF_HTTP11 = 1;
  static const int OBF_HTTP2 = 2;
  static const int OBF_DOH = 3;
  static const int OBF_RELAXED = 4;

  int _current = 0;
  int _hostFailures = 0;
  final Random _random = Random();
  final List<int> _packetHistory = [];

  // max.ru домены для маскировки
  static const List<String> maxDomains = [
    'max.ru',
    'm.aviasales.ru',
    'static.max.ru',
    'cdn.max.ru',
    'api.max.ru',
  ];

  int get current => _current;
  String get currentName => strategyName(_current);

  static const List<String> strategyNames = [
    'TLS 1.3 → max.ru',
    'HTTP/1.1 → max.ru',
    'HTTP/2 → max.ru',
    'DoH Cloudflare',
    'Relaxed',
  ];

  String strategyName(int s) => s >= 0 && s < strategyNames.length ? strategyNames[s] : '?';

  // ═══ ОСНОВНАЯ ФУНКЦИЯ ═══

  /// Оборачивает сырой пакет в маскировку под max.ru
  /// Возвращает [Uint8List] с обфусцированными данными
  Uint8List obfuscate(Uint8List data, {String? domain}) {
    final domain_ = domain ?? maxDomains[_random.nextInt(maxDomains.length)];
    _packetHistory.add(data.length);
    if (_packetHistory.length > 20) _packetHistory.removeAt(0);

    switch (_current) {
      case OBF_TLS13:
        return _wrapTls13(data, domain_);
      case OBF_HTTP11:
        return _wrapHttp11(data, domain_);
      case OBF_HTTP2:
        return _wrapHttp2(data, domain_);
      case OBF_DOH:
        return _wrapDoh(data);
      case OBF_RELAXED:
        return _wrapRelaxed(data);
      default:
        return _wrapTls13(data, domain_);
    }
  }

  /// Деобфускация (обратная операция)
  Uint8List deobfuscate(Uint8List obfuscated) {
    // Пропускаем заголовок маскировки, возвращаем сырые данные
    if (obfuscated.length < 100) return obfuscated;

    // Ищем конец HTTP заголовка или начало TLS данных
    for (int i = 0; i < min(500, obfuscated.length - 4); i++) {
      // HTTP/1.1: ищем \r\n\r\n
      if (obfuscated[i] == 0x0D && obfuscated[i + 1] == 0x0A &&
          obfuscated[i + 2] == 0x0D && obfuscated[i + 3] == 0x0A) {
        final headerEnd = i + 4;
        if (headerEnd < obfuscated.length) {
          return obfuscated.sublist(headerEnd);
        }
      }

      // TLS: ищем Change Cipher Spec (0x14) или Application Data (0x17)
      if (obfuscated[i] == 0x14 && obfuscated[i + 1] == 0x03) {
        return obfuscated.sublist(i);
      }
      if (obfuscated[i] == 0x17 && obfuscated[i + 1] == 0x03) {
        return obfuscated.sublist(i);
      }
    }

    return obfuscated;
  }

  // ═══ СТРАТЕГИИ ═══

  /// Стратегия 1: TLS 1.3 ClientHello → max.ru
  Uint8List _wrapTls13(Uint8List data, String domain) {
    // TLS record header
    final tlsLen = data.length;
    final header = Uint8List(5 + 4 + 4 + domain.length); // type + ver + len + extra

    int pos = 0;
    header[pos++] = 0x16; // Handshake
    header[pos++] = 0x03; // Major
    header[pos++] = 0x03; // Minor (TLS 1.2 wire, 1.3 negotiated)
    header[pos++] = ((tlsLen + domain.length + 20) >> 8) & 0xFF;
    header[pos++] = (tlsLen + domain.length + 20) & 0xFF;

    // Fake Server Name Indication extension
    header[pos++] = 0x00; header[pos++] = domain.length.toInt(); // SNI len
    for (int i = 0; i < domain.length; i++) {
      header[pos++] = domain.codeUnitAt(i);
    }

    // Padding extension
    final padLen = 16 + _random.nextInt(48);
    for (int i = 0; i < padLen && pos < header.length; i++) {
      header[pos++] = _random.nextInt(256);
    }

    // Финальный размер
    final result = Uint8List(header.length + tlsLen);
    result.setRange(0, header.length, header);
    result.setRange(header.length, result.length, data);

    return result;
  }

  /// Стратегия 2: HTTP/1.1 GET → max.ru
  Uint8List _wrapHttp11(Uint8List data, String domain) {
    final randomPath = '/${_random.nextInt(9999)}?v=${_random.nextInt(999999)}';
    final extraLen = 50 + domain.length + randomPath.length;
    final header = 'GET $randomPath HTTP/1.1\r\n'
        'Host: $domain\r\n'
        'User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64)\r\n'
        'Accept: */*\r\n'
        'Accept-Language: ru-RU,ru;q=0.9\r\n'
        'Content-Length: ${data.length}\r\n'
        '\r\n';

    final result = Uint8List(header.length + data.length);
    result.setRange(0, header.length, header.codeUnits);
    result.setRange(header.length, result.length, data);

    return result;
  }

  /// Стратегия 3: HTTP/2 → max.ru
  Uint8List _wrapHttp2(Uint8List data, String domain) {
    // HTTP/2 frame + data
    final frame = Uint8List(9 + data.length);
    int pos = 0;
    frame[pos++] = ((data.length) >> 16) & 0xFF; // Length (3 bytes)
    frame[pos++] = ((data.length) >> 8) & 0xFF;
    frame[pos++] = (data.length) & 0xFF;
    frame[pos++] = 0x01; // Type: DATA
    frame[pos++] = 0x00; // Flags
    frame[pos++] = 0x00; frame[pos++] = 0x00; frame[pos++] = 0x00; frame[pos++] = 0x01; // Stream ID

    frame.setRange(pos, frame.length, data);
    return frame;
  }

  /// Стратегия 4: DoH
  Uint8List _wrapDoh(Uint8List data) {
    // DNS-over-HTTPS обёртка
    final header = 'POST /dns-query HTTP/1.1\r\n'
        'Host: 1.1.1.1\r\n'
        'Content-Type: application/dns-message\r\n'
        'Content-Length: ${data.length}\r\n'
        '\r\n';

    final result = Uint8List(header.length + data.length);
    result.setRange(0, header.length, header.codeUnits);
    result.setRange(header.length, result.length, data);
    return result;
  }

  /// Стратегия 5: Relaxed
  Uint8List _wrapRelaxed(Uint8List data) {
    // Минимальная маскировка — просто добавляем несколько байт
    final prefix = Uint8List(8);
    for (int i = 0; i < 8; i++) {
      prefix[i] = _random.nextInt(256);
    }

    final result = Uint8List(prefix.length + data.length);
    result.setRange(0, prefix.length, prefix);
    result.setRange(prefix.length, result.length, data);
    return result;
  }

  // ═══ УПРАВЛЕНИЕ ═══

  /// Переключение на следующую стратегию
  int escalate() {
    _hostFailures++;
    _current = (_current + 1) % 5;
    debugPrint('[Obfuscate] Switch to strategy $_current: ${strategyName(_current)}');
    return _current;
  }

  /// Автовыбор стратегии на основе типа трафика
  int autoSelect(String trafficType) {
    switch (trafficType) {
      case 'tls':
        _current = OBF_TLS13;
        break;
      case 'http':
        _current = OBF_HTTP11;
        break;
      case 'dns':
        _current = OBF_DOH;
        break;
      default:
        _current = OBF_HTTP2;
    }
    return _current;
  }

  /// Генерация фейкового трафика (для отвлечения DPI)
  Uint8List generateFakeTraffic() {
    final domain = maxDomains[_random.nextInt(maxDomains.length)];
    final fakeData = Uint8List(64 + _random.nextInt(256));
    for (int i = 0; i < fakeData.length; i++) {
      fakeData[i] = _random.nextInt(256);
    }
    return obfuscate(fakeData, domain: domain);
  }

  void reset() {
    _current = 0;
    _hostFailures = 0;
    _packetHistory.clear();
  }

  String getStatus() {
    return 'Обфускация: ${strategyName(_current)} | Сбоев хоста: $_hostFailures | Пакетов: ${_packetHistory.length}';
  }
}

int min(int a, int b) => a < b ? a : b;
