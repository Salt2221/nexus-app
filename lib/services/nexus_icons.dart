// ═══════════════════════════════════════════════════════════════
// NEXUS SVG иконки — кастомные векторные иконки для всех модулей
//
// Все иконки — 24x24 viewBox, вписаны в круг или стилизованы
// Используются вместо стандартных Material Icons
// ═══════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'dart:ui' as ui;

// ═══ БАЗОВЫЙ КЛАСС ИКОНКИ ═══
class NexusIcon extends StatelessWidget {
  final double size;
  final Color color;
  final Object iconKey; // String или IconData

  const NexusIcon(this.iconKey, {super.key, this.size = 24, this.color = Colors.white});

  @override
  Widget build(BuildContext context) {
    if (iconKey is NexusSvgIcon) {
      return _SvgIconWidget(
        svg: iconKey as NexusSvgIcon,
        size: size,
        color: color,
      );
    }
    // fallback на Material icon
    return Icon(iconKey as IconData, size: size, color: color);
  }
}

/// Определение кастомной SVG иконки
class NexusSvgIcon {
  final String Function(Color color) buildPath;
  final String name;

  const NexusSvgIcon({required this.buildPath, required this.name});
}

/// Виджет для рендера SVG иконки
class _SvgIconWidget extends StatelessWidget {
  final NexusSvgIcon svg;
  final double size;
  final Color color;

  const _SvgIconWidget({required this.svg, required this.size, required this.color});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _SvgPainter(svg: svg, color: color),
        size: Size(size, size),
      ),
    );
  }
}

class _SvgPainter extends CustomPainter {
  final NexusSvgIcon svg;
  final Color color;

  _SvgPainter({required this.svg, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = this.color
      ..style = PaintingStyle.fill
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    // Scale to container
    canvas.save();
    final scale = size.width / 24.0;
    canvas.scale(scale, scale);

    // Определяем пути по строковым командам
    final paths = svg.buildPath(color);
    // Парсим SVG path data и рисуем
    _renderSvgPath(canvas, paths, paint);

    canvas.restore();
  }

  void _renderSvgPath(Canvas canvas, String pathData, Paint paint) {
    // Парсинг упрощённого SVG path (M, L, C, Q, A, Z)
    final regExp = RegExp(r'([MLCQAZ])\s*([\d.\-\s,]+)', caseSensitive: true);
    final path = Path();
    var matches = regExp.allMatches(pathData);

    for (var match in matches) {
      var cmd = match.group(1)!;
      var nums = _parseNums(match.group(2)!);

      switch (cmd) {
        case 'M':
          if (nums.length >= 2) path.moveTo(nums[0], nums[1]);
          break;
        case 'L':
          for (var i = 0; i + 1 < nums.length; i += 2) {
            path.lineTo(nums[i], nums[i + 1]);
          }
          break;
        case 'C':
          if (nums.length >= 6) {
            path.cubicTo(nums[0], nums[1], nums[2], nums[3], nums[4], nums[5]);
          }
          break;
        case 'Q':
          if (nums.length >= 4) {
            path.quadraticBezierTo(nums[0], nums[1], nums[2], nums[3]);
          }
          break;
        case 'A':
          // Simplified arc
          break;
        case 'Z':
          path.close();
          break;
      }
    }

    canvas.drawPath(path, paint);
  }

  List<double> _parseNums(String str) {
    return str.trim().split(RegExp(r'[\s,]+')).where((s) => s.isNotEmpty).map(double.parse).toList();
  }

  @override
  bool shouldRepaint(covariant _SvgPainter oldDelegate) =>
      oldDelegate.svg.name != svg.name || oldDelegate.color != color;
}

// ═══ НАБОР ИКОНОК NEXUS ═══

/// VPN Shield — щит с молнией
final nexusVpnIcon = NexusSvgIcon(
  name: 'vpn',
  buildPath: (c) =>
      'M12 2L3 7v6c0 5.25 3.83 10 9 12 5.17-2 9-6.75 9-12V7z '
      'M10 16l-3-3 1.41-1.41L10 13.17l5.59-5.59L17 9z',
);

/// MTProto — космическая тарелка (передача сигнала)
final nexusMtprotoIcon = NexusSvgIcon(
  name: 'mtproto',
  buildPath: (c) =>
      'M12 2C6.48 2 2 6.48 2 12s4.48 10 10 10 10-4.48 10-10S17.52 2 12 2z '
      'M8 14l2-4 4-2-2 4z',
);

/// SOCKS5 — носки (socks), стилизованные
final nexusSocksIcon = NexusSvgIcon(
  name: 'socks',
  buildPath: (c) =>
      'M6 2h12v4H6z M4 6h16v2H4z M5 8h14l-1 12H6z M9 14h6v2H9z',
);

/// DHT / P2P — шестиугольник с точками (сеть)
final nexusP2pIcon = NexusSvgIcon(
  name: 'p2p',
  buildPath: (c) =>
      'M12 2L3 7v10l9 5 9-5V7z M8 12l2 2 4-4',
);

/// Edge Storage — облако с диском
final nexusEdgeIcon = NexusSvgIcon(
  name: 'edge',
  buildPath: (c) =>
      'M19.35 10.04A7.49 7.49 0 0012 4C9.11 4 6.6 5.64 5.35 8.04A5.994 5.994 0 000 14c0 3.31 2.69 6 6 6h13c2.76 0 5-2.24 5-5 0-2.64-2.05-4.78-4.65-4.96z'
      'M12 11v6 M9 14h6',
);

/// Volunteer Compute — чип/процессор с шестерёнкой
final nexusComputeIcon = NexusSvgIcon(
  name: 'compute',
  buildPath: (c) =>
      'M9 3v2H7v2H5v4h2v2h2v2h2v2h4v-2h2v-2h2v-4h-2V7h-2V5h-2V3z '
      'M12 8v4l3 2',
);

/// SDR — радиоволны
final nexusSdrIcon = NexusSvgIcon(
  name: 'sdr',
  buildPath: (c) =>
      'M3.24 6.15C1.56 8.34 1 10.89 1 13.5s.56 5.16 2.24 7.35l1.42-1.42C3.46 17.6 3 15.57 3 13.5s.46-4.1 1.66-5.93z'
      'M6.1 9.36C5.1 10.58 4.5 12.15 4.5 13.5s.6 2.92 1.6 4.14l1.41-1.41c-.6-.78-.96-1.71-.96-2.73s.36-1.95.96-2.73z'
      'M12 12a1.5 1.5 0 100 3 1.5 1.5 0 000-3z'
      'M17.9 9.36l-1.41 1.41c.6.78.96 1.71.96 2.73s-.36 1.95-.96 2.73l1.41 1.41c1-1.22 1.6-2.79 1.6-4.14s-.6-2.92-1.6-4.14z'
      'M20.76 6.15l-1.42 1.42C20.54 9.4 21 11.43 21 13.5s-.46 4.1-1.66 5.93l1.42 1.42C22.44 18.66 23 16.11 23 13.5s-.56-5.16-2.24-7.35z',
);

/// Obfuscation — маска/камуфляж
final nexusObfuscateIcon = NexusSvgIcon(
  name: 'obfuscate',
  buildPath: (c) =>
      'M12 2C8.13 2 5 5.13 5 9c0 2.38 1.19 4.47 3 5.74V17c0 .55.45 1 1 1h6c.55 0 1-.45 1-1v-2.26c1.81-1.27 3-3.36 3-5.74 0-3.87-3.13-7-7-7z'
      'M9 21h6v2H9z',
);

/// DHT Auth / Profile — ключ-карта
final nexusProfileIcon = NexusSvgIcon(
  name: 'profile',
  buildPath: (c) =>
      'M12 12c2.21 0 4-1.79 4-4s-1.79-4-4-4-4 1.79-4 4 1.79 4 4 4z'
      'M12 14c-4.42 0-8 2.69-8 6h16c0-3.31-3.58-6-8-6z'
      'M17 2l1.5 3L22 5.5l-3.5 1.5L17 10l-1.5-3L12 5.5l3.5-1.5z',
);

/// Backend / Database — серверная стойка
final nexusServerIcon = NexusSvgIcon(
  name: 'server',
  buildPath: (c) =>
      'M4 2h16v4H4z M4 8h16v4H4z M4 14h16v4H4z'
      'M8 4h2v2H8z M8 10h2v2H8z M8 16h2v2H8z',
);

/// HR Bot — микрофон с волнами и документом
final nexusHrIcon = NexusSvgIcon(
  name: 'hr',
  buildPath: (c) =>
      'M12 14c-2.67 0-8 1.34-8 4v2h16v-2c0-2.66-5.33-4-8-4z'
      'M12 12a4 4 0 100-8 4 4 0 000 8z'
      'M15 15l2 4-2 1-1-3z',
);

/// Shield — общий щит (для фоллбеков)
final nexusShieldIcon = NexusSvgIcon(
  name: 'shield',
  buildPath: (c) =>
      'M12 1L3 5v6c0 5.55 3.84 10.74 9 12 5.16-1.26 9-6.45 9-12V5z'
      'M10 15.5l-3.5-3.5 1.41-1.41L10 12.67l5.09-5.09L16.5 9z',
);

/// Nexus Logo — стилизованная N с шестерёнкой
final nexusLogoIcon = NexusSvgIcon(
  name: 'nexus_logo',
  buildPath: (c) =>
      'M12 2L2 7l5 3 5-3 5 3 5-3z'
      'M2 17l5 3 5-3 5 3 5-3'
      'M2 12l5 3 5-3 5 3 5-3'
      'M12 22l-5-3v-5l5 3 5-3v5z',
);

// ═══ УТИЛИТЫ ═══

/// Получить иконку для типа модуля
NexusSvgIcon getIconForModule(String moduleName) {
  switch (moduleName.toLowerCase()) {
    case 'vpn':
    case 'tun':
      return nexusVpnIcon;
    case 'mtproto':
      return nexusMtprotoIcon;
    case 'socks':
    case 'socks5':
      return nexusSocksIcon;
    case 'p2p':
    case 'dht':
      return nexusP2pIcon;
    case 'edge':
    case 'edge_storage':
      return nexusEdgeIcon;
    case 'compute':
    case 'computing':
      return nexusComputeIcon;
    case 'sdr':
      return nexusSdrIcon;
    case 'obfuscate':
    case 'obfuscation':
      return nexusObfuscateIcon;
    case 'profile':
    case 'auth':
      return nexusProfileIcon;
    case 'server':
      return nexusServerIcon;
    case 'hr':
    case 'hr_bot':
      return nexusHrIcon;
    case 'shield':
      return nexusShieldIcon;
    default:
      return nexusLogoIcon;
  }
}
