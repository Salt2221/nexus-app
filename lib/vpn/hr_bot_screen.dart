// ═══════════════════════════════════════════════════════════════
// NEXUS HR Bot — Экран голосового ассистента собеседований
//
// Позволяет:
//   - Ввести голосовую команду вручную (текстом)
//   - Начать/закончить собеседование
//   - Просмотреть историю интервью
//   - Просмотреть текущий этап
// ═══════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'dart:async';

import '../services/hr_bot_service.dart';

class HrBotScreen extends StatefulWidget {
  const HrBotScreen({super.key});

  @override
  State<HrBotScreen> createState() => _HrBotScreenState();
}

class _HrBotScreenState extends State<HrBotScreen> with SingleTickerProviderStateMixin {
  final _bot = HrBotService.instance;
  late TabController _tabController;

  final _commandController = TextEditingController();
  final _positionController = TextEditingController();
  final _nameController = TextEditingController();
  final _ageController = TextEditingController();
  final _stageController = TextEditingController();
  final _totalController = TextEditingController();

  bool _showInput = true;
  bool _showResults = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _bot.addListener(_onBotUpdate);
    _bot.init();
  }

  @override
  void dispose() {
    _bot.removeListener(_onBotUpdate);
    _tabController.dispose();
    _commandController.dispose();
    _positionController.dispose();
    _nameController.dispose();
    _ageController.dispose();
    _stageController.dispose();
    _totalController.dispose();
    super.dispose();
  }

  void _onBotUpdate() => setState(() {});

  // ═══ ПАРСИНГ ГОЛОСОВОЙ КОМАНДЫ ═══

  void _parseCommand() {
    var text = _commandController.text.trim();
    if (text.isEmpty) return;

    var cmd = _bot.parseVoiceCommand(text);
    if (cmd.recognized) {
      _positionController.text = cmd.position;
      _nameController.text = cmd.candidateName;
      _ageController.text = cmd.age.toString();
      _totalController.text = cmd.totalStages.toString();
      _stageController.text = cmd.currentStage.toString();
      _showInput = false;
      setState(() {});
    } else {
      _showSnack('⚠️ Команда не распознана. Нужно: должность, ФИО, возраст, этапы');
    }
  }

  // ═══ НАЧАТЬ СОБЕСЕДОВАНИЕ ═══

  void _startInterview() {
    var cmd = VoiceCommandResult()
      ..position = _positionController.text.trim()
      ..candidateName = _nameController.text.trim()
      ..age = int.tryParse(_ageController.text) ?? 0
      ..totalStages = int.tryParse(_totalController.text) ?? 0
      ..currentStage = int.tryParse(_stageController.text) ?? 1;

    if (!cmd.hasRequired) {
      _showSnack('⚠️ Заполните все поля');
      return;
    }

    _bot.startInterview(cmd);
    _showResults = false;
    setState(() {});
  }

  void _endInterview() {
    _bot.endInterview();
    _showResults = true;
    setState(() {});
  }

  void _cancelInterview() {
    _bot.cancelInterview();
    _showResults = false;
    _showInput = true;
  }

  // ═══ UI ═══

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('HR Ассистент'),
        backgroundColor: Colors.deepPurple.shade900,
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.amber,
          labelColor: Colors.amber,
          unselectedLabelColor: Colors.white70,
          tabs: [
            Tab(text: '🎙️ Интервью'),
            Tab(text: '📋 История'),
            Tab(text: '⚙️ Настройки'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildInterviewTab(),
          _buildHistoryTab(),
          _buildSettingsTab(),
        ],
      ),
    );
  }

  Widget _buildInterviewTab() {
    return SingleChildScrollView(
      padding: EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Статус
          _buildStatusCard(),

          if (_bot.recording) ...[
            SizedBox(height: 16),
            _buildRecordingCard(),
          ],

          if (_bot.analyzing) ...[
            SizedBox(height: 16),
            _buildAnalyzingCard(),
          ],

          if (_showInput && !_bot.recording) ...[
            SizedBox(height: 16),
            _buildInputSection(),
          ],

          if (_showResults && _bot.currentInterview != null) ...[
            SizedBox(height: 16),
            _buildResultsCard(_bot.currentInterview!),
          ],

          SizedBox(height: 16),
          _buildActionButtons(),
        ],
      ),
    );
  }

  Widget _buildStatusCard() {
    return Card(
      color: Colors.deepPurple.shade800,
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(
              _bot.recording ? Icons.mic : Icons.mic_none,
              color: _bot.recording ? Colors.red : Colors.grey,
              size: 32,
            ),
            SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('HR Bot',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  Text(_bot.status,
                      style: TextStyle(color: Colors.grey[400], fontSize: 13)),
                ],
              ),
            ),
            if (_bot.recording)
              Text('${_bot.currentInterview?.stageNumber ?? ""}/'
                  '${_bot.currentInterview?.totalStages ?? ""}',
                  style: TextStyle(fontSize: 18, color: Colors.amber)),
          ],
        ),
      ),
    );
  }

  Widget _buildRecordingCard() {
    return Card(
      color: Colors.red.shade900.withValues(alpha: 0.3),
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(Icons.fiber_manual_record, color: Colors.red, size: 24),
            SizedBox(width: 12),
            Text('Запись...',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            Spacer(),
            Text('${_bot.currentInterview?.candidateName ?? ""}'),
          ],
        ),
      ),
    );
  }

  Widget _buildAnalyzingCard() {
    return Card(
      color: Colors.amber.shade900.withValues(alpha: 0.3),
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Row(
          children: [
            SizedBox(
              width: 24, height: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 12),
            Text('Анализ собеседования...',
                style: TextStyle(fontSize: 16)),
          ],
        ),
      ),
    );
  }

  Widget _buildInputSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Голосовая команда (текстом)
        TextField(
          controller: _commandController,
          decoration: InputDecoration(
            labelText: 'Голосовая команда (текстом)',
            hintText: 'Собеседование на должность..., кандидат ..., возраст ...',
            border: OutlineInputBorder(),
            suffixIcon: IconButton(
              icon: Icon(Icons.send),
              onPressed: _parseCommand,
            ),
          ),
          maxLines: 2,
        ),
        SizedBox(height: 12),
        Text('Или заполните вручную:', style: TextStyle(color: Colors.grey)),
        SizedBox(height: 8),

        // Поля ввода
        TextField(
          controller: _positionController,
          decoration: InputDecoration(labelText: 'Должность', border: OutlineInputBorder()),
        ),
        SizedBox(height: 8),
        TextField(
          controller: _nameController,
          decoration: InputDecoration(labelText: 'ФИО кандидата', border: OutlineInputBorder()),
        ),
        SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _ageController,
                decoration: InputDecoration(labelText: 'Возраст', border: OutlineInputBorder()),
                keyboardType: TextInputType.number,
              ),
            ),
            SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _stageController,
                decoration: InputDecoration(labelText: 'Текущий этап', border: OutlineInputBorder()),
                keyboardType: TextInputType.number,
              ),
            ),
            SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _totalController,
                decoration: InputDecoration(labelText: 'Всего этапов', border: OutlineInputBorder()),
                keyboardType: TextInputType.number,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildActionButtons() {
    if (_bot.recording) {
      return Row(
        children: [
          Expanded(
            child: ElevatedButton.icon(
              onPressed: _endInterview,
              icon: Icon(Icons.stop),
              label: Text('ЗАВЕРШИТЬ СОБЕСЕДОВАНИЕ'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                padding: EdgeInsets.symmetric(vertical: 16),
              ),
            ),
          ),
          SizedBox(width: 8),
          TextButton(
            onPressed: _cancelInterview,
            child: Text('Отмена'),
          ),
        ],
      );
    }

    if (_bot.status == 'completed' && _showResults) {
      return ElevatedButton.icon(
        onPressed: () {
          _cancelInterview();
          _showInput = true;
        },
        icon: Icon(Icons.refresh),
        label: Text('НОВОЕ СОБЕСЕДОВАНИЕ'),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.deepPurple,
          padding: EdgeInsets.symmetric(vertical: 16),
        ),
      );
    }

    return ElevatedButton.icon(
      onPressed: _startInterview,
      icon: Icon(Icons.play_arrow),
      label: Text('НАЧАТЬ СОБЕСЕДОВАНИЕ'),
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.green.shade700,
        padding: EdgeInsets.symmetric(vertical: 16),
      ),
    );
  }

  Widget _buildResultsCard(InterviewStage interview) {
    return Card(
      color: Colors.green.shade900.withValues(alpha: 0.3),
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('📋 Результаты', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            Divider(color: Colors.grey),

            _resultRow('Кандидат', interview.candidateName),
            _resultRow('Должность', interview.position),
            _resultRow('Этап', '${interview.stageNumber}/${interview.totalStages}'),
            SizedBox(height: 8),

            if (interview.thesis.isNotEmpty) ...[
              Text('📝 Тезисы:', style: TextStyle(fontWeight: FontWeight.bold)),
              Container(
                padding: EdgeInsets.all(8),
                margin: EdgeInsets.symmetric(vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.black26,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(interview.thesis, style: TextStyle(fontSize: 13)),
              ),
            ],

            if (interview.decision.isNotEmpty) ...[
              SizedBox(height: 8),
              Text('🔍 Решение:', style: TextStyle(fontWeight: FontWeight.bold)),
              Container(
                padding: EdgeInsets.all(8),
                margin: EdgeInsets.symmetric(vertical: 4),
                decoration: BoxDecoration(
                  color: interview.decision.contains('Переходит')
                      ? Colors.green.shade900.withValues(alpha: 0.3)
                      : Colors.red.shade900.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(interview.decision),
              ),
            ],

            if (interview.questions.isNotEmpty) ...[
              SizedBox(height: 8),
              Text('❓ Вопросы для следующего этапа:', style: TextStyle(fontWeight: FontWeight.bold)),
              ...interview.questions.map((q) => Padding(
                padding: EdgeInsets.only(left: 8, top: 4),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('• ', style: TextStyle(color: Colors.amber)),
                  Expanded(child: Text(q)),
                ]),
              )),
            ],

            if (interview.summary.isNotEmpty) ...[
              SizedBox(height: 8),
              Text('📌 Мнение:', style: TextStyle(fontWeight: FontWeight.bold)),
              Container(
                padding: EdgeInsets.all(8),
                margin: EdgeInsets.symmetric(vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.blue.shade900.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(interview.summary),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _resultRow(String label, String value) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Text('$label: ', style: TextStyle(color: Colors.grey[400])),
          Text(value, style: TextStyle(fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  // ═══ ИСТОРИЯ ═══

  Widget _buildHistoryTab() {
    var history = _bot.history;
    if (history.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.history, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text('История пуста', style: TextStyle(fontSize: 18, color: Colors.grey)),
            Text('Проведите собеседование', style: TextStyle(color: Colors.grey[600])),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: EdgeInsets.all(8),
      itemCount: history.length,
      itemBuilder: (ctx, i) {
        var stage = history[history.length - 1 - i];
        var passed = stage.decision.contains('Переходит');
        return Card(
          color: passed ? Colors.green.shade900.withValues(alpha: 0.2)
                        : Colors.grey.shade800.withValues(alpha: 0.3),
          child: ListTile(
            leading: Icon(
              passed ? Icons.check_circle : Icons.cancel,
              color: passed ? Colors.green : Colors.red,
            ),
            title: Text(stage.candidateName, style: TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text('${stage.position} — этап ${stage.stageNumber}/${stage.totalStages}'),
            trailing: Text(stage.decision.isNotEmpty
                ? stage.decision.split(':')[0]
                : 'не завершено'),
            onTap: () {
              // Показать детали
            },
          ),
        );
      },
    );
  }

  // ═══ НАСТРОЙКИ ═══

  Widget _buildSettingsTab() {
    return Padding(
      padding: EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Настройки HR Bot', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          SizedBox(height: 16),

          Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Яндекс Таблицы', style: TextStyle(fontWeight: FontWeight.bold)),
                  SizedBox(height: 8),
                  TextField(
                    decoration: InputDecoration(
                      labelText: 'ID таблицы',
                      hintText: 'из URL таблицы',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (v) => _spreadsheetId = v,
                  ),
                  SizedBox(height: 8),
                  TextField(
                    decoration: InputDecoration(
                      labelText: 'Название листа',
                      hintText: 'Интервью',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (v) => _sheetName = v,
                  ),
                  SizedBox(height: 16),
                  Text('(API ключи Yandex настраиваются в .env)',
                      style: TextStyle(color: Colors.grey, fontSize: 12)),
                ],
              ),
            ),
          ),

          SizedBox(height: 16),
          Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Статистика', style: TextStyle(fontWeight: FontWeight.bold)),
                  SizedBox(height: 8),
                  Text('Проведено собеседований: ${_bot.interviewCount}'),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String? _spreadsheetId;
  String _sheetName = 'Интервью';

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: Colors.deepPurple,
      duration: Duration(seconds: 3),
    ));
  }
}
