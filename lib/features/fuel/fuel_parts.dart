import 'dart:math' as math;

import 'package:coach_core/coach_core.dart';
import 'package:flutter/material.dart';

import '../../ui/kpi_ring.dart';
import '../../ui/liquid.dart';
import '../../ui/tokens.dart';

/// Farbe je Sportart (wie in Plan und Training).
extension FuelSportStyle on FuelSport {
  Color get color => switch (this) {
    FuelSport.run => AppPalette.green,
    FuelSport.bike => AppPalette.orange,
    FuelSport.swim => AppPalette.blue,
    FuelSport.triathlon => AppPalette.teal,
    FuelSport.strength => AppPalette.purple,
    FuelSport.hybrid => AppPalette.pink,
  };
}

/// Kategorische Farben der Kreisdiagramme (geprüft auf Farbsehschwäche, hell und dunkel). Werte stehen immer als
/// Text daneben – Farbe allein trägt nie die Bedeutung.
abstract final class FuelChartColors {
  static Color first(BuildContext context) => _dark(context) ? AppPalette.seriesBlueDark : AppPalette.seriesBlueLight;
  static Color second(BuildContext context) =>
      _dark(context) ? AppPalette.seriesOrangeDark : AppPalette.seriesOrangeLight;
  static Color third(BuildContext context) => _dark(context) ? AppPalette.seriesGreenDark : AppPalette.seriesGreenLight;

  static bool _dark(BuildContext context) => Theme.of(context).brightness == Brightness.dark;
}

/// Ampel einer Deckung: 85–115 % grün, 60–130 % orange, sonst rot; ohne Soll grau. [generousAbove]: mehr ist bis
/// 150 % unbedenklich (Natrium), darüber orange.
KpiStatus fuelCoverageStatus(double? coverage, {bool generousAbove = false}) => switch (coverage) {
  null => KpiStatus.unknown,
  >= 0.85 && <= 1.15 => KpiStatus.good,
  final value when generousAbove && value > 1.15 => value <= 1.5 ? KpiStatus.good : KpiStatus.moderate,
  >= 0.6 && <= 1.3 => KpiStatus.moderate,
  _ => KpiStatus.critical,
};

/// Ring „Soll je Stunde“ mit Deckung durch die gewählten Produkte.
class FuelTargetRing extends StatelessWidget {
  const FuelTargetRing({
    super.key,
    required this.value,
    required this.unit,
    required this.label,
    required this.coverage,
    this.generousAbove = false,
  });

  final String value;
  final String unit;
  final String label;
  final double? coverage;

  /// Mehr ist unbedenklich (Natrium bis 150 %).
  final bool generousAbove;

  @override
  Widget build(BuildContext context) {
    final status = fuelCoverageStatus(coverage, generousAbove: generousAbove);
    final percent = coverage == null ? '–' : '${(coverage! * 100).round()} %';
    return Semantics(
      label: '$label: $value $unit, gedeckt $percent',
      child: ExcludeSemantics(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          spacing: 6,
          children: [
            ProgressRing(
              fraction: coverage ?? 0,
              color: kpiColor(status),
              size: 78,
              stroke: 8,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(value, style: LiquidText.kpi(context, size: 20)),
                  Text(unit, style: AppText.caption(context).copyWith(color: AppColors.muted(context))),
                ],
              ),
            ),
            Text(label, style: LiquidText.label(context), textAlign: TextAlign.center),
            Text(
              coverage == null ? 'kein Soll' : 'gedeckt $percent',
              style: AppText.caption(context).copyWith(color: AppColors.muted(context)),
            ),
          ],
        ),
      ),
    );
  }
}

/// Ein Abschnitt eines Kreisdiagramms.
final class FuelSlice {
  const FuelSlice(this.label, this.value, this.color, {this.valueText});

  final String label;
  final double value;
  final Color color;
  final String? valueText;
}

/// Ring-Kreisdiagramm mit 2 px Lücke zwischen den Abschnitten und Legende samt Werten daneben.
class FuelDonut extends StatelessWidget {
  const FuelDonut({super.key, required this.title, required this.slices, this.caption, this.center});

  final String title;
  final List<FuelSlice> slices;
  final String? caption;
  final String? center;

  @override
  Widget build(BuildContext context) {
    final total = slices.fold(0.0, (sum, slice) => sum + slice.value);
    final track = LiquidTheme.of(context).track;
    return Semantics(
      label:
          '$title: ${[for (final slice in slices) '${slice.label} ${slice.valueText ?? _percent(slice.value, total)}'].join(', ')}',
      child: ExcludeSemantics(
        child: Row(
          spacing: 14,
          children: [
            SizedBox.square(
              dimension: 76,
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: 1),
                duration: LiquidMotion.of(context, LiquidMotion.slow),
                curve: LiquidMotion.settle,
                builder: (context, t, child) => CustomPaint(
                  painter: _DonutPainter(slices: slices, total: total, progress: t, track: track),
                  child: child,
                ),
                child: center == null ? null : Center(child: Text(center!, style: LiquidText.kpi(context, size: 15))),
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 4,
                children: [
                  Text(title, style: Theme.of(context).textTheme.titleSmall),
                  for (final slice in slices)
                    Row(
                      spacing: 6,
                      children: [
                        Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(color: slice.color, borderRadius: BorderRadius.circular(3)),
                        ),
                        Expanded(child: Text(slice.label, style: LiquidText.label(context))),
                        Text(
                          slice.valueText ?? _percent(slice.value, total),
                          style: LiquidText.label(context).copyWith(
                            color: Theme.of(context).colorScheme.onSurface,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ],
                    ),
                  if (caption case final caption?) Text(caption, style: LiquidText.label(context)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _percent(double value, double total) => total <= 0 ? '–' : '${(value / total * 100).round()} %';
}

class _DonutPainter extends CustomPainter {
  _DonutPainter({required this.slices, required this.total, required this.progress, required this.track});

  final List<FuelSlice> slices;
  final double total;
  final double progress;
  final Color track;

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 12.0;
    final rect = (Offset.zero & size).deflate(stroke / 2);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.butt;
    canvas.drawArc(rect, 0, 2 * math.pi, false, paint..color = track);
    if (total <= 0) return;
    final radius = rect.width / 2;
    // 2 px Lücke als Winkel auf dem Ring.
    final gap = slices.where((slice) => slice.value > 0).length > 1 ? 2 / radius : 0.0;
    var start = -math.pi / 2;
    for (final slice in slices) {
      if (slice.value <= 0) continue;
      final sweep = slice.value / total * 2 * math.pi * progress;
      final visible = math.max(0.0, sweep - gap);
      if (visible > 0) canvas.drawArc(rect, start + gap / 2, visible, false, paint..color = slice.color);
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(_DonutPainter old) => old.progress != progress || old.total != total || old.slices != slices;
}

/// Eine Zeile im Zeitstrahl: Zeitpunkt als Pille, Punkt auf der Linie, Inhalt.
class FuelTimelineRow extends StatelessWidget {
  const FuelTimelineRow({super.key, required this.step, required this.isLast, this.clock});

  final FuelStep step;
  final bool isLast;

  /// Uhrzeit (wenn der Start bekannt ist).
  final String? clock;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final amounts = step.amounts;
    final values = [
      if (amounts.carbs > 0) '${amounts.carbs.round()} g KH',
      if (amounts.protein > 0) '${amounts.protein.round()} g Protein',
      if (amounts.fluid > 0) '${amounts.fluid.round()} ml',
      if (amounts.sodium > 0) '${amounts.sodium.round()} mg Na',
      if (amounts.caffeine > 0) '${amounts.caffeine.round()} mg Koffein',
    ];
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 92,
            child: Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    step.timeLabel,
                    textAlign: TextAlign.right,
                    style: AppText.footnote(context).copyWith(fontWeight: FontWeight.w600),
                  ),
                  if (step.segment case final segment?)
                    Text(segment.label, style: AppText.caption(context).copyWith(color: segment.color)),
                  if (clock case final clock?)
                    Text(clock, style: AppText.caption(context).copyWith(color: AppColors.muted(context))),
                ],
              ),
            ),
          ),
          SizedBox(
            width: 28,
            child: Column(
              children: [
                const SizedBox(height: 5),
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(color: scheme.primary, shape: BoxShape.circle),
                ),
                if (!isLast) Expanded(child: Container(width: 2, color: scheme.primary.withValues(alpha: 0.25))),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 2,
                children: [
                  Text(step.content, style: AppText.callout(context).copyWith(fontWeight: FontWeight.w500)),
                  if (values.isNotEmpty) Text(values.join(' · '), style: LiquidText.label(context)),
                  if (step.detail.isNotEmpty) Text(step.detail, style: LiquidText.label(context)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Kurztext eines Produkts: „25 g KH · 50 mg Na · je Gel“.
String fuelProductSummary(FuelProduct product) {
  final values = [
    '${GermanFormat.decimal(product.carbs)} g KH',
    if (product.fructoseShare case final share?) '${(share * 100).round()} % Fruktose',
    if (product.sodium > 0) '${product.sodium.round()} mg Na',
    if (product.caffeine > 0) '${product.caffeine.round()} mg Koffein',
  ];
  final serving = product.isDrink ? '${product.volumeMilliliters.round()} ml' : product.serving;
  return '${values.join(' · ')} je $serving';
}

/// „8:30“ aus Minuten nach Mitternacht (über den Tag hinaus modulo 24 h).
String fuelClock(int minuteOfDay) {
  final minutes = ((minuteOfDay % 1440) + 1440) % 1440;
  return '${minutes ~/ 60}:${(minutes % 60).toString().padLeft(2, '0')}';
}
