import 'package:coach_core/coach_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../ui/components.dart';

/// Eigene Makroziele: automatisch, in Gramm oder in Prozent der Energie; auf Wunsch eigene Werte für Ruhetage.
class MacroGoalsSection extends StatelessWidget {
  const MacroGoalsSection({super.key, required this.nutrition, required this.weightKilograms, required this.change});

  final NutritionSettings nutrition;

  /// Körpergewicht für die Startwerte in Gramm.
  final double weightKilograms;
  final void Function(void Function(NutritionSettings value) update) change;

  MacroGoal _defaults(MacroMode mode) => mode == MacroMode.percent
      ? MacroGoal.percentDefault
      : MacroGoal(
          protein: (1.8 * weightKilograms).roundToDouble(),
          carbs: (4 * weightKilograms).roundToDouble(),
          fat: (1 * weightKilograms).roundToDouble(),
        );

  @override
  Widget build(BuildContext context) {
    final mode = nutrition.macroMode;
    final macros = nutrition.macros ?? _defaults(mode);
    final rest = nutrition.restDayMacros;
    return FormSection(
      header: 'Eigene Makroziele',
      footer: switch (mode) {
        MacroMode.auto =>
          'Automatisch: Die App rechnet Kalorien, Protein, Kohlenhydrate und Fett aus Ziel, Körperwerten und Training.',
        _ =>
          'Die Schutzgrenzen bleiben: nicht weniger Energie als das größte erlaubte Defizit und mindestens 20 % Fett. '
              'Die App passt dann an und sagt es im Reiter Ernährung. Ohne Gewichtsziele (Schutzeinstellung) gilt '
              'weiter die automatische Rechnung.',
      },
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
          child: SizedBox(
            width: double.infinity,
            child: SegmentedButton<MacroMode>(
              segments: [for (final value in MacroMode.values) ButtonSegment(value: value, label: Text(value.label))],
              selected: {mode},
              showSelectedIcon: false,
              onSelectionChanged: (selection) => change((value) {
                final next = selection.first;
                value.macroMode = next;
                // Gramm und Prozent passen nicht zueinander: beim Wechsel mit Startwerten beginnen.
                if (next != MacroMode.auto && next != mode) {
                  value
                    ..macros = _defaults(next)
                    ..restDayMacros = value.restDayMacros == null ? null : _defaults(next);
                }
              }),
            ),
          ),
        ),
        if (mode != MacroMode.auto) ...[
          _MacroGoalEditor(
            key: ValueKey('alle-${mode.rawValue}'),
            title: rest == null ? 'Alle Tage' : 'Trainingstage',
            mode: mode,
            goal: macros,
            onChanged: (goal) => change((value) => value.macros = goal),
          ),
          SwitchListTile.adaptive(
            title: const Text('Ruhetage mit eigenen Werten'),
            subtitle: const Text('Zum Beispiel weniger Kohlenhydrate an Tagen ohne Training.'),
            value: rest != null,
            onChanged: (on) => change((value) {
              value
                ..macros ??= macros
                ..restDayMacros = on ? macros : null;
            }),
          ),
          if (rest != null)
            _MacroGoalEditor(
              key: ValueKey('ruhe-${mode.rawValue}'),
              title: 'Ruhetage',
              mode: mode,
              goal: rest,
              onChanged: (goal) => change((value) => value.restDayMacros = goal),
            ),
        ],
      ],
    );
  }
}

/// Drei Felder (Protein, Kohlenhydrate, Fett), bei Prozent dazu die Energie; darunter Summe bzw. kcal.
class _MacroGoalEditor extends StatefulWidget {
  const _MacroGoalEditor({
    super.key,
    required this.title,
    required this.mode,
    required this.goal,
    required this.onChanged,
  });

  final String title;
  final MacroMode mode;
  final MacroGoal goal;
  final ValueChanged<MacroGoal> onChanged;

  @override
  State<_MacroGoalEditor> createState() => _MacroGoalEditorState();
}

class _MacroGoalEditorState extends State<_MacroGoalEditor> {
  late final _protein = TextEditingController(text: _text(widget.goal.protein));
  late final _carbs = TextEditingController(text: _text(widget.goal.carbs));
  late final _fat = TextEditingController(text: _text(widget.goal.fat));
  late final _kcal = TextEditingController(
    text: widget.goal.kilocalories == null ? '' : _text(widget.goal.kilocalories!),
  );

  static String _text(double value) => GermanFormat.number(value);

  static double? _parse(String text) => double.tryParse(text.trim().replaceAll(',', '.'));

  @override
  void dispose() {
    _protein.dispose();
    _carbs.dispose();
    _fat.dispose();
    _kcal.dispose();
    super.dispose();
  }

  void _changed() {
    final protein = _parse(_protein.text);
    final carbs = _parse(_carbs.text);
    final fat = _parse(_fat.text);
    if (protein == null || carbs == null || fat == null || protein < 0 || carbs < 0 || fat < 0) return;
    final kcal = _parse(_kcal.text);
    widget.onChanged(
      MacroGoal(
        protein: protein,
        carbs: carbs,
        fat: fat,
        kilocalories: widget.mode == MacroMode.percent && kcal != null && kcal >= 800 ? kcal : null,
      ),
    );
  }

  Widget _field(String label, TextEditingController controller, String unit) => Expanded(
    child: TextField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9,.]'))],
      decoration: InputDecoration(labelText: label, suffixText: unit, isDense: true),
      onChanged: (_) => _changed(),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final percent = widget.mode == MacroMode.percent;
    final unit = percent ? '%' : 'g';
    final goal = widget.goal;
    final sum = goal.protein + goal.carbs + goal.fat;
    final secondary = TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 8,
        children: [
          Text(widget.title, style: const TextStyle(fontWeight: FontWeight.w600)),
          Row(
            spacing: 10,
            children: [
              _field('Protein', _protein, unit),
              _field('Kohlenhydrate', _carbs, unit),
              _field('Fett', _fat, unit),
            ],
          ),
          if (percent) ...[
            Row(children: [_field('Energie (leer = automatisch)', _kcal, 'kcal')]),
            Text(
              (sum - 100).abs() < 0.5
                  ? 'Zusammen 100 %.'
                  : 'Zusammen ${GermanFormat.number(sum)} % – die App rechnet die Anteile auf 100 % um.',
              style: (sum - 100).abs() < 0.5 ? secondary : secondary.copyWith(color: Colors.orange),
            ),
          ] else
            Text(
              'Ergibt ${GermanFormat.number(4 * goal.protein + 4 * goal.carbs + 9 * goal.fat)} kcal.',
              style: secondary,
            ),
        ],
      ),
    );
  }
}
