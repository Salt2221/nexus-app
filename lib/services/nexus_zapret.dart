// ════════════════════════════════════════════
// NEXUS Zapret — VPN + MTProto Proxy Manager
// ════════════════════════════════════════════

import 'dart:async';
import 'package:flutter/services.dart';

const _vpnChannel = MethodChannel('com.nexus.v2/vpn');

class ZapretProfile {
  final String name;
  final String description;
  bool enabled;
  ZapretProfile({required this.name, required this.description, this.enabled = false});
}

enum VpnServiceStatus { disconnected, preparing, connected, denied }

class NexusZapret {
  NexusZapret._();
  static final NexusZapret instance = NexusZapret._();

  bool _running = false;
  VpnServiceStatus _vpnStatus = VpnServiceStatus.disconnected;
  bool _mtprotoProxyEnabled = false;

  final List<ZapretProfile> _profiles = [];
  List<ZapretProfile> get profiles => _profiles;
  bool get isRunning => _running;
  bool get mtprotoProxyEnabled => _mtprotoProxyEnabled;
  VpnServiceStatus get vpnStatus => _vpnStatus;

  int _startTime = 0;
  Timer? _timer;
  int get uptimeSeconds => _startTime;

  void Function(VpnServiceStatus status)? onVpnStatusChanged;

  void init() {
    _profiles.addAll([
      ZapretProfile(name: 'YouTube', description: 'Обход блокировок YouTube'),
      ZapretProfile(name: 'Telegram', description: 'MTProto proxy + обход Telegram'),
      ZapretProfile(name: 'Twitter / X', description: 'Обход Twitter/X'),
      ZapretProfile(name: 'Универсальный', description: 'Автоматический обход DPI'),
    ]);
  }

  Future<bool> startVpnService() async {
    try {
      _setStatus(VpnServiceStatus.preparing);
      final result = await _vpnChannel.invokeMethod<bool>('startVpn');
      if (result == true) {
        _running = true;
        _setStatus(VpnServiceStatus.connected);
        _startTime = 0;
        _timer?.cancel();
        _timer = Timer.periodic(const Duration(seconds: 1), (_) => _startTime++);
        return true;
      } else {
        _setStatus(VpnServiceStatus.denied);
        return false;
      }
    } catch (e) {
      _setStatus(VpnServiceStatus.disconnected);
      return false;
    }
  }

  Future<bool> stopVpnService() async {
    try {
      await _vpnChannel.invokeMethod('stopVpn');
      _running = false;
      _setStatus(VpnServiceStatus.disconnected);
      _timer?.cancel();
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Start MTProto proxy, returns secret string
  Future<dynamic> startMtproto({int port = 1443}) async {
    try {
      final result = await _vpnChannel.invokeMethod('startMtproxy', {'port': port});
      _mtprotoProxyEnabled = true;
      return result; // secret from Kotlin
    } catch (e) {
      return null;
    }
  }

  Future<bool> stopMtproto() async {
    try {
      await _vpnChannel.invokeMethod('stopMtproxy');
      _mtprotoProxyEnabled = false;
      return true;
    } catch (e) {
      return false;
    }
  }

  void _setStatus(VpnServiceStatus status) {
    _vpnStatus = status;
    onVpnStatusChanged?.call(status);
  }

  void start() => startVpnService();
  void stop() => stopVpnService();

  Map<String, dynamic> getStats() => {
    'vpnStatus': _vpnStatus.name,
    'uptime': _startTime,
    'mtprotoProxy': _mtprotoProxyEnabled,
  };
}
