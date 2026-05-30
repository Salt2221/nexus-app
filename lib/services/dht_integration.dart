// ═══════════════════════════════════════════════════════════════
// NEXUS DHT Integration — Мост между DHT P2P сетью и модулями
//
// Позволяет:
//   - Edge Storage: релеить блоки через DHT (store/find)
//   - VPN: публиковать relay-адреса в DHT
//   - SDR: шарить спектр/детекты через gossip
//   - Compute: распространять задачи через DHT
//
//  ВСЁ НА ЧИСТОМ DART — 100% ЛОКАЛЬНО
// ═══════════════════════════════════════════════════════════════

import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';

import 'dht_network.dart';

// ═══ ТИПЫ СООБЩЕНИЙ ═══
enum DhtIntegrationType {
  edgeBlockRelay,     // Edge Storage: релей блока
  edgeBlockRequest,   // Edge Storage: запрос блока
  vpnRelayOffer,      // VPN: предложение relay-узла
  vpnRelayRequest,    // VPN: запрос relay
  computeTask,        // Compute: задача для воркеров
  computeResult,      // Compute: результат задачи
  sdrSpectrumShare,   // SDR: публикация спектра
  sdrSignalDetected,  // SDR: детект сигнала на пире
  dhtStorageFallback, // Edge/DHT: fallback значения
}

/// Сообщение DHT интеграции
class DhtIntegrationMessage {
  final DhtIntegrationType type;
  final String senderId;
  final String targetId;
  final Map<String, dynamic> payload;
  final DateTime timestamp;

  DhtIntegrationMessage({
    required this.type,
    required this.senderId,
    this.targetId = '',
    required this.payload,
    required this.timestamp,
  });

  Map<String, dynamic> toJson() => {
    't': type.index,
    's': senderId,
    'tg': targetId,
    'p': payload,
    'ts': timestamp.millisecondsSinceEpoch,
  };

  factory DhtIntegrationMessage.fromJson(Map<String, dynamic> j) {
    return DhtIntegrationMessage(
      type: DhtIntegrationType.values[j['t'] as int],
      senderId: j['s'] as String,
      targetId: (j['tg'] as String?) ?? '',
      payload: Map<String, dynamic>.from(j['p'] as Map),
      timestamp: DateTime.fromMillisecondsSinceEpoch(j['ts'] as int),
    );
  }
}

// ═══ DHT INTEGRATION MANAGER ═══
class DhtIntegration extends ChangeNotifier {
  static final DhtIntegration instance = DhtIntegration._();

  DhtNode? _dhtNode;
  bool _initialized = false;
  String? _localId;
  final Map<String, dynamic> _localFallbackStore = {};

  // Коллбеки для модулей
  void Function(DhtIntegrationMessage msg)? onEdgeBlockRelay;
  void Function(DhtIntegrationMessage msg)? onEdgeBlockRequest;
  void Function(DhtIntegrationMessage msg)? onVpnRelayOffer;
  void Function(DhtIntegrationMessage msg)? onVpnRelayRequest;
  void Function(DhtIntegrationMessage msg)? onComputeTask;
  void Function(DhtIntegrationMessage msg)? onComputeResult;
  void Function(DhtIntegrationMessage msg)? onSdrSpectrumShare;
  void Function(DhtIntegrationMessage msg)? onSdrSignalDetected;

  DhtIntegration._();

  bool get initialized => _initialized;
  String? get localId => _localId;
  bool get isNetworkAvailable => _initialized && _dhtNode != null && _dhtNode!.running && _dhtNode!.totalPeers > 0;
  int get peerCount => _dhtNode?.totalPeers ?? 0;

  /// Инициализация
  Future<bool> init() async {
    if (_initialized) return true;
    try {
      if (!DhtNetworkManager.instance.initialized) {
        await DhtNetworkManager.instance.init();
      }
      _dhtNode = DhtNetworkManager.instance.node;
      if (_dhtNode == null) return false;
      _localId = _dhtNode!.nodeId.toHex();
      _initialized = true;
      _dhtNode!.onMessage = _handleDhtMessage;
      _dhtNode!.onValueFound = _handleDhtValueFound;
      debugPrint('[DHT-INT] Initialized (id=$_localId)');
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('[DHT-INT] init fail: $e');
      return false;
    }
  }

  void _handleDhtMessage(DhtMsg msg, DhtPeer peer) {
    if (msg.data == null) return;
    try {
      var intMsg = DhtIntegrationMessage.fromJson(msg.data!);
      switch (intMsg.type) {
        case DhtIntegrationType.edgeBlockRelay: onEdgeBlockRelay?.call(intMsg); break;
        case DhtIntegrationType.edgeBlockRequest: onEdgeBlockRequest?.call(intMsg); break;
        case DhtIntegrationType.vpnRelayOffer: onVpnRelayOffer?.call(intMsg); break;
        case DhtIntegrationType.vpnRelayRequest: onVpnRelayRequest?.call(intMsg); break;
        case DhtIntegrationType.computeTask: onComputeTask?.call(intMsg); break;
        case DhtIntegrationType.computeResult: onComputeResult?.call(intMsg); break;
        case DhtIntegrationType.sdrSpectrumShare: onSdrSpectrumShare?.call(intMsg); break;
        case DhtIntegrationType.sdrSignalDetected: onSdrSignalDetected?.call(intMsg); break;
        case DhtIntegrationType.dhtStorageFallback:
          if (intMsg.payload.containsKey('key') && intMsg.payload.containsKey('value')) {
            _localFallbackStore[intMsg.payload['key']] = intMsg.payload['value'];
          }
          break;
      }
    } catch (e) { debugPrint('[DHT-INT] parse: $e'); }
  }

  void _handleDhtValueFound(String key, dynamic value) {
    if (key.startsWith('edge:')) {
      onEdgeBlockRelay?.call(DhtIntegrationMessage(
        type: DhtIntegrationType.edgeBlockRelay, senderId: key,
        payload: {'key': key, 'value': value}, timestamp: DateTime.now(),
      ));
    } else if (key.startsWith('compute:')) {
      onComputeResult?.call(DhtIntegrationMessage(
        type: DhtIntegrationType.computeResult, senderId: key,
        payload: {'key': key, 'value': value}, timestamp: DateTime.now(),
      ));
    }
  }

  // ═══ EDGE STORAGE ═══
  Future<bool> publishEdgeBlock(String blockId, String data) async {
    if (!_initialized || _dhtNode == null) return false;
    return await _dhtNode!.storeValue('edge:block:$blockId', data);
  }

  Future<String?> findEdgeBlock(String blockId) async {
    if (!_initialized || _dhtNode == null) return null;
    var r = await _dhtNode!.findValue('edge:block:$blockId');
    return (r is String) ? r : null;
  }

  void requestEdgeBlockViaGossip(String blockId, String requestorId) {
    if (!_initialized || _dhtNode == null) return;
    _dhtNode!.gossip(DhtIntegrationMessage(
      type: DhtIntegrationType.edgeBlockRequest, senderId: requestorId,
      payload: {'block_id': blockId, 'requestor': requestorId},
      timestamp: DateTime.now(),
    ).toJson());
  }

  void relayEdgeBlockViaGossip(String blockId, String data, String peerId) {
    if (!_initialized || _dhtNode == null) return;
    _dhtNode!.gossip(DhtIntegrationMessage(
      type: DhtIntegrationType.edgeBlockRelay, senderId: _localId ?? '', targetId: peerId,
      payload: {'block_id': blockId, 'data': data},
      timestamp: DateTime.now(),
    ).toJson());
  }

  // ═══ VPN RELAY ═══
  Future<bool> publishVpnRelay(String relayId, String ip, int port) async {
    if (!_initialized || _dhtNode == null) return false;
    return await _dhtNode!.storeValue('vpn:relay:$relayId', {'ip': ip, 'port': port, 'available': true});
  }

  Future<Map<String, dynamic>?> findVpnRelay(String relayId) async {
    if (!_initialized || _dhtNode == null) return null;
    var r = await _dhtNode!.findValue('vpn:relay:$relayId');
    return (r is Map) ? Map<String, dynamic>.from(r) : null;
  }

  void requestVpnRelay(String requestorId) {
    if (!_initialized || _dhtNode == null) return;
    _dhtNode!.gossip(DhtIntegrationMessage(
      type: DhtIntegrationType.vpnRelayRequest, senderId: requestorId,
      payload: {'requestor': requestorId}, timestamp: DateTime.now(),
    ).toJson());
  }

  void offerVpnRelay(String relayId, String ip, int port) {
    if (!_initialized || _dhtNode == null) return;
    _dhtNode!.gossip(DhtIntegrationMessage(
      type: DhtIntegrationType.vpnRelayOffer, senderId: _localId ?? '',
      payload: {'relay_id': relayId, 'ip': ip, 'port': port},
      timestamp: DateTime.now(),
    ).toJson());
  }

  // ═══ COMPUTE ═══
  Future<bool> publishComputeTask(String taskId, Map<String, dynamic> taskDef) async {
    if (!_initialized || _dhtNode == null) return false;
    return await _dhtNode!.storeValue('compute:task:$taskId', taskDef);
  }

  Future<bool> publishComputeResult(String taskId, dynamic result) async {
    if (!_initialized || _dhtNode == null) return false;
    return await _dhtNode!.storeValue('compute:result:$taskId', result);
  }

  Future<dynamic> findComputeResult(String taskId) async {
    if (!_initialized || _dhtNode == null) return null;
    return await _dhtNode!.findValue('compute:result:$taskId');
  }

  void gossipComputeTask(Map<String, dynamic> taskDef) {
    if (!_initialized || _dhtNode == null) return;
    _dhtNode!.gossip(DhtIntegrationMessage(
      type: DhtIntegrationType.computeTask, senderId: _localId ?? '',
      payload: taskDef, timestamp: DateTime.now(),
    ).toJson());
  }

  void gossipComputeResult(String taskId, dynamic result) {
    if (!_initialized || _dhtNode == null) return;
    _dhtNode!.gossip(DhtIntegrationMessage(
      type: DhtIntegrationType.computeResult, senderId: _localId ?? '',
      payload: {'task_id': taskId, 'result': result}, timestamp: DateTime.now(),
    ).toJson());
  }

  // ═══ SDR ═══
  Future<bool> publishSdrSpectrum(double freqMHz, List<double> spectrum) async {
    if (!_initialized || _dhtNode == null) return false;
    return await _dhtNode!.storeValue(
      'sdr:spectrum:${freqMHz.toStringAsFixed(3)}',
      {'freq': freqMHz, 'spectrum': spectrum, 'pub_at': DateTime.now().toIso8601String()},
    );
  }

  Future<Map<String, dynamic>?> findSdrSpectrum(double freqMHz) async {
    if (!_initialized || _dhtNode == null) return null;
    var r = await _dhtNode!.findValue('sdr:spectrum:${freqMHz.toStringAsFixed(3)}');
    return (r is Map) ? Map<String, dynamic>.from(r) : null;
  }

  void gossipSignalDetected(double freqMHz, String label, double strength) {
    if (!_initialized || _dhtNode == null) return;
    _dhtNode!.gossip(DhtIntegrationMessage(
      type: DhtIntegrationType.sdrSignalDetected, senderId: _localId ?? '',
      payload: {'freq': freqMHz, 'label': label, 'strength': strength},
      timestamp: DateTime.now(),
    ).toJson());
  }

  void gossipSpectrum(double freqMHz, List<double> spectrum) {
    if (!_initialized || _dhtNode == null) return;
    _dhtNode!.gossip(DhtIntegrationMessage(
      type: DhtIntegrationType.sdrSpectrumShare, senderId: _localId ?? '',
      payload: {'freq': freqMHz, 'spectrum': spectrum.take(64).toList()},
      timestamp: DateTime.now(),
    ).toJson());
  }

  // ═══ FALLBACK ═══
  void storeFallback(String key, dynamic value) { _localFallbackStore[key] = value; }
  dynamic findFallback(String key) => _localFallbackStore[key];

  void dispose() {
    if (_dhtNode != null) { _dhtNode!.onMessage = null; _dhtNode!.onValueFound = null; }
    _localFallbackStore.clear();
    onEdgeBlockRelay = null; onEdgeBlockRequest = null;
    onVpnRelayOffer = null; onVpnRelayRequest = null;
    onComputeTask = null; onComputeResult = null;
    onSdrSpectrumShare = null; onSdrSignalDetected = null;
    _initialized = false;
  }
}
