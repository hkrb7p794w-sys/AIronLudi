import 'dart:math' as math;

import 'package:coach_core/coach_core.dart';
import 'package:flutter/material.dart';

import 'liquid.dart';

/// Ampelfarbe einer Kennzahl: Grün im Zielbereich, Orange für Aufmerksamkeit, Rot kritisch, Grau ohne Daten.
Color kpiColor(KpiStatus status) => switch (status) {
  KpiStatus.good => const Color(0xFF30D158),
  KpiStatus.moderate => const Color(0xFFFF9F0A),
  KpiStatus.critical => const Color(0xFFFF453A),
  KpiStatus.unknown => const Color(0xFF8E8E93),
};

/// Ring mit Anteil (voll) und optional zweitem, hellem Abschnitt (z. B. noch geplant). Die Füllung ist ein leuchtender
/// Verlauf der Statusfarbe und läuft beim Erscheinen und bei jeder Änderung mit einer Feder auf ihren Wert.
class ProgressRing extends StatelessWidget {
  const ProgressRing({
    super.key,
    required this.fraction,
    required this.color,
    this.secondary,
    this.size = 84,
    this.stroke = 9,
    this.child,
  });

  final double fraction;
  final double? secondary;
  final Color color;
  final double size;
  final double stroke;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final target = fraction.clamp(0.0, 1.0);
    final second = secondary?.clamp(0.0, 1.0);
    final track = LiquidTheme.of(context).track;
    return SizedBox.square(
      dimension: size,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: target),
        duration: LiquidMotion.of(context, LiquidMotion.slow),
        curve: LiquidMotion.settle,
        builder: (context, value, child) => CustomPaint(
          painter: _RingPainter(
            fraction: value,
            secondary: second == null || target <= 0 ? second : second * (value / target).clamp(0.0, 1.0),
            color: color,
            track: track,
            stroke: stroke,
          ),
          child: child,
        ),
        child: Center(child: child),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({
    required this.fraction,
    required this.secondary,
    required this.color,
    required this.track,
    required this.stroke,
  });

  final double fraction;
  final double? secondary;
  final Color color;
  final Color track;
  final double stroke;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final arc = rect.deflate(stroke / 2);
    Paint paint() => Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(arc, 0, 2 * math.pi, false, paint()..color = track);
    const start = -math.pi / 2;
    if (secondary case final second? when second > fraction) {
      canvas.drawArc(arc, start, 2 * math.pi * second, false, paint()..color = color.withValues(alpha: 0.28));
    }
    if (fraction <= 0) return;
    final sweep = 2 * math.pi * math.max(fraction, 0.01);
    final colors = LiquidGradients.of(color);
    // Verlauf entlang des Bogens: vom hellen Anfang zur satten Spitze.
    final shader = SweepGradient(
      startAngle: 0,
      endAngle: math.max(sweep, 0.0001),
      colors: [colors[0], colors[1], colors[2]],
      stops: const [0, 0.6, 1],
      transform: const GradientRotation(start),
    ).createShader(rect);
    // Weiches Leuchten unter dem Bogen.
    canvas.drawArc(
      arc,
      start,
      sweep,
      false,
      paint()
        ..color = color.withValues(alpha: 0.35)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, stroke * 0.6),
    );
    canvas.drawArc(arc, start, sweep, false, paint()..shader = shader);
    // Heller Punkt an der Spitze wie ein Lichtreflex.
    final tipAngle = start + sweep;
    final radius = arc.width / 2;
    final tip = arc.center + Offset(math.cos(tipAngle), math.sin(tipAngle)) * radius;
    canvas.drawCircle(tip, stroke * 0.22, Paint()..color = Colors.white.withValues(alpha: 0.55));
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.fraction != fraction || old.secondary != secondary || old.color != color || old.track != track;
}

/// Kennzahl als Ring mit Wert in der Mitte, Titel darüber und kurzer Zeile darunter.
class KpiRing extends StatelessWidget {
  const KpiRing({super.key, required this.kpi, this.onTap, this.size = 84});

  final Kpi kpi;
  final VoidCallback? onTap;
  final double size;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = kpiColor(kpi.status);
    return Semantics(
      button: onTap != null,
      label: '${kpi.title}: ${kpi.value}, ${kpi.caption}',
      excludeSemantics: true,
      child: LiquidPressable(
        scale: 0.95,
        child: InkWell(
          borderRadius: BorderRadius.circular(LiquidRadii.inner),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              spacing: 6,
              children: [
                Text(kpi.title, style: LiquidText.label(context).copyWith(fontWeight: FontWeight.w600)),
                ProgressRing(
                  fraction: kpi.fraction,
                  secondary: kpi.secondaryFraction,
                  color: color,
                  size: size,
                  child: FittedBox(
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Text(
                        kpi.value,
                        style: LiquidText.kpi(context, size: 24).copyWith(
                          color: switch (kpi.valueStatus) {
                            null => color,
                            // Neutraler Wert (z. B. noch nichts trainiert): normale Textfarbe statt Ampel.
                            KpiStatus.unknown => theme.colorScheme.onSurface,
                            final status => kpiColor(status),
                          },
                        ),
                      ),
                    ),
                  ),
                ),
                Text(
                  kpi.caption,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
