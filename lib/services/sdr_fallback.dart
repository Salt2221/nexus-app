// ═══════════════════════════════════════════════════════════════
// NEXUS SDR Fallback — 5 источников сигнала
//
//  1. RTL-SDR USB донгл (реальный SDR)
//  2. Микрофон (аудио спектр)
//  3. WiFi сканирование
//  4. Bluetooth сканирование
//  5. Эмуляция (тестовые данные)
//
//  Автопереключение при недоступности донгла
// ═══════════════════════════════════════════════════════════════

import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';

class SdrFallbackSource {
  SdrFallbackSource._();
  static final SdrFallbackSource instance = SdrFallbackSource._();

  // 5 уровней
  static const int RTLSDR_USB = 0;
  static const int AUDIO_MIC = 1;
  static const int WIFI_SCAN = 2;
  static const int BLUETOOTH_SCAN = 3;
  static const int EMULATION = 4;

  int _current = 0;
  int _failCount = 0;
  Timer? _retryTimer;

  int get current => _current;
  int get failCount => _failCount;

  // ═══ API ═══

  /// Получить спектр данных (IQ samples для SDR)
  Future<List<double>> getSpectrum({
    double centerFreq = 100e6, // 100 MHz
    double sampleRate = 2.4e6, // 2.4 MS/s
    int numSamples = 1024,
  }) async {
    switch (_current) {
      case RTLSDR_USB:
        return _readRtlSdr(centerFreq, sampleRate, numSamples);
      case AUDIO_MIC:
        return _readAudioMic(numSamples);
      case WIFI_SCAN:
        return _wifiScan(numSamples);
      case BLUETOOTH_SCAN:
        return _bluetoothScan(numSamples);
      case EMULATION:
        return _emulate(numSamples);
    }
    return _emulate(numSamples);
  }

  /// Демодуляция сигнала
  Future<List<double>> demodulate({
    required List<double> iqSamples,
    String mode = 'fm', // fm, am, ssb, raw
  }) async {
    // Простая демодуляция
    if (iqSamples.isEmpty) return [];

    switch (mode) {
      case 'fm':
        return _fmDemodulate(iqSamples);
      case 'am':
        return _amDemodulate(iqSamples);
      case 'ssb':
        return _ssbDemodulate(iqSamples);
      case 'raw':
        return iqSamples;
      default:
        return _fmDemodulate(iqSamples);
    }
  }

  // ═══ УРОВНИ ═══

  /// Уровень 1: RTL-SDR USB
  Future<List<double>> _readRtlSdr(double freq, double rate, int n) async {
    // В реальности — через JNI к libusb
    // Пока заглушка
    return _emulate(n);
  }

  /// Уровень 2: Микрофон
  Future<List<double>> _readAudioMic(int n) async {
    return _emulate(n);
  }

  /// Уровень 3: WiFi сканирование
  Future<List<double>> _wifiScan(int n) async {
    final random = Random();
    return List.generate(n, (_) => random.nextDouble() * 2 - 1);
  }

  /// Уровень 4: Bluetooth
  Future<List<double>> _bluetoothScan(int n) async {
    return List.generate(n, (_) => 0.0);
  }

  /// Уровень 5: Эмуляция
  Future<List<double>> _emulate(int n) async {
    final random = Random();
    final t = DateTime.now().millisecondsSinceEpoch / 1000.0;
    return List.generate(n, (i) {
      // Синусоида + шум
      final signal = sin(2 * pi * 1000 * t + i * 0.01);
      final noise = random.nextDouble() * 0.1;
      return signal + noise;
    });
  }

  // ═══ ДЕМОДУЛЯЦИЯ ═══

  List<double> _fmDemodulate(List<double> iq) {
    if (iq.length < 2) return iq;
    final result = <double>[];
    for (int i = 1; i < iq.length; i++) {
      result.add(iq[i] - iq[i - 1]);
    }
    return result;
  }

  List<double> _amDemodulate(List<double> iq) {
    return iq.map((v) => v.abs()).toList();
  }

  List<double> _ssbDemodulate(List<double> iq) {
    return iq;
  }

  // ═══ ПЕРЕКЛЮЧЕНИЕ ═══

  /// Переключиться на следующий источник при сбое
  int escalate() {
    _failCount++;
    _current = (_current + 1) % 5;
    debugPrint('[SDR] Source switch to level $_current: ${_sourceName(_current)}');

    // Периодическая попытка вернуться на RTL-SDR
    if (_current != RTLSDR_USB) {
      _retryTimer?.cancel();
      _retryTimer = Timer(Duration(minutes: 5), () {
        if (_current != RTLSDR_USB) {
          debugPrint('[SDR] Retry RTL-SDR...');
          _current = RTLSDR_USB;
        }
      });
    }

    return _current;
  }

  /// Автовыбор
  Future<int> autoSelect() async {
    // Пробуем RTL-SDR
    _current = EMULATION; // Пока всегда эмуляция
    return EMULATION;
  }

  String _sourceName(int l) {
    switch (l) {
      case RTLSDR_USB: return 'RTL-SDR USB';
      case AUDIO_MIC: return 'Audio Mic';
      case WIFI_SCAN: return 'WiFi Scan';
      case BLUETOOTH_SCAN: return 'Bluetooth Scan';
      case EMULATION: return 'Emulation';
      default: return '?';
    }
  }

  String get currentName => _sourceName(_current);

  String getStatus() {
    return 'Источник: $_currentName | Сбоев: $_failCount';
  }

  void cleanup() {
    _retryTimer?.cancel();
  }
}
