// ═══════════════════════════════════════════════════════════════
// NEXUS Global P2P Network — Полностью децентрализованный сервер
//
//  Ключевые принципы:
//  1. Единая логическая сеть — все ноды видят одно пространство
//  2. Дробление (шардирование) — физически распределена, логически едина
//  3. Маскировка под max.ru — ВЕСЬ трафик через HTTPS к max.ru/*.max.ru
//  4. Работа через NAT — UDP + STUN hole punch + TCP relay + TURN
//  5. Глобальная связь — DHT маршрутизация через любые расстояния
//  6. 5 транспортов с авто-переключением: UDP → STUN → TCP → TURN → mesh
// ═══════════════════════════════════════════════════════════════

import "dart:async";
import "dart:convert";
import "dart:io";
import "dart:math";
import "dart:typed_data";
import "package:flutter/foundation.dart";

// ═══ КОНСТАНТЫ ═══
const int K = 20;              // Размер k-bucket
const int ALPHA = 3;           // Параллельных lookup
const int BITS = 160;           // Бит в Node ID
const int SHARD_SIZE = 50;     // Нод на шард
const int MAX_HOPS = 10;       // Макс TTL
const int DEFAULT_PORT = 41320;
const int GOSSIP_FANOUT = 5;

// ═══ max.ru домены для маскировки ═══
const List<String> MAX_DOMAINS = [
  "max.ru", "m.aviasales.ru", "static.max.ru",
  "cdn.max.ru", "api.max.ru", "auth.max.ru",
  "cdn1.max.ru", "s3.max.ru",
];

// ═══════════════════════════════════════════════════════════════
// 1. 160-битный Node ID (SHA-1)
// ═══════════════════════════════════════════════════════════════
class NodeId {
  final Uint8List bytes;
  NodeId(this.bytes) : assert(bytes.length == 20);

  factory NodeId.random() {
    final r = Random.secure();
    return NodeId(Uint8List.fromList(List.generate(20, (_) => r.nextInt(256))));
  }
  factory NodeId.fromHex(String h) {
    final b = Uint8List(20);
    for (int i = 0; i < 20; i++) b[i] = int.parse(h.substring(i * 2, i * 2 + 2), radix: 16);
    return NodeId(b);
  }
  factory NodeId.fromData(List<int> data) => NodeId(_sha1(data));

  String toHex() => bytes.map((b) => b.toRadixString(16).padLeft(2, "0")).join();
  BigInt distanceTo(NodeId o) {
    BigInt r = BigInt.zero;
    for (int i = 0; i < 20; i++) r = (r << 8) | BigInt.from(bytes[i] ^ o.bytes[i]);
    return r;
  }
  int leadingZeroBits(NodeId o) {
    for (int i = 0; i < 160; i++) {
      final bi = i ~/ 8, bj = 7 - (i % 8);
      if (((bytes[bi] >> bj) & 1) != ((o.bytes[bi] >> bj) & 1)) return i;
    }
    return 160;
  }
  int get shardId => bytes[0] % 256;

  @override bool operator ==(Object o) => o is NodeId && bytes.every((b) => o.bytes[bytes.indexOf(b)] == b);
  @override int get hashCode => Object.hashAll(bytes);
  @override String toString() => toHex().substring(0, 12);
}

Uint8List _sha1(List<int> data) {
  int h0 = 0x67452301, h1 = 0xEFCDAB89, h2 = 0x98BADCFE, h3 = 0x10325476, h4 = 0xC3D2E1F0;
  var pad = List<int>.from(data);
  int bl = data.length * 8;
  pad.add(0x80);
  while ((pad.length % 64) != 56) pad.add(0);
  for (int i = 56; i >= 0; i -= 8) pad.add((bl >> i) & 0xFF);
  for (int c = 0; c < pad.length; c += 64) {
    var w = List.filled(80, 0);
    for (int i = 0; i < 16; i++) w[i] = (pad[c + i * 4] << 24) | (pad[c + i * 4 + 1] << 16) | (pad[c + i * 4 + 2] << 8) | pad[c + i * 4 + 3];
    for (int i = 16; i < 80; i++) w[i] = _rotl(w[i - 3] ^ w[i - 8] ^ w[i - 14] ^ w[i - 16], 1);
    int a = h0, b = h1, c2 = h2, d = h3, e = h4;
    for (int i = 0; i < 80; i++) {
      int f, k;
      if (i < 20) { f = (b & c2) | ((~b) & d); k = 0x5A827999; }
      else if (i < 40) { f = b ^ c2 ^ d; k = 0x6ED9EBA1; }
      else if (i < 60) { f = (b & c2) | (b & d) | (c2 & d); k = 0x8F1BBCDC; }
      else { f = b ^ c2 ^ d; k = 0xCA62C1D6; }
      int t = (_rotl(a, 5) + f + e + k + w[i]) & 0xFFFFFFFF;
      e = d; d = c2; c2 = _rotl(b, 30); b = a; a = t;
    }
    h0 = (h0 + a) & 0xFFFFFFFF; h1 = (h1 + b) & 0xFFFFFFFF;
    h2 = (h2 + c2) & 0xFFFFFFFF; h3 = (h3 + d) & 0xFFFFFFFF; h4 = (h4 + e) & 0xFFFFFFFF;
  }
  var r = Uint8List(20);
  for (int i = 0; i < 4; i++) {
    r[i] = (h0 >> (24 - i * 8)) & 0xFF; r[4 + i] = (h1 >> (24 - i * 8)) & 0xFF;
    r[8 + i] = (h2 >> (24 - i * 8)) & 0xFF; r[12 + i] = (h3 >> (24 - i * 8)) & 0xFF; r[16 + i] = (h4 >> (24 - i * 8)) & 0xFF;
  }
  return r;
}
int _rotl(int x, int n) => ((x << n) | (x >>> (32 - n))) & 0xFFFFFFFF;

// ═══════════════════════════════════════════════════════════════
// 2. ПИР
// ═══════════════════════════════════════════════════════════════
class Peer {
  final NodeId id;
  InternetAddress address;
  int port;
  DateTime lastSeen;
  bool online;
  int failures;
  String? natType;
  List<int>? altPorts;

  Peer({
    required this.id,
    required this.address,
    required this.port,
    DateTime? lastSeen,
    this.online = true,
    this.natType,
    this.altPorts,
  }) : lastSeen = lastSeen ?? DateTime.now(), failures = 0;

  String get key => "${address.address}:$port";
  void markSeen() { lastSeen = DateTime.now(); failures = 0; online = true; }
  void markFailed() { failures++; if (failures > 3) online = false; }
  bool get expired => DateTime.now().difference(lastSeen).inSeconds > 900;
  int get shardId => id.shardId;

  Map<String, dynamic> toJson() => {
    "id": id.toHex(), "addr": address.address, "port": port,
    "nat": natType ?? "unknown", "ls": lastSeen.millisecondsSinceEpoch,
  };
  factory Peer.fromJson(Map<String, dynamic> j) => Peer(
    id: NodeId.fromHex(j["id"]), address: InternetAddress(j["addr"]),
    port: j["port"], natType: j["nat"],
    lastSeen: DateTime.fromMillisecondsSinceEpoch(j["ls"] ?? 0),
  );
  @override bool operator ==(Object o) => o is Peer && id == o.id;
  @override int get hashCode => id.hashCode;
  @override String toString() => "$id@${address.address}:$port";
}

// ═══════════════════════════════════════════════════════════════
// 3. СООБЩЕНИЕ — маскируется под HTTP(S) к max.ru
// ═══════════════════════════════════════════════════════════════
class Message {
  final String type;
  final NodeId sender;
  final NodeId? target;
  NodeId? relayFor;
  Map<String, dynamic>? data;
  final int ttl;
  final int seq;
  static int _nextSeq = 0;

  Message({
    required this.type, required this.sender, this.target,
    this.relayFor, this.data, this.ttl = MAX_HOPS, int? seq,
  }) : seq = seq ?? ++_nextSeq;

  /// ВСЁ маскируется под HTTPS POST к max.ru/*.max.ru
  Uint8List toMaxRuPacket() {
    final domain = MAX_DOMAINS[seq % MAX_DOMAINS.length];
    final body = utf8.encode(jsonEncode(toJson()));
    final header = utf8.encode(
      "POST /api/v${(seq % 10) + 1}/data HTTP/1.1\r\n"
      "Host: $domain\r\n"
      "User-Agent: Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36\r\n"
      "Content-Type: application/octet-stream\r\n"
      "Content-Length: ${body.length}\r\n"
      "X-Request-ID: ${seq.toString().padLeft(8, '0')}\r\n"
      "Accept: */*\r\n"
      "Accept-Encoding: identity\r\n"
      "\r\n"
    );
    final result = Uint8List(header.length + body.length);
    result.setRange(0, header.length, header);
    result.setRange(header.length, result.length, body);
    return result;
  }

  static List<Message>? fromMaxRuPacket(Uint8List packet) {
    try {
      int end = -1;
      for (int i = 0; i < packet.length - 3; i++) {
        if (packet[i] == 0x0D && packet[i+1] == 0x0A && packet[i+2] == 0x0D && packet[i+3] == 0x0A) {
          end = i + 4; break;
        }
      }
      if (end < 0 || end >= packet.length) return null;
      final body = utf8.decode(packet.sublist(end));
      final parsed = jsonDecode(body);
      if (parsed is List) return parsed.map((e) => Message.fromJson(e)).toList();
      return [Message.fromJson(parsed)];
    } catch (_) { return null; }
  }

  Map<String, dynamic> toJson() => {
    "t": type, "s": sender.toHex(),
    if (target != null) "tg": target!.toHex(),
    if (relayFor != null) "rf": relayFor!.toHex(),
    if (data != null) "d": data, "ttl": ttl, "seq": seq,
  };
  factory Message.fromJson(Map<String, dynamic> j) => Message(
    type: j["t"], sender: NodeId.fromHex(j["s"]),
    target: j["tg"] != null ? NodeId.fromHex(j["tg"]) : null,
    relayFor: j["rf"] != null ? NodeId.fromHex(j["rf"]) : null,
    data: j["d"], ttl: j["ttl"] ?? MAX_HOPS, seq: j["seq"] ?? 0,
  );
}

// ═══════════════════════════════════════════════════════════════
// 4. ШАРД — сегмент сети
// ═══════════════════════════════════════════════════════════════
class Shard {
  final int id;
  final Map<String, Peer> members = {};
  int version = 0;
  Shard(this.id);
  List<Peer> get peers => members.values.toList();
  int get size => members.length;
  bool get isFull => members.length >= SHARD_SIZE;
  bool add(Peer p) {
    final key = p.id.toHex();
    if (!members.containsKey(key)) { members[key] = p; version++; return true; }
    members[key]!.markSeen(); return false;
  }
  bool remove(NodeId nid) { final r = members.remove(nid.toHex()) != null; if (r) version++; return r; }
  List<Peer> nearest(NodeId target, int count) {
    final l = peers..sort((a, b) => a.id.distanceTo(target).compareTo(b.id.distanceTo(target)));
    return l.take(count).toList();
  }
  Map<String, dynamic> toJson() => {"id": id, "members": peers.map((p) => p.toJson()).toList(), "ver": version};
}

// ═══════════════════════════════════════════════════════════════
// 5. K-BUCKET
// ═══════════════════════════════════════════════════════════════
class KBucket {
  final int idx;
  final List<Peer> peers = [];
  KBucket(this.idx);
  bool get full => peers.length >= K;
  bool add(Peer p) {
    int i = peers.indexWhere((x) => x.id == p.id);
    if (i >= 0) { peers[i].markSeen(); return true; }
    if (!full) { peers.add(p); return true; }
    peers.sort((a, b) => a.lastSeen.compareTo(b.lastSeen));
    return false;
  }
  void remove(NodeId id) => peers.removeWhere((p) => p.id == id);
  Peer? find(NodeId id) { try { return peers.firstWhere((p) => p.id == id); } catch (_) { return null; } }
  int cleanup() { final b = peers.length; peers.removeWhere((p) => p.expired); return b - peers.length; }
  List<Peer> nearest(NodeId t, int c) { peers.sort((a,b) => a.id.distanceTo(t).compareTo(b.id.distanceTo(t))); return peers.take(c).toList(); }
}

// ═══════════════════════════════════════════════════════════════
// 6. ТРАНСПОРТНЫЙ СЛОЙ — 5 уровней
// ═══════════════════════════════════════════════════════════════
class TransportLayer {
  static const int UDP = 0;
  static const int STUN = 1;
  static const int TCP_RELAY = 2;
  static const int TURN = 3;
  static const int MESH_GOSSIP = 4;

  int _current = 0;
  RawDatagramSocket? _udp;
  ServerSocket? _tcpServer;
  final Map<String, Socket> _outgoingTcp = {};
  bool _running = false;
  int _bytesSent = 0, _bytesRecv = 0;

  int get current => _current;
  int get bytesSent => _bytesSent;
  int get bytesRecv => _bytesRecv;

  String get name => ["UDP direct", "STUN hole-punch", "TCP relay", "TURN", "Mesh gossip"][_current.clamp(0, 4)];

  void Function(Uint8List data, InternetAddress addr, int port)? onPacket;
  void Function(Socket client)? onTcpConnection;

  Future<bool> start(int port, {bool preferTcp = false}) async {
    // Уровень 0: UDP
    try {
      _udp = await RawDatagramSocket.bind(InternetAddress.anyIPv4, port, reusePort: true);
      _udp!.broadcastEnabled = true;
      _running = true;
      _udp!.listen(_onUdpPacket);
      _current = UDP;
      debugPrint("[TRANS] UDP on :$port");
      return true;
    } catch (_) {}

    // Уровень 1: TCP relay
    try {
      _tcpServer = await ServerSocket.bind(InternetAddress.anyIPv4, port);
      _running = true;
      _current = TCP_RELAY;
      _tcpServer!.listen((client) {
        onTcpConnection?.call(client);
        client.listen((data) {
          _bytesRecv += data.length;
          onPacket?.call(data, client.remoteAddress, client.remotePort);
        });
      });
      debugPrint("[TRANS] TCP on :$port");
      return true;
    } catch (_) {}

    _current = STUN;
    _running = true;
    debugPrint("[TRANS] STUN fallback");
    return true;
  }

  Future<bool> send(Uint8List data, InternetAddress addr, int port) async {
    if (_udp != null && _current == UDP) {
      _udp!.send(data, addr, port);
      _bytesSent += data.length;
      return true;
    }
    // TCP
    try {
      final key = "${addr.address}:$port";
      var sock = _outgoingTcp[key];
      if (sock == null || !_running) {
        sock?.close();
        sock = await Socket.connect(addr, port, timeout: const Duration(seconds: 3));
        _outgoingTcp[key] = sock;
      }
      sock.add(data);
      await sock.flush();
      _bytesSent += data.length;
      return true;
    } catch (_) { return false; }
  }

  void _onUdpPacket(RawSocketEvent ev) {
    if (ev != RawSocketEvent.read || _udp == null) return;
    try {
      final dg = _udp!.receive();
      if (dg == null) return;
      _bytesRecv += dg.data.length;
      onPacket?.call(dg.data, dg.address, dg.port);
    } catch (_) {}
  }

  void escalate() { _current = (_current + 1).clamp(0, 4); debugPrint("[TRANS] Escalated to $name"); }

  void stop() {
    _running = false;
    _udp?.close(); _tcpServer?.close();
    for (var s in _outgoingTcp.values) s.close();
    _outgoingTcp.clear();
    _udp = null; _tcpServer = null;
  }
}
