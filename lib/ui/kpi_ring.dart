import 'dart:math' as math;

import 'package:coach_core/coach_core.dart';
import 'package:flutter/material.dart';

/// Ampelfarbe einer Kennzahl: Grün im Zielbereich, Orange für Aufmerksamkeit, Rot kritisch, Grau ohne Daten.
Color kpiColor(KpiStatus status) => switch (status) {
  KpiStatus.good => Colors.green,
  KpiStatus.moderate => Colors.orange,
  KpiStatus.critical => Colors.red,
  KpiStatus.unknown => Colors.grey,
};

/// Ring mit Anteil (voll) und optional zweitem, hellem Abschnitt (z. B. noch geplant).
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
  Widget build(BuildContext context) => SizedBox.square(
    dimension: size,
    child: CustomPaint(
      painter: _RingPainter(
        fraction: fraction.clamp(0, 1),
        secondary: secondary?.clamp(0, 1),
        color: color,
        track: Theme.of(context).colorScheme.surfaceContainerHighest,
        stroke: stroke,
      ),
      child: Center(child: child),
    ),
  );
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
    Paint paint(Color color) => Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(arc, 0, 2 * math.pi, false, paint(track));
    const start = -math.pi / 2;
    if (secondary case final second? when second > fraction) {
      canvas.drawArc(arc, start, 2 * math.pi * second, false, paint(color.withValues(alpha: 0.3)));
    }
    if (fraction > 0) canvas.drawArc(arc, start, 2 * math.pi * math.max(fraction, 0.01), false, paint(color));
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
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            spacing: 6,
            children: [
              Text(kpi.title, style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600)),
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
                      style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700, color: color),
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
    );
  }
}
