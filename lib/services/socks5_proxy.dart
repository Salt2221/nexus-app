// ════════════════════════════════════════════
// SOCKS5 Proxy Server — локальный прокси для обхода блокировок
// ════════════════════════════════════════════

import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart';

class Socks5Proxy extends ChangeNotifier {
  Socks5Proxy._();
  static final Socks5Proxy instance = Socks5Proxy._();

  ServerSocket? _server;
  bool _running = false;
  int _port = 1080;
  int _connections = 0;

  bool get isRunning => _running;
  int get port => _port;
  int get connections => _connections;

  /// Запустить SOCKS5 прокси на указанном порту
  Future<bool> start({int port = 1080}) async {
    if (_running) return true;
    _port = port;

    try {
      _server = await ServerSocket.bind(InternetAddress.loopbackIPv4, port);
      _running = true;
      _server!.listen(_handleClient, onError: (e) {
        debugPrint('SOCKS5 error: $e');
        _running = false;
        notifyListeners();
      }, onDone: () {
        _running = false;
        notifyListeners();
      });

      debugPrint('SOCKS5 proxy started on 127.0.0.1:$port');
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('SOCKS5 start failed: $e');
      return false;
    }
  }

  /// Остановить прокси
  Future<void> stop() async {
    _running = false;
    try {
      await _server?.close();
    } catch (_) {}
    _server = null;
    _connections = 0;
    notifyListeners();
  }

  void _handleClient(Socket client) {
    _connections++;
    notifyListeners();
    client.timeout(const Duration(minutes: 5));

    // SOCKS5 handshake
    client.listen((data) {
      if (data.length < 3) {
        client.destroy();
        return;
      }

      // SOCKS5: <VER> <NMETHODS> <METHODS...>
      if (data[0] == 0x05) {
        // Reply: no auth required
        client.add([0x05, 0x00]);
        return;
      }

      // SOCKS5 request: <VER> <CMD> <RSV> <ATYP> <DST.ADDR> <DST.PORT>
      if (data[0] == 0x05 && data.length >= 10) {
        final cmd = data[1];
        final atyp = data[3];

        if (cmd != 0x01) { // Only CONNECT
          client.add([0x05, 0x07, 0x00, 0x01, 0, 0, 0, 0, 0, 0]); // Command not supported
          client.destroy();
          return;
        }

        String host;
        int port;

        if (atyp == 0x01) { // IPv4
          host = '${data[4]}.${data[5]}.${data[6]}.${data[7]}';
          port = (data[8] << 8) + data[9];
        } else if (atyp == 0x03) { // Domain name
          final len = data[4];
          host = utf8.decode(data.sublist(5, 5 + len));
          port = (data[5 + len] << 8) + data[6 + len];
        } else {
          client.add([0x05, 0x08, 0x00, 0x01, 0, 0, 0, 0, 0, 0]); // Address type not supported
          client.destroy();
          return;
        }

        _relay(client, host, port);
      }
    }, onDone: () {
      _connections--;
      notifyListeners();
    }, onError: (e) {
      _connections--;
      notifyListeners();
    });
  }

  void _relay(Socket client, String host, int port) async {
    try {
      final target = await Socket.connect(host, port,
          timeout: const Duration(seconds: 10));
      target.timeout(const Duration(minutes: 5));

      // Reply success
      final localAddr = client.address.address;
      final localParts = localAddr.split('.').map((p) => int.parse(p)).toList();
      client.add([0x05, 0x00, 0x00, 0x01,
        localParts[0], localParts[1], localParts[2], localParts[3],
        (client.port >> 8) & 0xFF, client.port & 0xFF]);

      // Bidirectional relay
      final completer = Completer<void>();

      client.listen((data) {
        target.add(data);
      }, onDone: () {
        target.destroy();
        if (!completer.isCompleted) completer.complete();
      }, onError: (_) {
        target.destroy();
        if (!completer.isCompleted) completer.complete();
      });

      target.listen((data) {
        client.add(data);
      }, onDone: () {
        client.destroy();
        if (!completer.isCompleted) completer.complete();
      }, onError: (_) {
        client.destroy();
        if (!completer.isCompleted) completer.complete();
      });

      await completer.future;
    } catch (e) {
      try {
        client.add([0x05, 0x04, 0x00, 0x01, 0, 0, 0, 0, 0, 0]); // Host unreachable
      } catch (_) {}
      client.destroy();
    }
  }
}
