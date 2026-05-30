// ═══════════════════════════════════════════════════════════════
// NEXUS DPI Screen — Packet Fragmenter + Bridge Rotator + Camouflage Tunnel
// ═══════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'dart:math';

// ═══════════════════════════════════════════════════════════════
// Method Channels
// ═══════════════════════════════════════════════════════════════

const _dpiChannel = MethodChannel('com.nexus.v2/dpi');
const _bridgeChannel = MethodChannel('com.nexus.v2/bridge');
const _tunnelChannel = MethodChannel('com.nexus.v2/tunnel');

// ═══════════════════════════════════════════════════════════════
// 1. DPI Manager — Packet Fragmenter
// ═══════════════════════════════════════════════════════════════

class DpiManager {
  static final DpiManager instance = DpiManager._();
  DpiManager._();

  bool _active = false;
  String _currentStrategy = 'none';
  int _packetsProcessed = 0;
  int _packetsModified = 0;

  bool get active => _active;
  String get currentStrategy => _currentStrategy;
  int get packetsProcessed => _packetsProcessed;
  int get packetsModified => _packetsModified;

  // Конфигурация стратегий
  bool sniFragment = true;
  bool httpMangle = true;
  bool fakeTtl = true;
  bool tlsSplit = true;
  bool padding = true;

  Future<bool> start() async {
    try {
      final result = await _dpiChannel.invokeMethod('start', {
        'sni_fragment': sniFragment,
        'http_mangle': httpMangle,
        'fake_ttl': fakeTtl,
        'tls_split': tlsSplit,
        'padding': padding,
      });
      _active = result == true;
      return _active;
    } catch (e) {
      return false;
    }
  }

  Future<bool> stop() async {
    try {
      await _dpiChannel.invokeMethod('stop');
      _active = false;
      return true;
    } catch (e) {
      return false;
    }
  }

  Future<Map<String, dynamic>> getStats() async {
    try {
      final result = await _dpiChannel.invokeMethod('getStats');
      if (result is Map) return Map<String, dynamic>.from(result);
    } catch (_) {}
    return {'active': _active, 'packets': _packetsProcessed, 'modified': _packetsModified};
  }
}

// ═══════════════════════════════════════════════════════════════
// 2. Bridge Manager — Anti-Blocking Rotator
// ═══════════════════════════════════════════════════════════════

class BridgeManager {
  static final BridgeManager instance = BridgeManager._();
  BridgeManager._();

  bool _active = false;
  List<Map<String, dynamic>> _bridges = [];
  Map<String, dynamic>? _activeBridge;

  bool get active => _active;
  List<Map<String, dynamic>> get bridges => _bridges;
  Map<String, dynamic>? get activeBridge => _activeBridge;

  Future<bool> startDiscovery() async {
    try {
      final result = await _bridgeChannel.invokeMethod('start');
      _active = result == true;
      return _active;
    } catch (e) {
      return false;
    }
  }

  Future<List<Map<String, dynamic>>> discoverBridges() async {
    try {
      final result = await _bridgeChannel.invokeMethod('discover');
      if (result is List) {
        _bridges = result.cast<Map<String, dynamic>>();
      }
    } catch (_) {}
    return _bridges;
  }

  Future<bool> switchBridge(String host) async {
    try {
      final result = await _bridgeChannel.invokeMethod('switch', {'host': host});
      if (result == true) {
        _activeBridge = _bridges.firstWhere(
          (b) => b['host'] == host,
          orElse: () => <String, dynamic>{},
        );
      }
      return result == true;
    } catch (e) {
      return false;
    }
  }

  Future<bool> markBlocked(String host) async {
    try {
      await _bridgeChannel.invokeMethod('markBlocked', {'host': host});
      return true;
    } catch (e) {
      return false;
    }
  }
}

// ═══════════════════════════════════════════════════════════════
// 3. Tunnel Manager — Camouflage Tunnel
// ═══════════════════════════════════════════════════════════════

class TunnelManager {
  static final TunnelManager instance = TunnelManager._();
  TunnelManager._();

  bool _connected = false;
  String _frontDomain = 'firebase.google.com';
  String _hiddenDomain = '';
  String _protocol = 'websocket';
  int _bytesSent = 0;
  int _bytesReceived = 0;

  bool get connected => _connected;
  String get frontDomain => _frontDomain;
  String get protocol => _protocol;

  Future<bool> connect({
    required String frontDomain,
    required String hiddenDomain,
    String protocol = 'websocket',
    int port = 443,
    String path = '/chat',
  }) async {
    try {
      final result = await _tunnelChannel.invokeMethod('connect', {
        'front_domain': frontDomain,
        'hidden_domain': hiddenDomain,
        'port': port,
        'protocol': protocol,
        'path': path,
      });
      if (result == true) {
        _frontDomain = frontDomain;
        _hiddenDomain = hiddenDomain;
        _protocol = protocol;
        _connected = true;
      }
      return _connected;
    } catch (e) {
      return false;
    }
  }

  Future<void> disconnect() async {
    try {
      await _tunnelChannel.invokeMethod('disconnect');
      _connected = false;
    } catch (_) {}
  }

  Future<bool> switchDomain(String newDomain) async {
    try {
      final result = await _tunnelChannel.invokeMethod('switchDomain', {
        'domain': newDomain,
      });
      if (result == true) _frontDomain = newDomain;
      return result == true;
    } catch (e) {
      return false;
    }
  }

  Future<bool> switchProtocol(String protocol) async {
    try {
      final result = await _tunnelChannel.invokeMethod('switchProtocol', {
        'protocol': protocol,
      });
      if (result == true) _protocol = protocol;
      return result == true;
    } catch (e) {
      return false;
    }
  }
}

// ═══════════════════════════════════════════════════════════════
// 4. UI экран
// ═══════════════════════════════════════════════════════════════

class DpiScreen extends StatefulWidget {
  const DpiScreen({super.key});

  @override
  State<DpiScreen> createState() => _DpiScreenState();
}

class _DpiScreenState extends State<DpiScreen> {
  final _dpi = DpiManager.instance;
  final _bridge = BridgeManager.instance;
  final _tunnel = TunnelManager.instance;

  Timer? _statsTimer;

  // DPI toggles
  bool _sniFrag = true;
  bool _httpMangle = true;
  bool _fakeTtl = true;
  bool _padding = true;
  bool _active = false;

  // Tunnel config
  final _domainCtrl = TextEditingController(text: 'firebase.google.com');
  final _hiddenCtrl = TextEditingController(text: '');
  String _selectedProtocol = 'websocket';
  String _log = '';

  @override
  void initState() {
    super.initState();
    _statsTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _statsTimer?.cancel();
    _domainCtrl.dispose();
    _hiddenCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('DPI & Bridges'),
        backgroundColor: Colors.indigo.shade800,
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          // ════ SECTION 1: DPI Packet Fragmenter ════
          _sectionHeader('Packet Fragmenter', Icons.construction),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  SwitchListTile(
                    title: const Text('SNI Fragment'),
                    subtitle: const Text('Разбивать SNI на части'),
                    value: _sniFrag,
                    onChanged: (v) => setState(() => _sniFrag = v),
                  ),
                  SwitchListTile(
                    title: const Text('HTTP Case Mangle'),
                    subtitle: const Text('Менять регистр заголовков'),
                    value: _httpMangle,
                    onChanged: (v) => setState(() => _httpMangle = v),
                  ),
                  SwitchListTile(
                    title: const Text('Fake TTL Packets'),
                    subtitle: const Text('Фейковые пакеты с низким TTL'),
                    value: _fakeTtl,
                    onChanged: (v) => setState(() => _fakeTtl = v),
                  ),
                  SwitchListTile(
                    title: const Text('Packet Padding'),
                    subtitle: const Text('Добавлять padding к пакетам'),
                    value: _padding,
                    onChanged: (v) => setState(() => _padding = v),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      icon: Icon(_active ? Icons.stop : Icons.play_arrow),
                      label: Text(_active ? 'Stop DPI' : 'Start DPI'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _active ? Colors.red : Colors.green,
                        foregroundColor: Colors.white,
                      ),
                      onPressed: () async {
                        if (_active) {
                          await _dpi.stop();
                        } else {
                          _dpi.sniFragment = _sniFrag;
                          _dpi.httpMangle = _httpMangle;
                          _dpi.fakeTtl = _fakeTtl;
                          _dpi.padding = _padding;
                          await _dpi.start();
                        }
                        setState(() => _active = _dpi.active);
                        _addLog('DPI ${_active ? "включён" : "выключен"}');
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 12),

          // ════ SECTION 2: Bridge Rotator ════
          _sectionHeader('Bridge Rotator', Icons.wifi_tethering),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.search),
                      label: const Text('Discover Bridges'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.teal,
                        foregroundColor: Colors.white,
                      ),
                      onPressed: () async {
                        _addLog('Searching bridges...');
                        final bridges = await _bridge.discoverBridges();
                        setState(() {});
                        _addLog('Found ${bridges.length} bridges');
                      },
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (_bridge.bridges.isNotEmpty)
                    ..._bridge.bridges.map((b) => ListTile(
                      dense: true,
                      leading: Icon(
                        b['blocked'] == true ? Icons.block : Icons.cloud_done,
                        color: b['blocked'] == true ? Colors.red : Colors.green,
                        size: 20,
                      ),
                      title: Text('${b['host']}:${b['port']}', style: const TextStyle(fontSize: 13)),
                      subtitle: Text('${b['protocol']} • ${b['fingerprint']}', style: const TextStyle(fontSize: 11)),
                      trailing: TextButton(
                        child: const Text('Switch', style: TextStyle(fontSize: 11)),
                        onPressed: () async {
                          await _bridge.switchBridge(b['host']);
                          setState(() {});
                          _addLog('Switched to ${b['host']}');
                        },
                      ),
                    )),
                  if (_bridge.bridges.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(16),
                      child: Text('No bridges found', style: TextStyle(color: Colors.grey)),
                    ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 12),

          // ════ SECTION 3: Camouflage Tunnel ════
          _sectionHeader('Camouflage Tunnel', Icons.shield),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  TextField(
                    controller: _domainCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Front Domain (CDN)',
                      border: OutlineInputBorder(),
                      isDense: true,
                      hintText: 'firebase.google.com',
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _hiddenCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Hidden Domain (real server)',
                      border: OutlineInputBorder(),
                      isDense: true,
                      hintText: 'your-server.com',
                    ),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    value: _selectedProtocol,
                    decoration: const InputDecoration(
                      labelText: 'Protocol',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: const [
                      DropdownMenuItem(value: 'websocket', child: Text('WebSocket (WSS)')),
                      DropdownMenuItem(value: 'grpc', child: Text('gRPC')),
                      DropdownMenuItem(value: 'google_firebase', child: Text('Fake Firebase')),
                      DropdownMenuItem(value: 'fake_chat', child: Text('Fake Chat')),
                    ],
                    onChanged: (v) => setState(() => _selectedProtocol = v ?? 'websocket'),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          icon: Icon(_tunnel.connected ? Icons.link_off : Icons.link),
                          label: Text(_tunnel.connected ? 'Disconnect' : 'Connect'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _tunnel.connected ? Colors.red : Colors.indigo,
                            foregroundColor: Colors.white,
                          ),
                          onPressed: () async {
                            if (_tunnel.connected) {
                              await _tunnel.disconnect();
                              _addLog('Tunnel disconnected');
                            } else {
                              final ok = await _tunnel.connect(
                                frontDomain: _domainCtrl.text,
                                hiddenDomain: _hiddenCtrl.text,
                                protocol: _selectedProtocol,
                              );
                              _addLog(ok ? 'Tunnel connected via $_selectedProtocol' : 'Tunnel failed');
                            }
                            setState(() {});
                          },
                        ),
                      ),
                    ],
                  ),
                  if (_tunnel.connected) ...[
                    const SizedBox(height: 8),
                    Text('Active: ${_tunnel.frontDomain} → ${
                      _hiddenCtrl.text.isEmpty ? "(hidden)" : _hiddenCtrl.text
                    }', style: const TextStyle(fontSize: 12, color: Colors.green)),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () {
                              final domains = [
                                'firebase.google.com',
                                'googleapis.com',
                                'cloudfunctions.net',
                                'appspot.com',
                                'windows.net',
                                'azureedge.net',
                                'cdn.cloudflare.net',
                              ];
                              final next = (domains.indexOf(_tunnel.frontDomain) + 1) % domains.length;
                              _domainCtrl.text = domains[next];
                              _tunnel.switchDomain(domains[next]);
                              _addLog('Switched domain: ${domains[next]}');
                              setState(() {});
                            },
                            child: const Text('Rotate Domain', style: TextStyle(fontSize: 12)),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () {
                              final protos = ['websocket', 'grpc', 'google_firebase'];
                              final next = (protos.indexOf(_tunnel.protocol) + 1) % protos.length;
                              setState(() => _selectedProtocol = protos[next]);
                              _tunnel.switchProtocol(protos[next]);
                              _addLog('Switched protocol: ${protos[next]}');
                            },
                            child: const Text('Switch Protocol', style: TextStyle(fontSize: 12)),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),

          const SizedBox(height: 12),

          // ════ LOG ════
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Theme.of(context).brightness == Brightness.dark
                  ? Colors.grey[900] : Colors.grey[100],
              borderRadius: BorderRadius.circular(8),
            ),
            constraints: const BoxConstraints(maxHeight: 150),
            child: SingleChildScrollView(
              child: Text(
                _log.isEmpty ? '[log empty]' : _log,
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 11,
                  color: Theme.of(context).brightness == Brightness.dark
                      ? Colors.grey[400] : Colors.grey[700],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionHeader(String title, IconData icon) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(icon, size: 20, color: Colors.indigo),
          const SizedBox(width: 8),
          Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        ],
      ),
    );
  }

  void _addLog(String msg) {
    setState(() {
      _log = '[${DateTime.now().toString().substring(11, 19)}] $msg\n$_log';
      if (_log.length > 2000) _log = _log.substring(0, 2000);
    });
  }
}
