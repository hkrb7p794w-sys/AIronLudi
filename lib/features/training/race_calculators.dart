import 'package:coach_core/coach_core.dart';
import 'package:flutter/material.dart';

import '../../ui/components.dart';
import '../../ui/liquid.dart';
import '../../ui/tokens.dart';

/// Regler für die Zielzeit 70.3 (Seite „Almere“): Pace bzw. Geschwindigkeit je Disziplin und die Wechselzeit frei
/// verschieben, Abschnitte und Endzeit rechnen sofort mit. Ausgang sind die Werte der Schätzung, „Zurücksetzen“ stellt
/// sie wieder her. Nur zum Durchspielen – gespeichert wird nichts.
class TriathlonCalculatorSection extends StatefulWidget {
  const TriathlonCalculatorSection({super.key, required this.start});

  /// Ausgangswerte (aus den Saisonwerten, wie die Schätzung).
  final TriathlonTimes start;

  @override
  State<TriathlonCalculatorSection> createState() => _TriathlonCalculatorSectionState();
}

class _TriathlonCalculatorSectionState extends State<TriathlonCalculatorSection> {
  late TriathlonTimes _times = widget.start;

  @override
  void didUpdateWidget(TriathlonCalculatorSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Saisonwerte geändert (z. B. neuer Test): vom neuen Stand aus weiterrechnen.
    if (oldWidget.start != widget.start) _times = widget.start;
  }

  void _set(TriathlonTimes times) => setState(() => _times = times);

  @override
  Widget build(BuildContext context) {
    final start = widget.start;
    final times = _times;
    String clock(double minutes) => '${RaceEstimate.hoursMinutes(minutes)} h';
    return FormSection(
      header: 'Was bringt eine Verbesserung?',
      footer:
          'Regler nach rechts = schneller. Nur zum Durchrechnen, gespeichert wird nichts. Wechselzeiten sind Annahmen. '
          'Beim 70.3 ist das Rad der größte Hebel; mehr Zeit braucht es dafür nicht, nur Umschichten.',
      children: [
        CalculatorTotal(
          value: clock(times.totalMinutes),
          lines: [
            _difference((times.totalMinutes - start.totalMinutes).round(), same: 'die Schätzung', to: 'der Schätzung'),
            RaceEstimate.corridor(times.totalMinutes),
          ],
          onReset: times == start ? null : () => _set(start),
        ),
        CalculatorSlider(
          label: 'Schwimmen 1,9 km',
          result: clock(times.swimMinutes),
          value: '${PlanTokens.mmss(times.swimSecondsPer100m)} /100 m',
          position: times.swimSecondsPer100m.toDouble(),
          min: TriathlonTimes.swimMin.toDouble(),
          max: TriathlonTimes.swimMax.toDouble(),
          divisions: TriathlonTimes.swimMax - TriathlonTimes.swimMin,
          reversed: true,
          onChanged: (value) => _set(times.copyWith(swimSecondsPer100m: value.round())),
        ),
        CalculatorSlider(
          label: 'Rad 94 km',
          result: clock(times.bikeMinutes),
          value: '${GermanFormat.decimal(times.bikeKmh)} km/h',
          position: times.bikeKmh,
          min: TriathlonTimes.bikeMin,
          max: TriathlonTimes.bikeMax,
          divisions: ((TriathlonTimes.bikeMax - TriathlonTimes.bikeMin) / TriathlonTimes.bikeStep).round(),
          onChanged: (value) => _set(times.copyWith(bikeKmh: _snap(value, TriathlonTimes.bikeStep))),
        ),
        CalculatorSlider(
          label: 'Lauf 21,1 km',
          result: clock(times.runMinutes),
          value: '${PlanTokens.mmss(times.runSecondsPerKm)} /km',
          position: times.runSecondsPerKm.toDouble(),
          min: TriathlonTimes.runMin.toDouble(),
          max: TriathlonTimes.runMax.toDouble(),
          divisions: TriathlonTimes.runMax - TriathlonTimes.runMin,
          reversed: true,
          onChanged: (value) => _set(times.copyWith(runSecondsPerKm: value.round())),
        ),
        CalculatorSlider(
          label: 'Wechsel 1 und 2',
          value: '${GermanFormat.decimal(times.transitionMinutes)} min',
          position: times.transitionMinutes,
          min: TriathlonTimes.transitionMin,
          max: TriathlonTimes.transitionMax,
          divisions: ((TriathlonTimes.transitionMax - TriathlonTimes.transitionMin) / TriathlonTimes.transitionStep)
              .round(),
          reversed: true,
          onChanged: (value) => _set(times.copyWith(transitionMinutes: _snap(value, TriathlonTimes.transitionStep))),
        ),
      ],
    );
  }
}

/// Regler für den Marathon: Pace frei verschieben (Endzeit und Zwischenzeiten rechnen mit) und aus einer
/// Halbmarathonzeit die realistische Spanne ablesen. Nur zum Durchspielen – gespeichert wird nichts.
class MarathonCalculatorSection extends StatefulWidget {
  const MarathonCalculatorSection({super.key, required this.pace, required this.half});

  /// Zielpace in Sekunden je km (Ausgang und Vergleich).
  final int pace;

  /// Halbmarathonzeit in Sekunden (Test oder aus der Zielpace geschätzt).
  final int half;

  @override
  State<MarathonCalculatorSection> createState() => _MarathonCalculatorSectionState();
}

class _MarathonCalculatorSectionState extends State<MarathonCalculatorSection> {
  late int _pace = MarathonTimes.clampPace(widget.pace);
  late int _half = MarathonTimes.clampHalf(widget.half);

  @override
  void didUpdateWidget(MarathonCalculatorSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.pace != widget.pace) _pace = MarathonTimes.clampPace(widget.pace);
    if (oldWidget.half != widget.half) _half = MarathonTimes.clampHalf(widget.half);
  }

  @override
  Widget build(BuildContext context) {
    final startPace = MarathonTimes.clampPace(widget.pace);
    final startHalf = MarathonTimes.clampHalf(widget.half);
    final finish = MarathonTimes.seconds(_pace);
    final range = MarathonTimes.fromHalf(_half);
    String hm(int seconds) => MarathonOutlook.hoursMinutesFromSeconds(seconds);
    String pace(int seconds) => MarathonOutlook.pace(seconds / MarathonOutlook.marathonKilometers);
    return Column(
      children: [
        FormSection(
          header: 'Zeiten durchspielen',
          footer: 'Regler nach rechts = schneller. Gleichmäßige Pace gerechnet; gespeichert wird nichts.',
          children: [
            CalculatorTotal(
              value: '${TimeText.hms(finish)} h',
              lines: [
                _difference(
                  ((finish - MarathonTimes.seconds(startPace)) / 60).round(),
                  same: 'geplant',
                  to: 'der Zielpace',
                ),
              ],
              onReset: _pace == startPace ? null : () => setState(() => _pace = startPace),
            ),
            CalculatorSlider(
              label: 'Pace',
              value: '${PlanTokens.mmss(_pace)} /km',
              position: _pace.toDouble(),
              min: MarathonTimes.paceMin.toDouble(),
              max: MarathonTimes.paceMax.toDouble(),
              divisions: MarathonTimes.paceMax - MarathonTimes.paceMin,
              reversed: true,
              onChanged: (value) => setState(() => _pace = value.round()),
            ),
            for (final kilometers in MarathonTimes.splits)
              LabeledRow(
                label: kilometers == 21.0975 ? 'Halbmarathon' : '${GermanFormat.decimal(kilometers)} km',
                value: TimeText.hms(MarathonTimes.seconds(_pace, kilometers: kilometers)),
              ),
          ],
        ),
        FormSection(
          header: 'Aus dem Halbmarathon',
          footer: 'Praxiswert: Marathon ≈ Halbmarathon × 2,15–2,2.',
          children: [
            CalculatorSlider(
              label: 'Halbmarathon',
              value: TimeText.hms(_half),
              position: _half.toDouble(),
              min: MarathonTimes.halfMin.toDouble(),
              max: MarathonTimes.halfMax.toDouble(),
              divisions: (MarathonTimes.halfMax - MarathonTimes.halfMin) ~/ MarathonTimes.halfStep,
              reversed: true,
              onChanged: (value) => setState(() => _half = _snap(value, MarathonTimes.halfStep.toDouble()).round()),
            ),
            LabeledRow(
              label: 'Marathon realistisch',
              value: '${hm(range.low)}–${hm(range.high)} h (${pace(range.low)}–${pace(range.high)} /km)',
            ),
            if (_half != startHalf)
              ListTile(
                title: Text('Zurücksetzen', style: TextStyle(color: Theme.of(context).colorScheme.primary)),
                onTap: () => setState(() => _half = startHalf),
              ),
          ],
        ),
      ],
    );
  }
}

/// Unterschied in Minuten als Text („−4 min gegenüber der Schätzung“, ohne Unterschied „wie die Schätzung“).
String _difference(int minutes, {required String same, required String to}) => switch (minutes) {
  0 => 'wie $same',
  < 0 => '−${-minutes} min gegenüber $to',
  _ => '+$minutes min gegenüber $to',
};

/// Auf die Schrittweite des Reglers runden.
double _snap(double value, double step) => (value / step).round() * step;

/// Endzeit groß, darunter Vergleich und Einordnung; „Zurücksetzen“, sobald ein Regler bewegt wurde.
class CalculatorTotal extends StatelessWidget {
  const CalculatorTotal({super.key, required this.value, this.lines = const [], this.onReset});

  final String value;
  final List<String> lines;
  final VoidCallback? onReset;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 14, 8, 12),
    child: Row(
      spacing: 8,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 2,
            children: [
              Text(value, style: LiquidText.kpi(context, size: 28)),
              for (final line in lines)
                Text(line, style: AppText.footnote(context).copyWith(color: AppColors.muted(context))),
            ],
          ),
        ),
        if (onReset case final reset?) TextButton(onPressed: reset, child: const Text('Zurücksetzen')),
      ],
    ),
  );
}

/// Regler mit Beschriftung: links Disziplin und Ergebnis, rechts der eingestellte Wert. [reversed]: größere Werte
/// links (Pace und Zeiten), damit „nach rechts“ immer „schneller“ heißt.
class CalculatorSlider extends StatelessWidget {
  const CalculatorSlider({
    super.key,
    required this.label,
    required this.value,
    required this.position,
    required this.min,
    required this.max,
    required this.divisions,
    required this.onChanged,
    this.result,
    this.reversed = false,
  });

  final String label;

  /// Eingestellter Wert als Text (z. B. „2:05 /100 m“).
  final String value;

  /// Ergebnis für diesen Abschnitt (z. B. „0:40 h“).
  final String? result;
  final double position;
  final double min;
  final double max;
  final int divisions;
  final bool reversed;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final shown = (reversed ? max + min - position : position).clamp(min, max);
    return MergeSemantics(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              spacing: 8,
              children: [
                Expanded(flex: 3, child: Text(result == null ? label : '$label · $result')),
                Flexible(
                  flex: 2,
                  child: Text(
                    value,
                    textAlign: TextAlign.end,
                    style: TextStyle(fontWeight: FontWeight.w600, color: theme.colorScheme.primary),
                  ),
                ),
              ],
            ),
            Slider(
              value: shown,
              min: min,
              max: max,
              divisions: divisions,
              label: value,
              semanticFormatterCallback: (_) => value,
              onChanged: (raw) => onChanged(reversed ? max + min - raw : raw),
            ),
          ],
        ),
      ),
    );
  }
}
