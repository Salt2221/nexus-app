// ═══════════════════════════════════════════════════════════════
// NEXUS Global P2P Node — ядро децентрализованной сети
//
//  Использует dht_network.dart (NodeId, Peer, Message, Shard,
//  KBucket, TransportLayer) как базовые типы.
// ═══════════════════════════════════════════════════════════════

import "dart:async";
import "dart:convert";
import "dart:io";
import "dart:math";
import "package:flutter/foundation.dart";
import "dht_network.dart";

// ═══════════════════════════════════════════════════════════════
// GlobalP2PNode — главный класс
// ═══════════════════════════════════════════════════════════════
class GlobalP2PNode extends ChangeNotifier {
  final NodeId nodeId;
  final int port;
  final List<Peer> seeds;

  // Транспорт
  final TransportLayer transport = TransportLayer();

  // Маршрутизация
  final List<KBucket> buckets;
  final Map<int, Shard> shards = {};
  final Map<int, bool> seen = {}; // dedup
  final Map<String, RelayChain> activeRelays = {};

  // Состояние
  bool _running = false;
  int sent = 0, recv = 0, routed = 0;
  Timer? _refreshTimer, _cleanupTimer, _keepAliveTimer;

  // Callbacks
  void Function(Message msg, Peer from)? onMessage;
  void Function(Peer peer)? onPeerJoin;
  void Function(Peer peer)? onPeerLeave;

  GlobalP2PNode({
    NodeId? nodeId,
    this.port = DEFAULT_PORT,
    List<Peer>? seeds,
  }) : nodeId = nodeId ?? NodeId.random(),
       buckets = List.generate(BITS, (_) => KBucket(0)),
       seeds = seeds ?? [];

  // ══ Геттеры ══
  bool get running => _running;
  int get peerCount => buckets.fold(0, (s, b) => s + b.peers.length);
  String get transportName => transport.name;
  int get shardCount => shards.length;
  /// Register in P2P network
  Future<void> register(String identity) async {
    if (!_running) await start();
    debugPrint("[P2P] Registered: $identity");
    notifyListeners();
  }

  List<Peer> get allPeers {
    final seen = <String>{};
    final list = <Peer>[];
    for (var b in buckets) {
      for (var p in b.peers) {
        if (seen.add(p.id.toHex())) list.add(p);
      }
    }
    return list;
  }

  // ══ ЗАПУСК ══
  Future<bool> start() async {
    if (_running) return true;

    final ok = await transport.start(port);
    if (!ok) {
      debugPrint("[P2P] No transport available");
      return false;
    }

    _running = true;

    // Приём пакетов
    transport.onPacket = (data, addr, rport) {
      final msgs = Message.fromMaxRuPacket(data);
      if (msgs == null) return;
      final sender = _findOrCreatePeer(addr, rport, msgs.first.sender);
      addPeer(sender);
      for (var msg in msgs) handleMessage(msg, sender);
    };

    // Bootstrap к seed-нодам
    for (var seed in seeds) {
      addPeer(seed);
      send(Message(type: "CONNECT", sender: nodeId), seed);
    }
    iterativeFind(nodeId);

    // Фоновые задачи
    _refreshTimer = Timer.periodic(const Duration(minutes: 30), (_) {
      iterativeFind(nodeId);
      _announceShard();
    });
    _cleanupTimer = Timer.periodic(const Duration(minutes: 5), (_) {
      for (var b in buckets) b.cleanup();
      activeRelays.removeWhere((_, r) => r.expired);
    });
    _keepAliveTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      for (var p in allPeers.take(5)) {
        send(Message(type: "PING", sender: nodeId), p);
      }
    });

    notifyListeners();
    debugPrint("[P2P] Node ${nodeId} started on :$port via ${transport.name}");
    return true;
  }

  void stop() {
    _running = false;
    _refreshTimer?.cancel();
    _cleanupTimer?.cancel();
    _keepAliveTimer?.cancel();
    transport.stop();
    activeRelays.clear();
    notifyListeners();
  }

  // ══ ОТПРАВКА ══
  Future<bool> send(Message msg, Peer peer) async {
    if (!_running) return false;
    final packet = msg.toMaxRuPacket();
    final ok = await transport.send(packet, peer.address, peer.port);
    if (ok) sent++;
    else peer.markFailed();
    return ok;
  }

  Future<bool> sendViaRelay(Message msg, NodeId targetId) async {
    if (!_running) return false;
    final relays = allPeers
      .where((p) => p.online && p.id != targetId && p.id != nodeId)
      .toList()..shuffle(Random.secure());

    for (var relay in relays.take(3)) {
      msg.relayFor ??= targetId;
      final packet = msg.toMaxRuPacket();
      try {
        final sock = await Socket.connect(relay.address, relay.port,
          timeout: const Duration(seconds: 3));
        sock.add(packet); await sock.flush(); sock.close();
        sent++; routed++;
        return true;
      } catch (_) {}
    }
    return false;
  }

  // ══ ПРИЁМ И ОБРАБОТКА ══
  void handleMessage(Message msg, Peer sender) {
    recv++;

    // Dedup
    if (seen.containsKey(msg.seq)) return;
    seen[msg.seq] = true;
    if (seen.length > 10000) {
      final keys = seen.keys.toList()..sort();
      for (int i = 0; i < keys.length - 5000; i++) seen.remove(keys[i]);
    }

    // Relay
    if (msg.relayFor != null && msg.relayFor != nodeId && msg.ttl > 0) {
      final target = findPeer(msg.relayFor!);
      if (target != null) { send(msg, target); routed++; return; }
    }

    switch (msg.type) {
      case "PING":
        send(Message(type: "PONG", sender: nodeId, target: msg.sender), sender);
        break;
      case "PONG":
        sender.markSeen();
        break;

      case "CONNECT":
        addPeer(sender);
        onPeerJoin?.call(sender);
        send(Message(type: "CONNECT_OK", sender: nodeId, data: {
          "id": nodeId.toHex(), "shards": shards.keys.toList(),
          "peers": peerCount, "transport": transportName,
        }), sender);
        gossip({"event": "peer_join", "node": sender.id.toHex()}, sender);
        break;

      case "CONNECT_OK":
        sender.markSeen();
        if (msg.data != null) {
          debugPrint("[P2P] Connected to ${sender.id}, network: ${msg.data!["peers"]} peers");
        }
        break;

      case "FIND_NODE":
      case "GLOBAL_LOOKUP":
        if (msg.target != null) {
          final nearest = nearestPeers(msg.target!, K);
          send(Message(type: "NODES", sender: nodeId, target: msg.target,
            data: {"nodes": nearest.map((p) => p.toJson()).toList()}), sender);
        }
        break;

      case "NODES":
        if (msg.data?["nodes"] != null) {
          for (var n in (msg.data!["nodes"] as List)) {
            try { addPeer(Peer.fromJson(n)); } catch (_) {}
          }
        }
        break;

      case "NAT_HOLE":
        if (msg.data?["target_id"] != null) {
          final tid = NodeId.fromHex(msg.data!["target_id"]);
          final tp = findPeer(tid);
          if (tp != null) send(Message(type: "PING", sender: nodeId), tp);
        }
        break;

      case "NAT_HOLE_OK":
        sender.markSeen();
        debugPrint("[P2P] NAT hole punch OK for ${sender.id}");
        break;

      case "SHARD_INFO":
        if (msg.data?["shard"] != null) {
          final sd = msg.data!["shard"] as Map<String, dynamic>;
          final sid = sd["id"] as int;
          shards.putIfAbsent(sid, () => Shard(sid));
          if (sd["members"] != null) {
            for (var m in (sd["members"] as List)) {
              try { shards[sid]!.add(Peer.fromJson(m)); } catch (_) {}
            }
          }
        }
        break;

      case "RELAY":
        if (msg.relayFor != null && msg.data?["payload"] != null) {
          final target = findPeer(msg.relayFor!);
          if (target != null) {
            final relayed = Message(
              type: "RELAYED", sender: msg.sender,
              target: msg.relayFor, data: {"payload": msg.data!["payload"]},
            );
            send(relayed, target);
            routed++;
          }
        }
        break;

      case "GOSSIP":
        if (msg.data != null && msg.ttl > 0) {
          onMessage?.call(msg, sender);
          final others = allPeers
            .where((p) => p.id != sender.id && p.id != nodeId)
            .toList()..shuffle(Random.secure());
          for (var p in others.take(GOSSIP_FANOUT)) {
            send(Message(type: "GOSSIP", sender: msg.sender,
              data: msg.data, ttl: msg.ttl - 1, seq: msg.seq), p);
          }
        }
        break;

      default:
        onMessage?.call(msg, sender);
    }
  }

  // ══ УПРАВЛЕНИЕ ПИРАМИ ══
  void addPeer(Peer p) {
    if (p.id == nodeId) return;
    final bi = nodeId.leadingZeroBits(p.id);
    if (bi >= BITS) return;

    if (!buckets[bi].add(p)) {
      final oldest = buckets[bi].peers.first;
      send(Message(type: "PING", sender: nodeId), oldest);
    }

    final sid = p.shardId;
    shards.putIfAbsent(sid, () => Shard(sid));
    shards[sid]!.add(p);
  }

  Peer _findOrCreatePeer(InternetAddress addr, int rport, NodeId id) {
    for (var b in buckets) { final f = b.find(id); if (f != null) return f; }
    return Peer(id: id, address: addr, port: rport);
  }

  Peer? findPeer(NodeId id) {
    for (var b in buckets) { final f = b.find(id); if (f != null) return f; }
    return null;
  }

  List<Peer> nearestPeers(NodeId target, int count) {
    final all = allPeers;
    all.sort((a, b) => a.id.distanceTo(target).compareTo(b.id.distanceTo(target)));
    return all.take(count).toList();
  }

  // ═══ ITERATIVE LOOKUP ═══
  Future<List<Peer>> iterativeFind(NodeId target) async {
    final queried = <String>{};
    var closest = nearestPeers(target, K);

    for (int r = 0; r < 8; r++) {
      closest.sort((a, b) => a.id.distanceTo(target).compareTo(b.id.distanceTo(target)));
      final toQ = closest.where((p) => queried.add(p.id.toHex())).take(ALPHA).toList();
      if (toQ.isEmpty) break;

      final results = await Future.wait(toQ.map((p) => _findNodeReq(p, target)));
      for (var peers in results) {
        for (var peer in peers) {
          if (!closest.any((c) => c.id == peer.id)) { closest.add(peer); addPeer(peer); }
        }
      }

      if (closest.isNotEmpty && closest.first.id == toQ.first.id) break;
    }

    return closest.take(K).toList();
  }

  Future<List<Peer>> _findNodeReq(Peer peer, NodeId target) async {
    final completer = Completer<List<Peer>>();
    final peers = <Peer>[];
    final handler = (Message msg, Peer from) {
      if (msg.type == "NODES" && msg.data?["nodes"] != null && !completer.isCompleted) {
        for (var n in (msg.data!["nodes"] as List)) {
          try { peers.add(Peer.fromJson(n)); } catch (_) {}
        }
        completer.complete(peers);
      }
    };
    onMessage = handler;
    send(Message(type: "FIND_NODE", sender: nodeId, target: target), peer);
    Timer(const Duration(seconds: 4), () {
      if (!completer.isCompleted) completer.complete(peers);
    });
    return completer.future;
  }

  // ═══ NAT HOLE PUNCH ═══
  Future<bool> natHolePunch(Peer target) async {
    if (!_running) return false;

    // Просим известных пиров постучать к target
    final relays = allPeers.where((p) => p.online && p.id != target.id && p.id != nodeId).toList();
    if (relays.isEmpty) return false;

    for (var relay in relays.take(3)) {
      send(Message(type: "NAT_HOLE", sender: nodeId,
        data: {"target_id": target.id.toHex()}), relay);
    }

    // Сами стучимся
    for (int i = 0; i < 5; i++) {
      send(Message(type: "PING", sender: nodeId), target);
      await Future.delayed(const Duration(milliseconds: 200));
    }

    debugPrint("[P2P] NAT hole punch to ${target.id}");
    return true;
  }

  // ═══ GOSSIP ═══
  void gossip(Map<String, dynamic> data, [Peer? exclude]) {
    final others = allPeers
      .where((p) => p.id != exclude?.id && p.id != nodeId)
      .toList()..shuffle(Random.secure());
    for (var p in others.take(GOSSIP_FANOUT)) {
      send(Message(type: "GOSSIP", sender: nodeId, data: data), p);
    }
  }

  // ═══ SHARD ═══
  void _announceShard() {
    final myShard = shards.putIfAbsent(nodeId.shardId, () => Shard(nodeId.shardId));
    final info = Message(type: "SHARD_INFO", sender: nodeId,
      data: {"shard": myShard.toJson()});
    for (var p in allPeers.take(10)) send(info, p);
  }

  // ═══ RELAY CHAIN ═══
  Future<RelayChain?> createRelayChain(NodeId target) async {
    final path = <NodeId>[];
    var current = nodeId;

    for (int i = 0; i < 5; i++) {
      final nearest = nearestPeers(target, 3)
        .where((p) => !path.contains(p.id) && p.id != current)
        .toList();
      if (nearest.isEmpty) break;
      final next = nearest.first;
      path.add(next.id);
      current = next.id;
      if (current.distanceTo(target) < BigInt.from(1000)) break;
    }

    if (path.isEmpty) return null;
    final chain = RelayChain(origin: nodeId, destination: target, relays: path);
    activeRelays[target.toHex()] = chain;
    debugPrint("[P2P] Relay chain created: ${path.length} hops");
    return chain;
  }

  // ═══ ЭСКАЛАЦИЯ ТРАНСПОРТА ═══
  void escalateTransport() {
    transport.escalate();
    notifyListeners();
  }

  // ═══ СТАТУС ═══
  Map<String, dynamic> getStatus() => {
    "id": nodeId.toHex(),
    "running": _running,
    "transport": transportName,
    "peers": peerCount,
    "shards": shardCount,
    "sent": sent,
    "recv": recv,
    "routed": routed,
  };

  String get statusString => "[P2P] ${nodeId} | $transportName | $peerCount peers | $shardCount shards | ↑$sent ↓$recv ↻$routed";

  @override
  void dispose() { stop(); super.dispose(); }
}

// ═══════════════════════════════════════════════════════════════
// RelayChain
// ═══════════════════════════════════════════════════════════════
class RelayChain {
  final NodeId origin;
  final NodeId destination;
  final List<NodeId> relays;
  final int createdAt;
  bool active = true;

  RelayChain({
    required this.origin, required this.destination,
    List<NodeId>? relays,
  }) : relays = relays ?? [], createdAt = DateTime.now().millisecondsSinceEpoch;

  int get hops => relays.length;
  bool get expired => DateTime.now().millisecondsSinceEpoch - createdAt > 120000;
}

// ═══════════════════════════════════════════════════════════════
// DhtNetworkManager — совместимый синглтон для старого кода
// ═══════════════════════════════════════════════════════════════
class DhtNetworkManager extends ChangeNotifier {
  DhtNetworkManager._();
  static final DhtNetworkManager instance = DhtNetworkManager._();

  GlobalP2PNode? _node;
  bool _initialized = false;

  bool get initialized => _initialized;
  bool get running => _node?.running ?? false;
  int get peers => _node?.peerCount ?? 0;
  GlobalP2PNode? get node => _node;

  Future<bool> init({List<Peer>? seeds, int port = DEFAULT_PORT}) async {
    if (_initialized) return true;
    try {
      _node = GlobalP2PNode(seeds: seeds, port: port);
      final ok = await _node!.start();
      _initialized = ok;
      notifyListeners();
      return ok;
    } catch (e) {
      debugPrint("[DHT-MGR] init fail: $e");
      return false;
    }
  }

  Future<void> register(String identity) async {
    await init();
    if (_node != null) await _node!.register(identity);
  }

  @override
  void dispose() { _node?.dispose(); _node = null; _initialized = false; super.dispose(); }

  Future<bool> store(String key, dynamic value) async {
    if (_node == null || !_node!.running) return false;
    final kid = NodeId.fromData(utf8.encode(key));
    final closest = await _node!.iterativeFind(kid);
    int n = 0;
    for (var p in closest.take(5)) {
      _node!.send(Message(type: "STORE", sender: _node!.nodeId,
        target: kid, data: {"value": value}), p);
      n++;
    }
    return n > 0;
  }

  Future<dynamic> find(String key) async {
    if (_node == null || !_node!.running) return null;
    final kid = NodeId.fromData(utf8.encode(key));
    final completer = Completer<dynamic>();
    dynamic found;

    _node!.onMessage = (msg, from) {
      if (msg.type == "VALUE" && msg.data?["value"] != null && !completer.isCompleted) {
        found = msg.data!["value"];
        completer.complete(found);
      }
    };

    final closest = await _node!.iterativeFind(kid);
    for (var p in closest) {
      _node!.send(Message(type: "FIND_VALUE", sender: _node!.nodeId, target: kid), p);
    }

    Timer(const Duration(seconds: 5), () {
      if (!completer.isCompleted) completer.complete(null);
    });

    return completer.future;
  }
}
