import 'dart:math' as math;

import 'package:coach_core/coach_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// Gezeichnete, animierte Daisy: zotteliger, apricotfarbener Terrier-Mix mit Schlappohren, Bart und wuscheligen Brauen.
/// Die Stimmung bestimmt Bewegung und Zubehör (lila Geschirr beim Losgehen, Blümchen-Halstuch wenn sie stolz ist,
/// „Zzz“ am Ruhetag). Bei „Bewegung reduzieren“ steht sie still (Port von `DaisyAvatar`).
class DaisyAvatar extends StatefulWidget {
  const DaisyAvatar({super.key, required this.mood, this.size = 64});

  final CompanionMood mood;
  final double size;

  @override
  State<DaisyAvatar> createState() => _DaisyAvatarState();
}

class _DaisyAvatarState extends State<DaisyAvatar> with SingleTickerProviderStateMixin {
  late final Ticker _ticker = createTicker((elapsed) => setState(() => _time = elapsed.inMicroseconds / 1e6));
  double _time = 0;
  bool _reduceMotion = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.disableAnimationsOf(context);
    if (_reduceMotion) {
      if (_ticker.isActive) _ticker.stop();
    } else if (!_ticker.isActive && TickerMode.valuesOf(context).enabled) {
      _ticker.start();
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pose = DaisyGeometry.pose(widget.mood, time: _time, reduceMotion: _reduceMotion);
    return Semantics(
      label: 'Daisy',
      image: true,
      child: ClipOval(
        child: SizedBox.square(
          dimension: widget.size,
          child: CustomPaint(
            painter: DaisyPainter(mood: widget.mood, pose: pose),
          ),
        ),
      ),
    );
  }
}

/// Zeichnet Daisy auf 200 × 200 Einheiten (wie der Swift-Canvas).
class DaisyPainter extends CustomPainter {
  const DaisyPainter({required this.mood, required this.pose});

  final CompanionMood mood;
  final DaisyPose pose;

  static const background = Color(0xFFFFF4E6);
  static const fur = Color(0xFFE2B17A);
  static const light = Color(0xFFEFCB98);
  static const cream = Color(0xFFF7E6C8);
  static const ear = Color(0xFFD29A62);
  static const earTip = Color(0xFFB57444);
  static const iris = Color(0xFF6E3510);
  static const pupil = Color(0xFF2A140A);
  static const nose = Color(0xFF2B201D);
  static const line = Color(0xFF5A3A2A);

  static Path furPath(
    double x,
    double y,
    double rx,
    double ry, {
    required int tufts,
    required double depth,
    double phase = 0,
    double start = 0,
    double end = 2 * math.pi,
  }) {
    final shape = DaisyGeometry.fur(
      center: DaisyPoint(x, y),
      radiusX: rx,
      radiusY: ry,
      tufts: tufts,
      depth: depth,
      phase: phase,
      start: start,
      end: end,
    );
    final path = Path()..moveTo(shape.start.x, shape.start.y);
    for (final curve in shape.curves) {
      path.quadraticBezierTo(curve.control.x, curve.control.y, curve.end.x, curve.end.y);
    }
    return path..close();
  }

  static Rect _oval(double x, double y, double rx, double ry) =>
      Rect.fromCenter(center: Offset(x, y), width: rx * 2, height: ry * 2);

  static Paint _fill(Color color) => Paint()..color = color;

  /// Dreht bzw. skaliert um einen Punkt; [draw] zeichnet im veränderten Koordinatensystem.
  static void _around(
    Canvas canvas,
    double x,
    double y,
    void Function() draw, {
    double degrees = 0,
    double scaleY = 1,
  }) {
    canvas
      ..save()
      ..translate(x, y)
      ..rotate(degrees * math.pi / 180)
      ..scale(1, scaleY)
      ..translate(-x, -y);
    draw();
    canvas.restore();
  }

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, _fill(background));
    canvas
      ..save()
      ..scale(size.width / 200, size.height / 200);

    // Körper mit Atmung.
    _around(canvas, 100, 200, scaleY: 1 + pose.breath, () {
      canvas
        ..drawPath(furPath(100, 186, 42, 38, tufts: 14, depth: 0.10), _fill(fur))
        ..drawPath(furPath(100, 182, 24, 24, tufts: 10, depth: 0.10), _fill(cream));
      _accessory(canvas);
    });

    // Kopf: hüpft und neigt sich um den Hals.
    canvas
      ..save()
      ..translate(0, pose.bounce);
    _around(canvas, 100, 140, degrees: pose.headTilt, () {
      for (final side in const [-1.0, 1.0]) {
        final x = 100 + side * 42;
        _around(canvas, x, 68, degrees: side * (-22 + pose.earSwing), () {
          canvas
            ..drawPath(furPath(x, 96, 15, 30, tufts: 9, depth: 0.18, phase: 1), _fill(ear))
            ..drawPath(furPath(x, 112, 13, 14, tufts: 6, depth: 0.22, phase: 2), _fill(earTip));
        });
      }
      canvas
        ..drawPath(furPath(100, 98, 46, 46, tufts: 22, depth: 0.12), _fill(fur))
        ..drawPath(furPath(100, 92, 36, 34, tufts: 18, depth: 0.14, phase: 0.5), _fill(light))
        ..drawPath(
          furPath(100, 56, 22, 10, tufts: 9, depth: 0.55, phase: 0.3, start: math.pi, end: 2 * math.pi),
          _fill(light),
        );
      for (final side in const [-1.0, 1.0]) {
        canvas.drawPath(furPath(100 + side * 19, 84, 11, 5, tufts: 6, depth: 0.45, phase: side), _fill(cream));
      }
      canvas
        ..drawPath(furPath(100, 124, 28, 20, tufts: 14, depth: 0.10), _fill(cream))
        ..drawPath(furPath(100, 138, 20, 12, tufts: 10, depth: 0.35, phase: 0.7, end: math.pi), _fill(cream));

      _eyes(canvas);

      final nosePath = Path()
        ..moveTo(88, 114)
        ..quadraticBezierTo(100, 107, 112, 114)
        ..quadraticBezierTo(112, 124, 100, 126)
        ..quadraticBezierTo(88, 124, 88, 114);
      canvas
        ..drawPath(nosePath, _fill(nose))
        ..drawOval(_oval(95, 113, 3.4, 1.8), _fill(const Color(0xFF6C5A55)));

      if (pose.tongue) {
        final tongue = Path()
          ..moveTo(93, 132)
          ..quadraticBezierTo(100, 138, 107, 132)
          ..quadraticBezierTo(100, 152, 93, 132);
        canvas.drawPath(tongue, _fill(const Color(0xFFEF8A95)));
      }
      final mouth = Path()
        ..moveTo(100, 126)
        ..lineTo(100, 132)
        ..quadraticBezierTo(93, 138, 86, 133)
        ..moveTo(100, 132)
        ..quadraticBezierTo(107, 138, 114, 133);
      canvas.drawPath(
        mouth,
        Paint()
          ..color = line
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..strokeCap = StrokeCap.round,
      );
      for (final side in const [-1.0, 1.0]) {
        canvas.drawOval(_oval(100 + side * 28, 118, 7, 4), _fill(const Color(0xFFF3A7A0).withValues(alpha: 0.45)));
      }
    });
    canvas.restore();

    _floats(canvas);
    canvas.restore();
  }

  void _eyes(Canvas canvas) {
    for (final side in const [-1.0, 1.0]) {
      final x = 100 + side * 19;
      if (pose.eyesOpen < 0.2) {
        final lid = Path()
          ..moveTo(x - 8, 98)
          ..quadraticBezierTo(x, 104, x + 8, 98);
        canvas.drawPath(
          lid,
          Paint()
            ..color = const Color(0xFF3A1E10)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.5
            ..strokeCap = StrokeCap.round,
        );
        continue;
      }
      _around(canvas, x, 98, scaleY: pose.eyesOpen, () {
        canvas
          ..drawOval(_oval(x, 98, 9.5, 9.5), _fill(iris))
          ..drawOval(_oval(x, 99, 6, 6), _fill(pupil))
          ..drawOval(_oval(x + 3, 95, 2.8, 2.8), _fill(Colors.white))
          ..drawOval(_oval(x - 3, 102, 1.2, 1.2), _fill(Colors.white.withValues(alpha: 0.7)));
      });
    }
  }

  void _accessory(Canvas canvas) {
    switch (mood) {
      case CompanionMood.excited || CompanionMood.hopeful:
        // Lila Geschirr für den Spaziergang.
        final strap = Path()
          ..moveTo(62, 160)
          ..quadraticBezierTo(100, 176, 138, 160);
        canvas
          ..drawPath(
            strap,
            Paint()
              ..color = const Color(0xFFA77BE0)
              ..style = PaintingStyle.stroke
              ..strokeWidth = 9
              ..strokeCap = StrokeCap.round,
          )
          ..drawOval(_oval(100, 171, 5, 5), _fill(const Color(0xFF8F63CF)));
      case CompanionMood.proud:
        // Hellblaues Halstuch mit Blümchen.
        final scarf = Path()
          ..moveTo(58, 150)
          ..quadraticBezierTo(100, 166, 142, 150)
          ..lineTo(100, 198)
          ..close();
        canvas.drawPath(scarf, _fill(const Color(0xFF9ED3EF)));
        const flowers = [
          (88.0, 163.0, Color(0xFFF06FA0)),
          (108.0, 171.0, Color(0xFFF7D046)),
          (100.0, 184.0, Color(0xFF5B8FE0)),
          (120.0, 160.0, Color(0xFFF06FA0)),
          (78.0, 157.0, Color(0xFF5B8FE0)),
          (96.0, 175.0, Color(0xFFF06FA0)),
        ];
        for (final (x, y, color) in flowers) {
          canvas.drawOval(_oval(x, y, 2.6, 2.6), _fill(color));
        }
      case CompanionMood.happy || CompanionMood.resting || CompanionMood.cozy:
        break;
    }
  }

  static void _text(Canvas canvas, String text, Offset center, TextStyle style) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(canvas, center - Offset(painter.width / 2, painter.height / 2));
  }

  void _floats(Canvas canvas) {
    final phase = pose.floatPhase;
    switch (mood) {
      case CompanionMood.resting:
        // Drei „z“, die nacheinander aufsteigen und verblassen.
        for (var index = 0; index < 3; index++) {
          final local = (phase + index / 3) % 1;
          _text(
            canvas,
            'z',
            Offset(150 + 14 * local, 60 - 40 * local),
            TextStyle(
              fontSize: 14 + 6 * local,
              fontWeight: FontWeight.bold,
              color: const Color(0xFF7C8BD8).withValues(alpha: 1 - local),
            ),
          );
        }
      case CompanionMood.proud:
        const points = [Offset(38, 40), Offset(164, 34), Offset(170, 120)];
        for (final (index, point) in points.indexed) {
          final local = (phase + index / 3) % 1;
          final strength = math.sin(local * math.pi);
          _text(
            canvas,
            '✦',
            point,
            TextStyle(
              fontSize: 12 + 8 * strength,
              color: const Color(0xFFF7C948).withValues(alpha: strength),
            ),
          );
        }
      case CompanionMood.happy || CompanionMood.excited || CompanionMood.hopeful || CompanionMood.cozy:
        break;
    }
  }

  @override
  bool shouldRepaint(DaisyPainter oldDelegate) => oldDelegate.mood != mood || oldDelegate.pose != pose;
}
