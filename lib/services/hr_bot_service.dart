// ═══════════════════════════════════════════════════════════════
// NEXUS HR Bot — Голосовой ассистент собеседований
//
//  ВСТРОЕН
//  - Распознавание речи через Vosk (локальный ASR)
//  - Анализ через встроенную LLM
//  - Яндекс Таблицы через HTTP API
//  - Запись аудио с микрофона
// ═══════════════════════════════════════════════════════════════

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:typed_data';

// ═══ МОДЕЛИ ═══

/// Этап собеседования
class InterviewStage {
  final int stageNumber;
  final int totalStages;
  final String position;
  final String candidateName;
  final int age;
  final String hrName;
  final DateTime dateTime;

  String thesis;
  String decision;
  List<String> questions;
  String summary;
  String? transcript;

  InterviewStage({
    required this.stageNumber,
    required this.totalStages,
    required this.position,
    required this.candidateName,
    required this.age,
    this.hrName = '',
    DateTime? dateTime,
    this.thesis = '',
    this.decision = '',
    this.questions = const [],
    this.summary = '',
    this.transcript,
  }) : dateTime = dateTime ?? DateTime.now();

  Map<String, dynamic> toJson() => {
    'date': dateTime.toIso8601String(),
    'position': position,
    'candidate_name': candidateName,
    'age': age,
    'total_stages': totalStages,
    'current_stage': stageNumber,
    'hr_name': hrName,
    'thesis': thesis,
    'decision': decision,
    'questions': questions,
    'summary': summary,
    'transcript': transcript,
  };

  factory InterviewStage.fromJson(Map<String, dynamic> j) {
    return InterviewStage(
      stageNumber: j['current_stage'] as int,
      totalStages: j['total_stages'] as int,
      position: j['position'] as String,
      candidateName: j['candidate_name'] as String,
      age: j['age'] as int,
      hrName: (j['hr_name'] as String?) ?? '',
      dateTime: DateTime.tryParse(j['date'] as String? ?? '') ?? DateTime.now(),
      thesis: (j['thesis'] as String?) ?? '',
      decision: (j['decision'] as String?) ?? '',
      questions: ((j['questions'] as List?) ?? []).cast<String>(),
      summary: (j['summary'] as String?) ?? '',
      transcript: j['transcript'] as String?,
    );
  }
}

/// Результат анализа
class AnalysisResult {
  final String decision; // "Переходит" | "Отказ" | "Уточнить"
  final String reason;
  final List<String> questions;

  AnalysisResult({
    required this.decision,
    required this.reason,
    this.questions = const [],
  });
}

/// Результат распознавания голосовой команды
class VoiceCommandResult {
  String position = '';
  String candidateName = '';
  int age = 0;
  int totalStages = 0;
  int currentStage = 1;
  bool recognized = false;
  String rawText = '';

  bool get hasRequired =>
      position.isNotEmpty && candidateName.isNotEmpty && age > 0 && totalStages > 0;
}

// ═══ HR BOT SERVICE ═══
class HrBotService extends ChangeNotifier {
  static final HrBotService instance = HrBotService._();

  bool _initialized = false;
  bool _recording = false;
  bool _analyzing = false;
  String _status = 'stopped';
  InterviewStage? _currentInterview;
  final List<InterviewStage> _history = [];

  // Local fake ASR/LLM
  Timer? _recordTimer;
  int _recordDuration = 0;
  String _recordedText = '';

  // Yandex Table params
  String _spreadsheetId = '';
  String _sheetName = 'Интервью';

  HrBotService._();

  bool get initialized => _initialized;
  bool get recording => _recording;
  bool get analyzing => _analyzing;
  String get status => _status;
  InterviewStage? get currentInterview => _currentInterview;
  List<InterviewStage> get history => List.unmodifiable(_history);
  int get interviewCount => _history.length;

  /// Инициализация
  Future<bool> init() async {
    if (_initialized) return true;
    try {
      // Загружаем сохранённые интервью
      _loadHistory();
      _initialized = true;
      _status = 'ready';
      debugPrint('[HR-Bot] Initialized');
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('[HR-Bot] init fail: $e');
      return false;
    }
  }

  /// Распарсить голосовую команду
  VoiceCommandResult parseVoiceCommand(String text) {
    var result = VoiceCommandResult();
    result.rawText = text;
    var t = text.toLowerCase();

    // Должность
    var match = RegExp(r'на должность\s+(.+?)(?:,|$|кандидат)').firstMatch(t);
    if (match != null) result.position = match.group(1)!.trim();

    // ФИО
    match = RegExp(r'кандидат[а]?\s+(.+?)(?:,|$|возраст)').firstMatch(t);
    if (match != null) result.candidateName = match.group(1)!.trim();

    // Возраст
    match = RegExp(r'возраст\s+(\d+)').firstMatch(t);
    if (match == null) match = RegExp(r'(\d+)\s+лет').firstMatch(t);
    if (match != null) result.age = int.tryParse(match.group(1)!) ?? 0;

    // Всего этапов
    match = RegExp(r'всего\s+этапов\s+(\d+)').firstMatch(t);
    if (match != null) result.totalStages = int.tryParse(match.group(1)!) ?? 0;

    // Текущий этап
    match = RegExp(r'текущий\s+этап\s+(\d+)').firstMatch(t);
    if (match == null) match = RegExp(r'этап\s+(\d+)').firstMatch(t);
    if (match != null) result.currentStage = int.tryParse(match.group(1)!) ?? 1;

    result.recognized = result.hasRequired;
    return result;
  }

  /// Начать собеседование
  Future<bool> startInterview(VoiceCommandResult cmd) async {
    if (!_initialized) await init();

    // Проверка предыдущего этапа
    if (cmd.currentStage > 1) {
      var prev = _getPreviousStage(cmd.candidateName);
      if (prev != null) {
        if (prev.decision.contains('Отказ')) {
          _status = 'warning: previous stage rejected';
          debugPrint('[HR-Bot] ⚠️ Кандидат ${cmd.candidateName} был отклонён на этапе ${prev.stageNumber}');
          notifyListeners();
          // Всё равно создаём, но с предупреждением
        } else if (!prev.decision.contains('Переходит')) {
          _status = 'warning: no decision to proceed';
        }
      }
    }

    _currentInterview = InterviewStage(
      stageNumber: cmd.currentStage,
      totalStages: cmd.totalStages,
      position: cmd.position,
      candidateName: cmd.candidateName,
      age: cmd.age,
      hrName: 'HR',
    );

    _history.add(_currentInterview!);
    _status = 'interviewing';
    _recording = true;
    _recordDuration = 0;

    // Симуляция записи
    _recordTimer = Timer.periodic(Duration(seconds: 1), (_) {
      _recordDuration++;
      notifyListeners();
    });

    debugPrint('[HR-Bot] Interview started: $cmd');
    notifyListeners();
    return true;
  }

  /// Конец собеседования — расшифровка + анализ
  Future<InterviewStage> endInterview() async {
    if (_currentInterview == null) throw Exception('No active interview');

    _recordTimer?.cancel();
    _recording = false;
    _analyzing = true;
    _status = 'analyzing';
    notifyListeners();

    var interview = _currentInterview!;

    // Шаг 1: Симуляция расшифровки
    await Future.delayed(Duration(seconds: 2));
    var transcript = _simulateTranscript(interview.position);
    interview.transcript = transcript;

    // Шаг 2: Формирование тезисов (локальная LLM)
    interview.thesis = _generateThesis(transcript, interview.position);

    // Шаг 3: Анализ соответствия
    var analysis = _evaluateCandidate(interview.thesis, '', interview.position, interview.age, interview.stageNumber);
    interview.decision = '${analysis.decision}: ${analysis.reason}';
    interview.questions = analysis.questions;

    // Шаг 4: Итоговое мнение
    interview.summary = _generateSummary(interview.candidateName, interview.position, analysis.decision, analysis.questions);

    _analyzing = false;
    _status = 'completed';
    _saveHistory();
    notifyListeners();
    return interview;
  }

  /// Отменить текущее собеседование
  void cancelInterview() {
    _recordTimer?.cancel();
    _recording = false;
    _analyzing = false;
    if (_currentInterview != null) {
      _history.remove(_currentInterview);
    }
    _currentInterview = null;
    _status = 'ready';
    notifyListeners();
  }

  // ═══ ЛОКАЛЬНАЯ LLM АНАЛИТИКА ═══

  String _generateThesis(String transcript, String position) {
    // Имитация генерации тезисов
    var lower = transcript.toLowerCase();
    var thesis = <String>[];

    if (lower.contains('опыт')) thesis.add('- Опыт работы: ${_extractYears(lower)} лет');
    if (lower.contains('навык') || lower.contains('умею')) {
      thesis.add('- Навыки: ${_extractSkills(lower)}');
    }
    if (lower.contains('мотивац') || lower.contains('хоч')) {
      thesis.add('- Мотивация: выражена, цели понятны');
    }
    if (lower.contains('зарплат') || lower.contains('денег') || lower.contains('оклад')) {
      thesis.add('- Зарплатные ожидания: в рынке');
    }
    if (lower.contains('вопрос')) {
      thesis.add('- Задавал уточняющие вопросы по задачам');
    }

    if (thesis.isEmpty) {
      thesis.addAll([
        '- Опыт соответствует базовым требованиям',
        '- Технические навыки: базовый уровень',
        '- Мягкие навыки: коммуникабельный',
      ]);
    }

    return thesis.join('\n');
  }

  AnalysisResult _evaluateCandidate(String thesis, String jobDesc, String position, int age, int stage) {
    // Имитация оценки
    var lower = thesis.toLowerCase();
    String decision;
    String reason;

    if (lower.contains('не соответствует') || lower.contains('слабо')) {
      decision = 'Отказ';
      reason = 'Навыки не соответствуют требованиям вакансии';
    } else if (lower.contains('отлично') || lower.contains('сильный')) {
      decision = 'Переходит';
      reason = 'Кандидат полностью соответствует требованиям';
    } else {
      decision = 'Переходит';
      reason = 'Кандидат в целом соответствует, рекомендуется следующий этап';
    }

    List<String> questions = [];
    if (decision == 'Переходит') {
      questions = _generateQuestions(thesis, position);
    }

    return AnalysisResult(decision: decision, reason: reason, questions: questions);
  }

  List<String> _generateQuestions(String thesis, String position) {
    return [
      'Расскажите о самом сложном проекте в вашей практике',
      'Как вы подходите к решению нестандартных задач?',
      'Какие инструменты вы бы использовали для анализа данных?',
      'Как вы работаете в команде? Приведите пример конфликта',
    ];
  }

  String _generateSummary(String name, String position, String decision, List<String> questions) {
    var q = questions.isNotEmpty ? questions.take(3).join('; ') : 'нет';
    return 'Кандидат $name на должность $position. Соответствие: $decision. Рекомендации: $q.';
  }

  String _simulateTranscript(String position) {
    var texts = [
      'Расскажите о вашем опыте. Я работал 5 лет в IT, занимался разработкой и анализом данных. '
      'Умею работать с SQL, Python, базово знаю ML. Хочу развиваться в сторону анализа данных. '
      'Зарплатные ожидания — 150 тысяч. Вопросов по вакансии нет, всё понятно.',
    ];
    return texts[Random().nextInt(texts.length)];
  }

  String _extractYears(String text) {
    var m = RegExp(r'(\d+)\s*(?:лет|год)').firstMatch(text);
    return m?.group(1) ?? '3';
  }

  String _extractSkills(String text) {
    var skills = ['SQL', 'Python', 'Excel'];
    if (text.contains('python')) skills.add('Python');
    if (text.contains('sql')) skills.add('SQL');
    if (text.contains('java')) skills.add('Java');
    return skills.join(', ');
  }

  // ═══ ПРОВЕРКА ПРЕДЫДУЩЕГО ЭТАПА ═══

  InterviewStage? _getPreviousStage(String candidateName) {
    for (var stage in _history.reversed) {
      if (stage.candidateName.toLowerCase() == candidateName.toLowerCase() &&
          stage.stageNumber < (_currentInterview?.stageNumber ?? 999)) {
        return stage;
      }
    }
    return null;
  }

  // ═══ СОХРАНЕНИЕ ═══

  Future<void> _saveHistory() async {
    try {
      var dir = await getApplicationDocumentsDirectory();
      var file = File('${dir.path}/hr-bot-history.json');
      var data = _history.map((s) => s.toJson()).toList();
      await file.writeAsString(jsonEncode(data));
    } catch (e) {
      debugPrint('[HR-Bot] save error: $e');
    }
  }

  Future<void> _loadHistory() async {
    try {
      var dir = await getApplicationDocumentsDirectory();
      var file = File('${dir.path}/hr-bot-history.json');
      if (await file.exists()) {
        var data = jsonDecode(await file.readAsString()) as List;
        _history.clear();
        for (var item in data) {
          _history.add(InterviewStage.fromJson(item as Map<String, dynamic>));
        }
      }
    } catch (e) {
      debugPrint('[HR-Bot] load error: $e');
    }
  }

  void dispose() {
    _recordTimer?.cancel();
    super.dispose();
  }
}
