import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../services/edge_storage.dart';

class EdgeStorageScreen extends StatefulWidget {
  const EdgeStorageScreen({super.key});

  @override
  State<EdgeStorageScreen> createState() => _EdgeStorageScreenState();
}

class _EdgeStorageScreenState extends State<EdgeStorageScreen> {
  final _storage = NexusEdgeStorage.instance;
  final _nameController = TextEditingController();
  final _contentController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _storage.addListener(_onUpdate);
  }

  @override
  void dispose() {
    _storage.removeListener(_onUpdate);
    _nameController.dispose();
    _contentController.dispose();
    super.dispose();
  }

  void _onUpdate() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('☁️ Edge Storage'),
        actions: [
          IconButton(
            icon: Icon(_storage.running ? Icons.stop : Icons.play_arrow),
            onPressed: () {
              if (_storage.running) _storage.stop();
              else _storage.start();
            },
          ),
        ],
      ),
      body: ListView(
        padding: EdgeInsets.all(16),
        children: [
          // Status card
          Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Статус: ${_storage.running ? "🟢 Работает" : "🔴 Остановлен"}',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  SizedBox(height: 8),
                  Text('Пиров в сети: ${_storage.totalPeers}'),
                  Text('Файлов: ${_storage.totalFiles}'),
                  Text('Блоков: ${_storage.totalBlocks}'),
                  Text('Использовано: ${_storage.usedStorageKB} KB'),
                ],
              ),
            ),
          ),

          SizedBox(height: 16),

          // Active peers
          if (_storage.peers.isNotEmpty) ...[
            Text('Пиры:', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ..._storage.peers.map((p) => ListTile(
              leading: Icon(Icons.computer),
              title: Text(p.name),
              subtitle: Text('${p.address}:${p.port} • ${p.blocks} блоков'),
            )),
            Divider(),
          ],

          // Add file
          Text('Добавить файл:', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          TextField(
            controller: _nameController,
            decoration: InputDecoration(labelText: 'Имя файла', border: OutlineInputBorder()),
          ),
          SizedBox(height: 8),
          TextField(
            controller: _contentController,
            maxLines: 3,
            decoration: InputDecoration(labelText: 'Содержимое', border: OutlineInputBorder()),
          ),
          SizedBox(height: 8),
          ElevatedButton.icon(
            icon: Icon(Icons.save),
            label: Text('Сохранить (Zero-Knowledge)'),
            onPressed: () async {
              if (_nameController.text.isEmpty) return;
              final data = _contentController.text.codeUnits;
              await _storage.addFile(
                _nameController.text,
                Uint8List.fromList(data),
              );
              _nameController.clear();
              _contentController.clear();
            },
          ),

          Divider(),

          // Local files
          Text('Локальные файлы:', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          if (_storage.localFiles.isEmpty)
            Padding(
              padding: EdgeInsets.all(16),
              child: Text('Нет файлов', style: TextStyle(color: Colors.grey)),
            )
          else
            ..._storage.localFiles.map((f) => ListTile(
              leading: Icon(Icons.insert_drive_file),
              title: Text(f.name),
              subtitle: Text('${f.sizeFormatted} • блок: ${f.blockId.substring(0, 8)}...'),
            )),
        ],
      ),
    );
  }
}
