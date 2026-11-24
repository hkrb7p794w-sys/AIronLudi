import 'package:coach_core/coach_core.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import 'tokens.dart';

// Gemeinsame Achsen für alle fl_chart-Diagramme (Roast B-30): deutsches Zahlenformat, keine krummen Randwerte
// („467“ über „400“), kein Umbruch in der reservierten Breite und Schrift, die mit der Systemgröße wächst, ohne
// überzulaufen.

/// Wertachse (meist links). [format] überschreibt die Zahl (z. B. Uhrzeit, Tempo); sonst ganze Zahlen bzw. eine
/// Nachkommastelle mit Komma, je nach Rasterweite.
AxisTitles valueAxis({double reservedSize = 40, double? interval, String Function(double value)? format}) => AxisTitles(
  sideTitles: SideTitles(
    showTitles: true,
    reservedSize: reservedSize,
    interval: interval,
    getTitlesWidget: (value, meta) {
      if (isOffGridEdge(value, min: meta.min, max: meta.max, interval: meta.appliedInterval)) {
        return const SizedBox.shrink();
      }
      return SideTitleWidget(
        meta: meta,
        child: AxisLabel(format?.call(value) ?? axisNumber(value, interval: meta.appliedInterval)),
      );
    },
  ),
);

/// Randwert, der nicht auf dem Raster liegt (fl_chart beschriftet Minimum und Maximum immer) – weglassen.
bool isOffGridEdge(double value, {required double min, required double max, required double interval}) {
  if (value != min && value != max) return false;
  if (interval <= 0) return false;
  final steps = value / interval;
  return (steps - steps.roundToDouble()).abs() > 1e-6;
}

/// Zahl für eine Achse: ganze Zahl ab Rasterweite 1, sonst mit Komma.
String axisNumber(double value, {required double interval}) =>
    interval >= 1 ? GermanFormat.decimal(value.roundToDouble()) : GermanFormat.number(value);

/// Beschriftung einer Achse: Rolle `caption`, eine Zeile, bei großer Schrift verkleinert statt umbrochen.
class AxisLabel extends StatelessWidget {
  const AxisLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => FittedBox(
    fit: BoxFit.scaleDown,
    child: Text(
      text,
      maxLines: 1,
      softWrap: false,
      style: AppText.caption(context).copyWith(color: AppColors.muted(context)),
    ),
  );
}
