// ════════════════════════════════════════════
// NEXUS TG WS Proxy — WebSocket → MTProto bridge
// Переписан с TgWsProxy (Python) на Dart
// ════════════════════════════════════════════

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// Конфигурация прокси
class TgWsProxyConfig {
  final String host;
  final int port;
  final bool enabled;
  final String secret;
  final String bridgeUrl;
  final String balancerUrl;
  final List<String> linkHosts;

  const TgWsProxyConfig({
    this.host = '127.0.0.1',
    this.port = 1443,
    this.enabled = true,
    this.secret = 'nexus_tg_ws_2026',
    this.bridgeUrl = 'wss://tgbridge.iamka.ru/ws',
    this.balancerUrl = 'wss://tgbridge.iamka.ru/ws',
    this.linkHosts = const [
      'telegram.org',
      't.me',
      'telegram.me',
      'web.telegram.org',
      'tdesktop.com',
    ],
  });
}

/// Состояние прокси
enum TgWsProxyStatus { stopped, starting, running, stopping, error }

/// TG WS Proxy — полная реализация
class NexusTgWsProxy {
  NexusTgWsProxy._();
  static final NexusTgWsProxy instance = NexusTgWsProxy._();

  TgWsProxyConfig _config = const TgWsProxyConfig();

  // Состояние
  TgWsProxyStatus _status = TgWsProxyStatus.stopped;
  String _error = '';
  int _activeConnections = 0;
  int _totalConnections = 0;
  int _bytesTransferred = 0;

  // Серверные компоненты
  ServerSocket? _tcpServer;
  WebSocketChannel? _bridgeChannel;
  final List<Socket> _clients = [];
  Timer? _reconnectTimer;
  final List<StreamSubscription> _subscriptions = [];

  // Геттеры
  TgWsProxyConfig get config => _config;
  TgWsProxyStatus get status => _status;
  String get error => _error;
  int get activeConnections => _activeConnections;
  int get totalConnections => _totalConnections;
  int get bytesTransferred => _bytesTransferred;
  bool get isRunning => _status == TgWsProxyStatus.running;

  // Колбэки для UI
  void Function(TgWsProxyStatus)? onStatusChanged;
  void Function(int connections)? onConnectionChanged;
  void Function(int bytes)? onTrafficChanged;

  /// Инициализация
  void init({TgWsProxyConfig? config}) {
    if (config != null) _config = config;
  }

  /// Запуск прокси
  Future<bool> start() async {
    if (_status == TgWsProxyStatus.running) return true;

    _status = TgWsProxyStatus.starting;
    _error = '';
    _onStatusChanged();
    _activeConnections = 0;
    _totalConnections = 0;
    _bytesTransferred = 0;

    try {
      // 1. Подключаемся к WebSocket bridge
      await _connectBridge();

      // 2. Запускаем TCP-сервер для приёма локальных подключений
      _tcpServer = await ServerSocket.bind(
        InternetAddress.loopbackIPv4,
        _config.port,
      );

      _tcpServer!.listen(_onTcpConnection, onError: _onTcpError);
      
      _status = TgWsProxyStatus.running;
      _onStatusChanged();
      
      // 3. Запускаем пинг для поддержания соединения
      _startPing();

      return true;
    } catch (e) {
      _status = TgWsProxyStatus.error;
      _error = 'Ошибка запуска: $e';
      _onStatusChanged();
      await _cleanup();
      return false;
    }
  }

  /// Остановка прокси
  Future<void> stop() async {
    _status = TgWsProxyStatus.stopping;
    _onStatusChanged();
    await _cleanup();
    _status = TgWsProxyStatus.stopped;
    _onStatusChanged();
  }

  /// Подключение к WebSocket bridge
  Future<void> _connectBridge() async {
    try {
      final uri = Uri.parse(_config.bridgeUrl);
      _bridgeChannel = WebSocketChannel.connect(uri, protocols: ['mtproto']);

      // Ждём открытия
      await _bridgeChannel!.ready;
      
      // Слушаем сообщения
      final sub = _bridgeChannel!.stream.listen(
        _onBridgeMessage,
        onError: (e) {
          _error = 'Bridge error: $e';
          _onStatusChanged();
          _scheduleReconnect();
        },
        onDone: () {
          _bridgeChannel = null;
          if (_status == TgWsProxyStatus.running) {
            _scheduleReconnect();
          }
        },
      );
      _subscriptions.add(sub);
    } catch (e) {
      _error = 'Bridge connect failed: $e';
      _onStatusChanged();
      _scheduleReconnect();
    }
  }

  /// Планирование переподключения
  void _scheduleReconnect() {
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 5), () async {
      if (_status == TgWsProxyStatus.running && _bridgeChannel == null) {
        await _connectBridge();
      }
    });
  }

  /// Пинг WebSocket каждые 30 секунд
  void _startPing() {
    Timer.periodic(const Duration(seconds: 30), (_) {
      if (_bridgeChannel != null) {
        try {
          _bridgeChannel!.sink.add(jsonEncode({'type': 'ping'}));
        } catch (_) {}
      }
    });
  }

  /// Обработка нового TCP-подключения
  void _onTcpConnection(Socket client) {
    _activeConnections++;
    _totalConnections++;
    _onConnectionChanged();
    _clients.add(client);

    final buffer = BytesBuilder();

    client.listen(
      (data) {
        _bytesTransferred += data.length;
        _onTrafficChanged();
        buffer.add(data);

        // Отправляем входящий трафик через WebSocket bridge
        if (_bridgeChannel != null) {
          try {
            _bridgeChannel!.sink.add(base64Encode(data));
          } catch (e) {
            _error = 'Send failed: $e';
            _onStatusChanged();
          }
        }
      },
      onDone: () {
        _clients.remove(client);
        _activeConnections--;
        _onConnectionChanged();
      },
      onError: (_) {
        _clients.remove(client);
        _activeConnections--;
        _onConnectionChanged();
      },
    );
  }

  /// Обработка сообщений от WebSocket bridge (ответы)
  void _onBridgeMessage(dynamic message) {
    try {
      final data = base64Decode(message as String);
      // Отправляем ответ активным клиентам
      for (final client in _clients.toList()) {
        try {
          client.add(data);
          _bytesTransferred += data.length;
          _onTrafficChanged();
        } catch (_) {
          _clients.remove(client);
          _activeConnections--;
          _onConnectionChanged();
        }
      }
    } catch (e) {
      _error = 'Bridge message error: $e';
      _onStatusChanged();
    }
  }

  /// Ошибка TCP-сервера
  void _onTcpError(Object error) {
    _error = 'TCP error: $error';
    _status = TgWsProxyStatus.error;
    _onStatusChanged();
  }

  /// Очистка ресурсов
  Future<void> _cleanup() async {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;

    for (final sub in _subscriptions) {
      await sub.cancel();
    }
    _subscriptions.clear();

    try { await _bridgeChannel?.sink.close(); } catch (_) {}
    _bridgeChannel = null;

    for (final client in _clients) {
      try { client.close(); } catch (_) {}
    }
    _clients.clear();

    try { await _tcpServer?.close(); } catch (_) {}
    _tcpServer = null;

    _activeConnections = 0;
  }

  void _onStatusChanged() {
    onStatusChanged?.call(_status);
  }

  void _onConnectionChanged() {
    onConnectionChanged?.call(_activeConnections);
  }

  void _onTrafficChanged() {
    onTrafficChanged?.call(_bytesTransferred);
  }
}
