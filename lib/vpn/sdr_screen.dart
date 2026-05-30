import 'dart:math';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../services/sdr_service.dart';

class SdrScreen extends StatefulWidget {
  const SdrScreen({super.key});

  @override
  State<SdrScreen> createState() => _SdrScreenState();
}

class _SdrScreenState extends State<SdrScreen> {
  final _sdr = NexusSdr.instance;

  @override
  void initState() {
    super.initState();
    _sdr.addListener(_onUpdate);
  }

  @override
  void dispose() {
    _sdr.removeListener(_onUpdate);
    super.dispose();
  }

  void _onUpdate() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('📡 SDR — Программное радио'),
        actions: [
          PopupMenuButton<SdrMode>(
            icon: Icon(Icons.settings_input_component),
            onSelected: (mode) {
              if (_sdr.running) _sdr.stop();
              _sdr.start(mode: mode);
            },
            itemBuilder: (_) => [
              PopupMenuItem(value: SdrMode.emulation, child: Text('🎮 Эмуляция')),
              PopupMenuItem(value: SdrMode.rtlSdr, child: Text('📻 RTL-SDR (USB)')),
              PopupMenuItem(value: SdrMode.audio, child: Text('🎤 Аудио SDR')),
            ],
          ),
          IconButton(
            icon: Icon(_sdr.running ? Icons.stop : Icons.play_arrow),
            onPressed: () {
              if (_sdr.running) _sdr.stop();
              else _sdr.start(mode: _sdr.mode);
            },
          ),
        ],
      ),
      body: ListView(
        padding: EdgeInsets.all(12),
        children: [
          // Status
          Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text('Статус: ', style: TextStyle(fontSize: 16)),
                      Text(_sdr.running ? '🟢 Работает' : '🔴 Остановлен',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                      Spacer(),
                      Text('[${_sdr.mode.name}]'),
                    ],
                  ),
                  SizedBox(height: 8),
                  Text('Обнаружено сигналов: ${_sdr.signalsDetected}'),
                ],
              ),
            ),
          ),

          SizedBox(height: 12),

          // Spectrum waterfall
          Card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: EdgeInsets.fromLTRB(12, 12, 12, 0),
                  child: Text('Спектр', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
                SizedBox(height: 4),
                Container(
                  height: 120,
                  child: CustomPaint(
                    size: Size.infinite,
                    painter: _SpectrumPainter(_sdr.spectrum),
                  ),
                ),
              ],
            ),
          ),

          SizedBox(height: 12),

          // Frequency control
          Card(
            child: Padding(
              padding: EdgeInsets.all(12),
              child: Column(
                children: [
                  Text('Частота: ${_sdr.frequencyMHz.toStringAsFixed(3)} MHz',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  Slider(
                    value: _sdr.frequencyMHz,
                    min: 0.5, max: 2000,
                    divisions: 1999,
                    label: '${_sdr.frequencyMHz.toStringAsFixed(1)} MHz',
                    onChanged: (v) => _sdr.setFrequency(v),
                  ),
                  SizedBox(height: 8),
                  Row(
                    children: [
                      Text('Gain: ${(_sdr.gain * 100).toStringAsFixed(0)}%'),
                      Expanded(
                        child: Slider(
                          value: _sdr.gain,
                          min: 0, max: 1,
                          onChanged: (v) => _sdr.setGain(v),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 8),
                  // Demod selector
                  DropdownButtonFormField<DemodMode>(
                    value: _sdr.demod,
                    decoration: InputDecoration(labelText: 'Демодуляция', border: OutlineInputBorder()),
                    items: [
                      DropdownMenuItem(value: DemodMode.fm, child: Text('📻 FM')),
                      DropdownMenuItem(value: DemodMode.am, child: Text('📡 AM')),
                      DropdownMenuItem(value: DemodMode.usb, child: Text('📶 USB')),
                      DropdownMenuItem(value: DemodMode.lsb, child: Text('📶 LSB')),
                      DropdownMenuItem(value: DemodMode.cw, child: Text('📶 CW')),
                    ],
                    onChanged: (v) => _sdr.setDemod(v!),
                  ),
                ],
              ),
            ),
          ),

          SizedBox(height: 12),

          // Quick scan buttons
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ActionChip(
                avatar: Icon(Icons.flight, size: 18),
                label: Text('ADS-B (1090 MHz)'),
                onPressed: () { _sdr.setFrequency(1090); },
              ),
              ActionChip(
                avatar: Icon(Icons.directions_boat, size: 18),
                label: Text('AIS (162 MHz)'),
                onPressed: () { _sdr.setFrequency(162.0); },
              ),
              ActionChip(
                avatar: Icon(Icons.cloud, size: 18),
                label: Text('NOAA (137 MHz)'),
                onPressed: () { _sdr.setFrequency(137.1); },
              ),
              ActionChip(
                avatar: Icon(Icons.radio, size: 18),
                label: Text('FM (100 MHz)'),
                onPressed: () { _sdr.setFrequency(100.0); },
              ),
            ],
          ),

          if (_sdr.running) ...[
            SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    icon: Icon(Icons.search),
                    label: Text('Сканировать всё'),
                    onPressed: () => _sdr.scanAll(),
                  ),
                ),
                SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    icon: Icon(Icons.autorenew),
                    label: Text('Автоскан'),
                    onPressed: () => _sdr.autoScan(),
                  ),
                ),
              ],
            ),
          ],

          Divider(),

          // Signal events
          Text('Обнаруженные сигналы:',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          if (_sdr.signalEvents.isEmpty)
            Padding(
              padding: EdgeInsets.all(16),
              child: Text('Ожидание сигналов...', style: TextStyle(color: Colors.grey)),
            )
          else
            ..._sdr.signalEvents.reversed.map((e) => Card(
              child: ListTile(
                leading: _signalIcon(e.type),
                title: Text(e.label),
                subtitle: Text('${e.frequencyMHz.toStringAsFixed(3)} MHz • сила: ${(e.strength * 100).toStringAsFixed(0)}%'),
                trailing: Text(e.detectedAt.toString().substring(11, 19)),
              ),
            )),
        ],
      ),
    );
  }

  Widget _signalIcon(SignalType t) {
    final icons = {
      SignalType.adsb: Icons.flight,
      SignalType.ais: Icons.directions_boat,
      SignalType.fmRadio: Icons.radio,
      SignalType.amRadio: Icons.wifi_tethering,
      SignalType.sstv: Icons.tv,
      SignalType.weather: Icons.cloud,
      SignalType.unknown: Icons.signal_cellular_alt,
    };
    return Icon(icons[t] ?? Icons.signal_cellular_alt, color: Colors.blue);
  }
}

class _SpectrumPainter extends CustomPainter {
  final List<double> spectrum;

  _SpectrumPainter(this.spectrum);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    final gradient = ui.Gradient.linear(
      Offset(0, 0),
      Offset(size.width, 0),
      [Colors.red, Colors.yellow, Colors.green, Colors.blue, Colors.purple],
    );

    final path = Path();
    final h = size.height;
    final w = size.width;

    path.moveTo(0, h);
    for (int i = 0; i < spectrum.length; i++) {
      final x = (i / spectrum.length) * w;
      final y = h - ((spectrum[i] + 90) / 90) * h;
      path.lineTo(x, y);
    }
    path.lineTo(w, h);
    path.close();

    paint.shader = gradient;
    canvas.drawPath(path, paint..style = PaintingStyle.fill);
  }

  @override
  bool shouldRepaint(covariant _SpectrumPainter old) => true;
}
