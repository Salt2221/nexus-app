import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'dart:async';
import 'dart:math';

// ════════════════════════════════════════════
// Mesh Network — P2P без интернета
// ════════════════════════════════════════════

class MeshPeer {
  final String id;
  final String name;
  final String? deviceId;
  bool isOnline;

  MeshPeer({required this.id, required this.name, this.deviceId, this.isOnline = true});
}

class MeshPacket {
  final String id;
  final String senderId;
  final String senderName;
  final String content;
  final DateTime timestamp;
  final int ttl;
  final String? originalSenderId;

  MeshPacket({
    required this.id,
    required this.senderId,
    required this.senderName,
    required this.content,
    DateTime? timestamp,
    this.ttl = 3,
    this.originalSenderId,
  }) : timestamp = timestamp ?? DateTime.now();
}

class MeshNetworkManager extends ChangeNotifier {
  static final MeshNetworkManager instance = MeshNetworkManager._();
  MeshNetworkManager._();

  final List<MeshPeer> _peers = [];
  final List<MeshPacket> _packets = [];
  final List<String> _seenPacketIds = [];
  Timer? _heartbeatTimer;

  List<MeshPeer> get peers => List.unmodifiable(_peers);
  List<MeshPacket> get messages => List.unmodifiable(_packets);

  String get localPeerId => 'mesh-${DateTime.now().millisecondsSinceEpoch}';
  String get localPeerName => 'Nexus-${_randomSuffix()}';

  String _randomSuffix() => Random().nextInt(9999).toString().padLeft(4, '0');

  Future<void> init() async {
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      _cleanupOfflinePeers();
    });
  }

  void dispose() {
    _heartbeatTimer?.cancel();
  }

  void addPeer(MeshPeer peer) {
    if (!_peers.any((p) => p.id == peer.id)) {
      _peers.add(peer);
    }
  }

  Future<void> sendMessage(String text) async {
    final packet = MeshPacket(
      id: 'pkt-${DateTime.now().millisecondsSinceEpoch}',
      senderId: localPeerId,
      senderName: localPeerName,
      content: text,
    );
    _packets.add(packet);
    _simulateDelivery(packet);
  }

  void _simulateDelivery(MeshPacket packet) {
    // Mesh simulation — in real app, uses wifi-direct / BLE
    for (final peer in _peers) {
      if (peer.isOnline) {
        final delivery = MeshPacket(
          id: 'del-${DateTime.now().millisecondsSinceEpoch}',
          senderId: peer.id,
          senderName: peer.name,
          content: packet.content,
          originalSenderId: packet.senderId,
        );
        _packets.add(delivery);
      }
    }
  }

  void _cleanupOfflinePeers() {
    _peers.removeWhere((p) => !p.isOnline);
  }
}

// ════════════════════════════════════════════
// MeshRoot — InheritedWidget
// ════════════════════════════════════════════

class MeshRoot extends InheritedNotifier<MeshNetworkManager> {
  final MeshNetworkManager mesh;

  const MeshRoot({
    super.key,
    required this.mesh,
    required super.child,
  }) : super(notifier: mesh);

  static MeshNetworkManager of(BuildContext context) {
    final root = context.dependOnInheritedWidgetOfExactType<MeshRoot>();
    return root?.mesh ?? MeshNetworkManager.instance;
  }

  @override
  bool updateShouldNotify(MeshRoot oldWidget) => mesh != oldWidget.mesh;
}
