// ignore_for_file: use_of_void_result

import 'dart:async';
import 'package:flutter/services.dart';

/// Управление MTProto прокси через нативный Kotlin-сервис.
/// Реализует obfuscated transport (AES-CTR) + Fake TLS (0xDD secret).
/// Полная логика на Kotlin в NexusVpnService.kt
class NexusMtprotoProxy {
  static const _channel = MethodChannel('com.nexus.v2/mtproto');
  static const _vpnChannel = MethodChannel('com.nexus.v2/vpn');
  static final NexusMtprotoProxy _instance = NexusMtprotoProxy._();
  factory NexusMtprotoProxy() => _instance;
  static NexusMtprotoProxy get instance => _instance;
  NexusMtprotoProxy._();

  // Стейт
  bool _running = false;
  bool get isRunning => _running;

  String _secret = '';
  String get secret => _secret;

  String _status = 'stopped';
  String get status => _status;

  int _connections = 0;
  int get connections => _connections;

  int _bytesRelayed = 0;
  int get bytesRelayed => _bytesRelayed;

  String _currentDc = '';
  String get currentDc => _currentDc;

  int _handshakeOk = 0;
  int get handshakeOk => _handshakeOk;

  int _handshakeFail = 0;
  int get handshakeFail => _handshakeFail;

  String _protocol = 'AES-CTR';
  String get protocol => _protocol;

  int _port = 1443;

  String get proxyConfig {
    if (_secret.isEmpty) return '';
    return 'tg://proxy?server=127.0.0.1&port=$_port&secret=$_secret';
  }



  Future<bool> start({int port = 1443}) async {
    try {
      _port = port;
      _channel.setMethodCallHandler(_handleStatus);

      final secret = await _vpnChannel.invokeMethod<String>('getSecret');
      if (secret != null && secret.isNotEmpty) _secret = secret;
      // ignore: use_of_void_result
      await _vpnChannel.invokeMethod('startMtproto', {'port': port});
      _running = true;
      return true;
    } catch (_) {
      _running = false;
      return false;
    }
  }

  Future<bool> stop() async {
    try {
      await _vpnChannel.invokeMethod('stopMtproto');
      _running = false;
      _status = 'stopped';
      _connections = 0;
      return true;
    } catch (_) {
      return false;
    }
  }

  // SOCKS5 управление через нативный код

  Future<bool> startSocks({int port = 1080}) async {
    try {
      await _vpnChannel.invokeMethod('startSocks', {'port': port});
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> stopSocks() async {
    try {
      await _vpnChannel.invokeMethod('stopSocks');
      return true;
    } catch (_) {
      return false;
    }
  }

  String getProxyLink() => proxyConfig;

  Future<void> _handleStatus(dynamic call) async {
    if (call.method != 'onStatus') return;
    final args = call.arguments as Map<dynamic, dynamic>;
    _status = args['status'] as String? ?? _status;
    _connections = args['connections'] as int? ?? 0;
    _bytesRelayed = args['bytesRelayed'] as int? ?? 0;
    _currentDc = args['currentDc'] as String? ?? '';
    _handshakeOk = args['handshakeOk'] as int? ?? 0;
    _handshakeFail = args['handshakeFail'] as int? ?? 0;
    _protocol = args['protocol'] as String? ?? 'AES-CTR';
    final s = args['secret'] as String?;
    if (s != null && s.isNotEmpty) _secret = s;
  }

  void dispose() {}
}
