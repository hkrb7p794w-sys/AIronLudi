import 'dart:math' as math;

import 'companion.dart';

/// Punkt im 200 × 200 großen Raster des Avatars.
final class DaisyPoint {
  const DaisyPoint(this.x, this.y);

  final double x;
  final double y;

  @override
  bool operator ==(Object other) => other is DaisyPoint && other.x == x && other.y == y;

  @override
  int get hashCode => Object.hash(x, y);

  @override
  String toString() => 'DaisyPoint($x, $y)';
}

/// Ein Fellstück: Anfangspunkt und pro Zottel eine quadratische Kurve (Kontrollpunkt = Fellspitze).
final class DaisyFur {
  const DaisyFur({required this.start, required this.curves});

  final DaisyPoint start;
  final List<({DaisyPoint control, DaisyPoint end})> curves;
}

/// Animationszustand zu einem Zeitpunkt (Sekunden). Werte in Grad bzw. Einheiten des 200er-Rasters.
final class DaisyPose {
  const DaisyPose({
    required this.headTilt,
    required this.earSwing,
    required this.bounce,
    required this.breath,
    required this.eyesOpen,
    required this.tongue,
    required this.floatPhase,
  });

  final double headTilt;
  final double earSwing;
  final double bounce;
  final double breath;
  final double eyesOpen;
  final bool tongue;

  /// 0…1, für aufsteigende „Zzz“ bzw. funkelnde Sterne.
  final double floatPhase;

  @override
  bool operator ==(Object other) =>
      other is DaisyPose &&
      other.headTilt == headTilt &&
      other.earSwing == earSwing &&
      other.bounce == bounce &&
      other.breath == breath &&
      other.eyesOpen == eyesOpen &&
      other.tongue == tongue &&
      other.floatPhase == floatPhase;

  @override
  int get hashCode => Object.hash(headTilt, earSwing, bounce, breath, eyesOpen, tongue, floatPhase);
}

/// Geometrie des gezeichneten Avatars „Daisy“ (zotteliger, apricotfarbener Terrier-Mix) in einem 200 × 200
/// großen Koordinatensystem. Die App zeichnet daraus Pfade; hier liegt nur die Rechnung, damit sie testbar ist.
abstract final class DaisyGeometry {
  /// Ellipse mit weichen Fellzotteln. [depth] = wie weit die Spitzen über den Rand stehen (Anteil des Radius),
  /// [phase] variiert die Länge der Zotteln, [start]/[end] begrenzen den Bogen (Bogenmaß).
  static DaisyFur fur({
    required DaisyPoint center,
    required double radiusX,
    required double radiusY,
    required int tufts,
    required double depth,
    double phase = 0,
    double start = 0,
    double end = 2 * math.pi,
  }) {
    final count = (tufts < 1 ? 1 : tufts) * 2;
    final points = [
      for (var index = 0; index <= count; index++)
        () {
          final angle = start + (end - start) * index / count;
          final scale = index.isEven ? 1.0 : 1 + depth * (0.75 + 0.25 * math.sin(index * 1.7 + phase));
          return DaisyPoint(center.x + radiusX * scale * math.cos(angle), center.y + radiusY * scale * math.sin(angle));
        }(),
    ];
    return DaisyFur(
      start: points[0],
      curves: [for (var index = 1; index < count; index += 2) (control: points[index], end: points[index + 1])],
    );
  }

  /// Rest wie `truncatingRemainder(dividingBy:)` in Swift (Vorzeichen des Dividenden).
  static double _remainder(double value, double divisor) => value.remainder(divisor);

  static DaisyPose pose(CompanionMood mood, {required double time, bool reduceMotion = false}) {
    final t = reduceMotion ? 0.0 : time;
    // Alle 4 Sekunden kurz blinzeln (nicht im Schlaf).
    final blink = _remainder(t, 4) > 3.85 ? 0.1 : 1.0;
    final breath = math.sin(t * 2) * 0.015;
    return switch (mood) {
      CompanionMood.excited => DaisyPose(
        headTilt: math.sin(t * 1.5) * 4,
        earSwing: math.sin(t * 7) * 9,
        bounce: -(math.sin(t * 3.5)).abs() * 4,
        breath: breath,
        eyesOpen: blink,
        tongue: false,
        floatPhase: 0,
      ),
      CompanionMood.happy => DaisyPose(
        headTilt: math.sin(t * 2) * 3,
        earSwing: math.sin(t * 5) * 6,
        bounce: -(math.sin(t * 3)).abs() * 3,
        breath: breath,
        eyesOpen: blink,
        tongue: true,
        floatPhase: 0,
      ),
      CompanionMood.proud => DaisyPose(
        headTilt: -6 + math.sin(t) * 2,
        earSwing: math.sin(t * 2) * 3,
        bounce: 0,
        breath: breath,
        eyesOpen: blink,
        tongue: false,
        floatPhase: _remainder(t / 2, 1),
      ),
      // Daisys typisches Kopfschiefhalten.
      CompanionMood.hopeful => DaisyPose(
        headTilt: 10 * math.sin(t * 0.8),
        earSwing: math.sin(t * 2) * 4,
        bounce: 0,
        breath: breath,
        eyesOpen: blink,
        tongue: false,
        floatPhase: 0,
      ),
      CompanionMood.resting => DaisyPose(
        headTilt: 4,
        earSwing: 0,
        bounce: 0,
        breath: math.sin(t * 1.2) * 0.03,
        eyesOpen: 0,
        tongue: false,
        floatPhase: _remainder(t / 3, 1),
      ),
      CompanionMood.cozy => DaisyPose(
        headTilt: 6,
        earSwing: math.sin(t) * 2,
        bounce: 0,
        breath: math.sin(t * 1.2) * 0.025,
        eyesOpen: 0.35 * blink,
        tongue: false,
        floatPhase: 0,
      ),
    };
  }
}
