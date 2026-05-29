import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'dart:async';

// ════════════════════════════════════════════
// Transport Layer — управление соединениями
// ════════════════════════════════════════════

class NexusTransportManager extends ChangeNotifier {
  static final NexusTransportManager instance = NexusTransportManager._();
  NexusTransportManager._();

  bool _initialized = false;
  String? _serverUrl;
  int _activeConnections = 0;

  bool get isInitialized => _initialized;
  String? get serverUrl => _serverUrl;
  int get activeConnections => _activeConnections;

  Future<void> init() async {
    _initialized = true;
    _serverUrl = 'http://localhost:8081';
  }

  @override
  void dispose() {
    _initialized = false;
    super.dispose();
  }

  Future<bool> connect(String url) async {
    _serverUrl = url;
    _activeConnections++;
    return true;
  }

  void disconnect() {
    if (_activeConnections > 0) _activeConnections--;
  }
}

// ════════════════════════════════════════════
// TransportRoot — InheritedWidget
// ════════════════════════════════════════════

class TransportRoot extends InheritedNotifier<NexusTransportManager> {
  const TransportRoot({
    super.key,
    required NexusTransportManager transport,
    required super.child,
    this.serverUrl,
  }) : super(notifier: transport);

  final String? serverUrl;

  static NexusTransportManager of(BuildContext context) {
    final root = context.dependOnInheritedWidgetOfExactType<TransportRoot>();
    return root?.notifier ?? NexusTransportManager.instance;
  }

  @override
  bool updateShouldNotify(TransportRoot oldWidget) => notifier != oldWidget.notifier;
}
