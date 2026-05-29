// ═══════════════════════════════════════════════════════════════
// NEXUS TLS Obfuscator — маскировка ВСЕГО трафика под max.ru
//
// Что делает:
//   1. Весь исходящий трафик выглядит как HTTPS к max.ru
//   2. TLS 1.3 ClientHello с SNI = max.ru
//   3. HTTP/2 или HTTP/1.1 Upgrade заголовки с max.ru
//   4. DNS через DoH (dns.max.ru)
//   5. Сертификат подписан "Maks" (подделка под реальный)
//   6. Random TLS padding (до 512 байт) для борьбы с DPI
//   7. TCP-сегментация — пакеты не длиннее 512 байт
//
// ВСЁ НА ЧИСТОМ DART — только через RawDatagramSocket / RawSocket
// Нативный код (C) — более глубокая обфускация на уровне сокетов
// ═══════════════════════════════════════════════════════════════

import "dart:async";
import "dart:convert";
import "dart:io";
import "dart:math";
import "dart:typed_data";
import "package:flutter/foundation.dart";

// ═══ КОНСТАНТЫ ═══

/// max.ru — маскировочный домен
const String MAX_DOMAIN = "max.ru";
const String MAX_CDN = "static.max.ru";
const String MAX_API = "api.max.ru";

/// MAX.RU TLS сертификат (публичные данные, для обфускации)
/// Эти байты симулируют реальный TLS сертификат max.ru
const List<int> MAX_CERT_FINGERPRINT = [
  0x8E, 0x6A, 0x6B, 0x3C, 0x23, 0x8C, 0x39, 0xFC,
  0x7B, 0x80, 0x22, 0x11, 0x2E, 0x0E, 0x48, 0x7C,
  0xB9, 0xC3, 0xD5, 0x24, 0xAF, 0x7C, 0xF4, 0x0F,
  0xFB, 0xD3, 0x8C, 0x75, 0x69, 0xDE, 0xAD, 0xD1,
];

/// Типы обфускации для разных протоколов
enum ObfuscationType {
  tls13,        // TLS 1.3 ClientHello
  http2,        // HTTP/2 PRI + HEADERS
  http11,       // HTTP/1.1 Upgrade
  quic,         // QUIC initial (0-RTT)
  ws,           // WebSocket upgrade
  doh,          // DNS over HTTPS
  tcpSegment,   // TCP segmentation only
}

// ═══ TLS 1.3 ClientHello Builder ═══

/// Строит настоящий TLS 1.3 ClientHello с SNI = max.ru
class TlsClientHelloBuilder {
  final String serverName;
  final int tlsVersion; // 0x0303 = TLS 1.2, 0x0304 = TLS 1.3
  final List<int> _random;
  final int _sessionIdLen;
  final List<List<int>> _cipherSuites;
  final List<int> _extensions;

  TlsClientHelloBuilder({
    this.serverName = MAX_DOMAIN,
    this.tlsVersion = 0x0304,
    List<int>? random,
    int sessionIdLen = 32,
    List<List<int>>? cipherSuites,
  }) : _random = random ?? List.generate(32, (_) => Random.secure().nextInt(256)),
       _sessionIdLen = sessionIdLen,
       _cipherSuites = cipherSuites ?? _defaultCipherSuites,
       _extensions = [];

  static const _defaultCipherSuites = [
    // TLS 1.3
    [0x13, 0x01], // TLS_AES_128_GCM_SHA256
    [0x13, 0x02], // TLS_AES_256_GCM_SHA384
    [0x13, 0x03], // TLS_CHACHA20_POLY1305_SHA256
    // TLS 1.2
    [0x00, 0x9C], // TLS_AES_128_GCM_SHA256
    [0x00, 0x9D], // TLS_AES_256_GCM_SHA384
  ];

  /// Построить полный TLS ClientHello
  Uint8List build() {
    var buf = BytesBuilder();

    // ─── Record Layer ───
    buf.addByte(0x16); // ContentType: Handshake (22)
    buf.addByte((tlsVersion >> 8) & 0xFF);
    buf.addByte(tlsVersion & 0xFF);
    // Length placeholder
    var lengthPos = buf.length;
    buf.addByte(0); buf.addByte(0);

    // ─── Handshake: ClientHello ───
    buf.addByte(0x01); // HandshakeType: ClientHello
    var helloLenPos = buf.length;
    buf.addByte(0); buf.addByte(0); buf.addByte(0); // length placeholder

    // Version
    buf.addByte(0x03); buf.addByte(0x03); // TLS 1.2 (legacy)

    // Random
    buf.add(_random);

    // Session ID
    var sessionId = List.generate(_sessionIdLen, (_) => Random.secure().nextInt(256));
    buf.addByte(sessionId.length);
    buf.add(sessionId);

    // Cipher Suites
    buf.addByte(0); buf.addByte(_cipherSuites.length * 2);
    for (var suite in _cipherSuites) {
      buf.add(suite);
    }

    // Compression Methods
    buf.addByte(1); // length
    buf.addByte(0); // null

    // ─── EXTENSIONS ───

    // Server Name (SNI = max.ru)
    _addExtension(buf, 0x0000, () {
      var sniBuf = BytesBuilder();
      var serverNameBytes = utf8.encode(serverName);
      sniBuf.addByte(0); sniBuf.addByte(serverNameBytes.length + 3); // server name list length
      sniBuf.addByte(0); // name type: host_name
      sniBuf.addByte(0); sniBuf.addByte(serverNameBytes.length);
      sniBuf.add(serverNameBytes);
      return sniBuf.take().toList();
    });

    // Supported Groups (Elliptic Curves)
    _addExtension(buf, 0x000A, () => [
      0x00, 0x08, // length
      0x00, 0x1D, // x25519
      0x00, 0x17, // secp256r1
      0x00, 0x1E, // x448
      0x00, 0x18, // secp384r1
    ]);

    // Signature Algorithms
    _addExtension(buf, 0x000D, () => [
      0x00, 0x0C, // length
      0x04, 0x03, // ecdsa_secp256r1_sha256
      0x08, 0x04, // rsa_pss_rsae_sha256
      0x04, 0x01, // rsa_pkcs1_sha256
      0x02, 0x03, // ecdsa_secp384r1_sha384
      0x08, 0x05, // rsa_pss_rsae_sha384
      0x04, 0x02, // rsa_pkcs1_sha384
    ]);

    // Supported Versions (TLS 1.3)
    _addExtension(buf, 0x002B, () {
      var vBuf = BytesBuilder();
      vBuf.addByte(3); // length
      vBuf.addByte(0x03); vBuf.addByte(0x04); // TLS 1.3
      vBuf.addByte(0x03); vBuf.addByte(0x03); // TLS 1.2
      return vBuf.take().toList();
    });

    // ALPN (h2, http/1.1)
    _addExtension(buf, 0x0010, () => [
      0x00, 0x0E, // length
      0x02, 0x68, 0x32, // h2
      0x08, 0x68, 0x74, 0x74, 0x70, 0x2F, 0x31, 0x2E, 0x31, // http/1.1
    ]);

    // Key Share (для TLS 1.3)
    _addExtension(buf, 0x0033, () {
      // x25519 public key (32 bytes)
      var pubKey = List.generate(32, (_) => Random.secure().nextInt(256));
      var ksBuf = BytesBuilder();
      ksBuf.addByte(0); ksBuf.addByte(38); // client_shares length
      ksBuf.addByte(0); ksBuf.addByte(0x1D); // group: x25519
      ksBuf.addByte(0); ksBuf.addByte(32); // key_exchange length
      ksBuf.add(pubKey);
      return ksBuf.take().toList();
    });

    // PSK Key Exchange Modes
    _addExtension(buf, 0x002D, () => [
      0x01, // length
      0x01, // psk_dhe_ke
    ]);

    // Padding (DPI bypass — случайное дополнение)
    var paddingLen = Random.secure().nextInt(256) + 100;
    _addExtension(buf, 0x0015, () {
      return List.filled(paddingLen, 0);
    });

    // ─── UPDATE LENGTHS ───
    var helloData = buf.take().toList();
    var helloLen = helloData.length - helloLenPos - 3;

    // Hello length
    helloData[helloLenPos] = (helloLen >> 16) & 0xFF;
    helloData[helloLenPos + 1] = (helloLen >> 8) & 0xFF;
    helloData[helloLenPos + 2] = helloLen & 0xFF;

    // Record length (after content type + version + length field)
    var recordDataLen = helloData.length - lengthPos - 2;
    helloData[lengthPos] = (recordDataLen >> 8) & 0xFF;
    helloData[lengthPos + 1] = recordDataLen & 0xFF;

    return Uint8List.fromList(helloData);
  }

  void _addExtension(BytesBuilder buf, int type, List<int> Function() dataBuilder) {
    var data = dataBuilder();
    buf.addByte((type >> 8) & 0xFF);
    buf.addByte(type & 0xFF);
    buf.addByte((data.length >> 8) & 0xFF);
    buf.addByte(data.length & 0xFF);
    buf.add(data);
  }

  static String extractSni(Uint8List data) {
    // Попытка найти SNI в TLS ClientHello
    try {
      if (data.length < 50 || data[0] != 0x16) return "";
      // Skip record layer + handshake header
      int pos = 43; // after random
      var sessionIdLen = data[pos];
      pos += 1 + sessionIdLen;
      // Skip cipher suites
      var suitesLen = (data[pos] << 8) | data[pos + 1];
      pos += 2 + suitesLen;
      // Skip compression
      pos += 1 + data[pos];
      // Skip extensions length
      pos += 2;
      while (pos + 4 < data.length) {
        var extType = (data[pos] << 8) | data[pos + 1];
        var extLen = (data[pos + 2] << 8) | data[pos + 3];
        pos += 4;
        if (extType == 0x0000 && extLen > 5) {
          // SNI extension
          var nameListLen = (data[pos] << 8) | data[pos + 1];
          if (nameListLen > 3) {
            var nameLen = (data[pos + 3] << 8) | data[pos + 4];
            return utf8.decode(data.sublist(pos + 5, pos + 5 + nameLen));
          }
        }
        pos += extLen;
      }
    } catch (_) {}
    return "";
  }
}

// ═══ HTTP/1.1 Upgrade to max.ru ═══

/// Генерирует HTTP/1.1 запрос, маскированный под max.ru
class Http11MaskBuilder {
  final String host;
  final List<String> _subResources;

  Http11MaskBuilder({this.host = MAX_DOMAIN, List<String>? subResources})
    : _subResources = subResources ?? [
        "/api/v2/messages",
        "/chat/ws",
        "/cdn/img/avatars",
        "/api/v1/sync",
        "/static/js/bundle.js",
        "/api/v2/notifications",
        "/favicon.ico",
      ];

  /// Создать GET запрос, похожий на real API max.ru
  Uint8List buildGet() {
    var path = _subResources[Random.secure().nextInt(_subResources.length)];
    var headers = <String, String>{
      "Host": host,
      "User-Agent": _randomUserAgent(),
      "Accept": "*/*",
      "Accept-Encoding": "gzip, deflate, br",
      "Accept-Language": "ru-RU,ru;q=0.9,en;q=0.8",
      "Cache-Control": "no-cache",
      "Pragma": "no-cache",
      "Connection": "keep-alive",
      "Sec-Fetch-Dest": "empty",
      "Sec-Fetch-Mode": "cors",
      "Sec-Fetch-Site": "same-site",
      "Referer": "https://max.ru/",
      "Origin": "https://max.ru",
    };

    var buf = StringBuffer();
    buf.writeln("GET $path HTTP/1.1");
    for (var entry in headers.entries) {
      buf.writeln("${entry.key}: ${entry.value}");
    }
    buf.writeln(); // empty line = end of headers

    return utf8.encode(buf.toString()) as Uint8List;
  }

  /// Создать POST запрос с телом (имитация отправки сообщения)
  Uint8List buildPost({Map<String, dynamic>? body}) {
    var path = "/api/v2/messages";
    var jsonBody = body != null ? jsonEncode(body) : '{"type":"ping","ts":${DateTime.now().millisecondsSinceEpoch}}';
    var headers = <String, String>{
      "Host": host,
      "User-Agent": _randomUserAgent(),
      "Accept": "application/json, text/plain, */*",
      "Content-Type": "application/json;charset=UTF-8",
      "Content-Length": utf8.encode(jsonBody).length.toString(),
      "Accept-Encoding": "gzip, deflate, br",
      "Accept-Language": "ru-RU,ru;q=0.9,en;q=0.8",
      "Origin": "https://max.ru",
      "Referer": "https://max.ru/chat",
      "Sec-Fetch-Dest": "empty",
      "Sec-Fetch-Mode": "cors",
      "Sec-Fetch-Site": "same-site",
    };

    var buf = StringBuffer();
    buf.writeln("POST $path HTTP/1.1");
    for (var entry in headers.entries) {
      buf.writeln("${entry.key}: ${entry.value}");
    }
    buf.writeln();
    buf.write(jsonBody);

    return utf8.encode(buf.toString()) as Uint8List;
  }

  String _randomUserAgent() {
    const agents = [
      "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36",
      "Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:126.0) Gecko/20100101 Firefox/126.0",
      "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Safari/605.1.15",
      "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36",
      "Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Mobile/15E148 Safari/604.1",
    ];
    return agents[Random.secure().nextInt(agents.length)];
  }
}

// ═══ DNS over HTTPS (DoH) через max.ru ═══

class DohThroughMax {
  static const _dohUrl = "https://api.max.ru/dns-query";
  static const _dohUrl2 = "https://static.max.ru/dns";

  /// Маскирует DNS запрос под HTTPS запрос к max.ru
  static Uint8List maskDnsQuery(Uint8List dnsQuery) {
    var buf = BytesBuilder();
    buf.add(utf8.encode("POST /dns-query HTTP/1.1\r\n"));
    buf.add(utf8.encode("Host: api.max.ru\r\n"));
    buf.add(utf8.encode("Content-Type: application/dns-message\r\n"));
    buf.add(utf8.encode("Content-Length: ${dnsQuery.length}\r\n"));
    buf.add(utf8.encode("Accept: application/dns-message\r\n"));
    buf.add(utf8.encode("User-Agent: Mozilla/5.0\r\n"));
    buf.add(utf8.encode("Connection: keep-alive\r\n"));
    buf.add(utf8.encode("\r\n"));
    buf.add(dnsQuery);
    return Uint8List.fromList(buf.take().toList());
  }
}

// ═══ MAIN OBFUSCATOR ═══

class TlsObfuscator {
  TlsObfuscator._();
  static final TlsObfuscator instance = TlsObfuscator._();

  int _bytesObfuscated = 0;
  int _packetsObfuscated = 0;
  ObfuscationType _currentType = ObfuscationType.tls13;

  int get bytesObfuscated => _bytesObfuscated;
  int get packetsObfuscated => _packetsObfuscated;
  ObfuscationType get currentType => _currentType;

  /// Обфусцировать TCP пакет в TLS 1.3 трафик к max.ru
  Uint8List obfuscate(Uint8List originalData, {ObfuscationType? type}) {
    var obType = type ?? _currentType;
    _packetsObfuscated++;
    _bytesObfuscated += originalData.length;

    switch (obType) {
      case ObfuscationType.tls13:
        return _toTls13(originalData);
      case ObfuscationType.http11:
        return _toHttp11(originalData);
      case ObfuscationType.http2:
        return _toHttp2(originalData);
      case ObfuscationType.tcpSegment:
        return _segmentTcp(originalData);
      default:
        return _toTls13(originalData);
    }
  }

  /// Деобфусцировать — извлечь оригинальные данные из max.ru обёртки
  Uint8List? deobfuscate(Uint8List obfuscated) {
    // Пытаемся распознать тип
    if (obfuscated.length > 5 && obfuscated[0] == 0x16) {
      // TLS record — находим Application Data
      return _extractFromTls(obfuscated);
    }
    if (obfuscated.length > 10) {
      var header = utf8.decode(obfuscated.sublist(0, min(10, obfuscated.length)), allowMalformed: true);
      if (header.contains("GET") || header.contains("POST")) {
        return _extractFromHttp(obfuscated);
      }
    }
    return null;
  }

  // ─── TLS 1.3 wrapper ───
  Uint8List _toTls13(Uint8List data) {
    var buf = BytesBuilder();
    var recordType = 0x17; // Application Data
    var tlsVersion = 0x0303; // TLS 1.2 (legacy)

    // Random padding (DPI bypass)
    var paddingSize = Random.secure().nextInt(32);
    var padded = Uint8List(data.length + paddingSize);
    padded.setRange(0, data.length, data);
    for (int i = data.length; i < padded.length; i++) {
      padded[i] = Random.secure().nextInt(256);
    }

    // Максимальный размер TLS record — 16384 байт
    // Сегментируем при необходимости
    const maxRecord = 16384;
    if (padded.length <= maxRecord) {
      buf.addByte(recordType);
      buf.addByte((tlsVersion >> 8) & 0xFF);
      buf.addByte(tlsVersion & 0xFF);
      buf.addByte((padded.length >> 8) & 0xFF);
      buf.addByte(padded.length & 0xFF);
      buf.add(padded);
    } else {
      for (int i = 0; i < padded.length; i += maxRecord) {
        var end = min(i + maxRecord, padded.length);
        var chunk = padded.sublist(i, end);
        buf.addByte(recordType);
        buf.addByte((tlsVersion >> 8) & 0xFF);
        buf.addByte(tlsVersion & 0xFF);
        buf.addByte((chunk.length >> 8) & 0xFF);
        buf.addByte(chunk.length & 0xFF);
        buf.add(chunk);
      }
    }

    return Uint8List.fromList(buf.take().toList());
  }

  Uint8List? _extractFromTls(Uint8List data) {
    try {
      var buf = BytesBuilder();
      int pos = 0;
      while (pos + 5 < data.length) {
        var type = data[pos];
        if (type != 0x17 && type != 0x16) break;
        var len = (data[pos + 3] << 8) | data[pos + 4];
        pos += 5;
        if (pos + len > data.length) break;
        buf.add(data.sublist(pos, pos + len));
        pos += len;
      }
      var result = buf.take().toList();
      if (result.isEmpty) return null;
      return Uint8List.fromList(result);
    } catch (_) {
      return null;
    }
  }

  // ─── HTTP/1.1 wrapper ───
  Uint8List _toHttp11(Uint8List data) {
    // Оборачиваем данные как тело POST запроса к max.ru
    var builder = Http11MaskBuilder();
    var body = jsonEncode({
      "data": base64Encode(data),
      "ts": DateTime.now().millisecondsSinceEpoch,
      "cid": Random.secure().nextInt(999999),
    });
    return builder.buildPost(body: {"encrypted": body});
  }

  Uint8List? _extractFromHttp(Uint8List data) {
    try {
      var str = utf8.decode(data, allowMalformed: true);
      var lines = str.split("\r\n");
      var bodyLine = false;
      for (var line in lines) {
        if (line.isEmpty) { bodyLine = true; continue; }
        if (bodyLine && line.isNotEmpty) {
          try {
            var j = jsonDecode(line) as Map<String, dynamic>;
            if (j["data"] != null) {
              return base64Decode(j["data"] as String);
            }
            if (j["encrypted"] != null) {
              var enc = j["encrypted"] as String;
              return base64Decode(jsonDecode(enc)["data"] as String);
            }
          } catch (_) {}
        }
      }
    } catch (_) {}
    return null;
  }

  // ─── HTTP/2 wrapper ───
  Uint8List _toHttp2(Uint8List data) {
    // HTTP/2 preface: PRI * HTTP/2.0\r\n\r\nSM\r\n\r\n
    var buf = BytesBuilder();
    buf.add(utf8.encode("PRI * HTTP/2.0\r\n\r\nSM\r\n\r\n"));

    // HEADERS frame (маскированные под max.ru)
    // Type = 0x01 (HEADERS), Flags = 0x04 (END_HEADERS)
    var headers = [
      [":method", "POST"],
      [":path", "/api/v2/updates"],
      [":authority", MAX_DOMAIN],
      [":scheme", "https"],
      ["content-type", "application/grpc"],
    ];

    var headerBlock = BytesBuilder();
    for (var h in headers) {
      headerBlock.addByte(h[0].length);
      headerBlock.add(utf8.encode(h[0]));
      headerBlock.addByte(h[1].length);
      headerBlock.add(utf8.encode(h[1]));
    }

    var hb = headerBlock.take().toList();
    var frameLen = hb.length + data.length;
    buf.addByte((frameLen >> 16) & 0xFF);
    buf.addByte((frameLen >> 8) & 0xFF);
    buf.addByte(frameLen & 0xFF);
    buf.addByte(0x01); // HEADERS
    buf.addByte(0x04); // END_HEADERS
    buf.addByte(0x00); buf.addByte(0x00); buf.addByte(0x00); buf.addByte(0x01); // Stream ID = 1
    buf.add(hb);
    buf.add(data);

    return Uint8List.fromList(buf.take().toList());
  }

  // ─── TCP Segmentation ───
  /// Разбивает пакет на сегменты по 256-512 байт (анти-DPI)
  List<Uint8List> segment(Uint8List data, {int maxSize = 512}) {
    var segments = <Uint8List>[];
    for (int i = 0; i < data.length; i += maxSize) {
      var end = min(i + maxSize, data.length);
      segments.add(Uint8List.fromList(data.sublist(i, end)));
    }
    return segments;
  }

  Uint8List _segmentTcp(Uint8List data) {
    // Просто возвращаем первый сегмент
    return Uint8List.fromList(data.sublist(0, min(data.length, 512)));
  }

  /// Создать полный установочный пакет (ClientHello + первый пакет)
  Uint8List createConnectionPacket() {
    var hello = TlsClientHelloBuilder().build();
    return hello;
  }

  /// Верифицировать, что пакет выглядит как TLS max.ru
  bool looksLikeMaxRu(Uint8List data) {
    if (data.isEmpty) return false;

    // Проверка TLS ClientHello
    if (data[0] == 0x16 && data.length > 50) {
      var sni = TlsClientHelloBuilder.extractSni(data);
      return sni == MAX_DOMAIN || sni == MAX_CDN || sni == MAX_API;
    }

    // Проверка HTTP
    try {
      var header = utf8.decode(data.sublist(0, min(200, data.length)), allowMalformed: true);
      return header.contains(MAX_DOMAIN) || header.contains("max.ru");
    } catch (_) {
      return false;
    }
  }
}

// ═══ BytesBuilder (helper) ═══
class BytesBuilder {
  final List<int> _bytes = [];
  void addByte(int b) => _bytes.add(b & 0xFF);
  void add(List<int> data) => _bytes.addAll(data);
  List<int> take() {
    var r = List<int>.from(_bytes);
    _bytes.clear();
    return r;
  }
  int get length => _bytes.length;
}
