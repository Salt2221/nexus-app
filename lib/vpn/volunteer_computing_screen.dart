import 'dart:math';
import 'package:flutter/material.dart';
import '../services/volunteer_computing.dart';
import '../services/edge_storage.dart';

class VolunteerComputingScreen extends StatefulWidget {
  const VolunteerComputingScreen({super.key});

  @override
  State<VolunteerComputingScreen> createState() => _VolunteerComputingScreenState();
}

class _VolunteerComputingScreenState extends State<VolunteerComputingScreen> {
  final _compute = NexusVolunteerComputing.instance;
  ComputeTaskType _selectedTask = ComputeTaskType.piDigits;
  final _paramsController = TextEditingController(text: '1000');
  int _chunks = 4;

  @override
  void initState() {
    super.initState();
    _compute.addListener(_onUpdate);
  }

  @override
  void dispose() {
    _compute.removeListener(_onUpdate);
    _paramsController.dispose();
    super.dispose();
  }

  void _onUpdate() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('🧮 Volunteer Computing'),
        actions: [
          IconButton(
            icon: Icon(_compute.running ? Icons.stop : Icons.play_arrow),
            onPressed: () {
              if (_compute.running) _compute.stop();
              else _compute.start();
            },
          ),
        ],
      ),
      body: ListView(
        padding: EdgeInsets.all(16),
        children: [
          // Status
          Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Статус: ${_compute.running ? "🟢 Работает" : "🔴 Остановлен"}',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  SizedBox(height: 8),
                  Text('Воркеров: ${_compute.workerCount}'),
                  Text('Активных задач: ${_compute.activeJobs}'),
                  Text('Завершено: ${_compute.completedJobs}'),
                ],
              ),
            ),
          ),

          SizedBox(height: 16),

          // Controls
          Text('Новая задача:', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          SizedBox(height: 8),

          DropdownButtonFormField<ComputeTaskType>(
            value: _selectedTask,
            decoration: InputDecoration(labelText: 'Тип задачи', border: OutlineInputBorder()),
            items: [
              DropdownMenuItem(value: ComputeTaskType.piDigits, child: Text('π (число Пи)')),
              DropdownMenuItem(value: ComputeTaskType.primeSearch, child: Text('Поиск простых чисел')),
              DropdownMenuItem(value: ComputeTaskType.matrixMul, child: Text('Умножение матриц')),
              DropdownMenuItem(value: ComputeTaskType.hashBrute, child: Text('Hash brute-force')),
              DropdownMenuItem(value: ComputeTaskType.custom, child: Text('Пользовательская')),
            ],
            onChanged: (v) => setState(() => _selectedTask = v!),
          ),

          SizedBox(height: 8),

          TextField(
            controller: _paramsController,
            decoration: InputDecoration(
              labelText: 'Параметры (размер / диапазон)',
              border: OutlineInputBorder(),
            ),
          ),

          SizedBox(height: 8),

          Row(
            children: [
              Text('Чанков: $_chunks  '),
              Slider(
                value: _chunks.toDouble(),
                min: 1, max: 16, divisions: 15,
                label: '$_chunks',
                onChanged: (v) => setState(() => _chunks = v.toInt()),
              ),
            ],
          ),

          ElevatedButton.icon(
            icon: Icon(Icons.play_arrow),
            label: Text('Запустить задачу'),
            onPressed: () {
              final task = _compute.createTask(
                _selectedTask,
                _paramsController.text,
                chunks: _chunks,
              );
              _compute.executeTask(task);
            },
          ),

          Divider(),

          // Tasks
          Text('Задачи:', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          if (_compute.tasks.isEmpty)
            Padding(
              padding: EdgeInsets.all(16),
              child: Text('Нет задач', style: TextStyle(color: Colors.grey)),
            )
          else
            ..._compute.tasks.reversed.map((t) => Card(
              child: ListTile(
                leading: Icon(_taskIcon(t.type)),
                title: Text('${t.type.name} (${t.chunks} чанков)'),
                subtitle: Text('${t.params} • статус: ${t.status}'),
                trailing: t.status == 'running'
                  ? SizedBox(
                      width: 20, height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : Icon(t.status == 'completed'
                      ? Icons.check_circle : Icons.pending,
                      color: t.status == 'completed' ? Colors.green : Colors.orange),
              ),
            )),

          Divider(),

          // Results
          Text('Результаты:', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          if (_compute.results.isEmpty)
            Padding(
              padding: EdgeInsets.all(16),
              child: Text('Нет результатов', style: TextStyle(color: Colors.grey)),
            )
          else
            ..._compute.results.map((r) => Card(
              child: ListTile(
                title: Text('Чанк ${r.chunk} от ${r.taskId.substring(0, 12)}...'),
                subtitle: Text('${r.data}'),
              ),
            )),
        ],
      ),
    );
  }

  IconData _taskIcon(ComputeTaskType t) {
    switch (t) {
      case ComputeTaskType.piDigits: return Icons.format_list_numbered;
      case ComputeTaskType.hashBrute: return Icons.lock;
      case ComputeTaskType.matrixMul: return Icons.grid_on;
      case ComputeTaskType.primeSearch: return Icons.looks_3;
      case ComputeTaskType.custom: return Icons.code;
    }
  }
}
