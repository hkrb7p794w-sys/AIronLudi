part of 'workout_parts.dart';

/// Großer Ziffernblock mit Schnelltasten statt vieler Stepper-Tipps (60 → 80 kg: 3 Tipps statt 8).
class SetValuePad extends ConsumerStatefulWidget {
  const SetValuePad({super.key, required this.gym, required this.exerciseID, required this.set, required this.field});

  final GymController gym;
  final String exerciseID;
  final int set;
  final SetField field;

  @override
  ConsumerState<SetValuePad> createState() => _SetValuePadState();
}

class _SetValuePadState extends ConsumerState<SetValuePad> {
  late SetField _field = widget.field;
  String _weight = '';
  String _reps = '';

  /// Die erste Taste ersetzt den alten Wert (statt anzuhängen) – kein versehentliches „808“ aus 80 und einer 8.
  bool _replacesWeight = true;
  bool _replacesReps = true;

  /// Unterstützung statt Zusatzgewicht (negatives Gewicht), nur bei Körpergewichtsübungen.
  bool _assisted = false;

  LoggedExercise? get _exercise =>
      widget.gym.active?.exercises.where((exercise) => exercise.id == widget.exerciseID).firstOrNull;

  LoggedSet? get _setValue {
    final exercise = _exercise;
    return exercise != null && widget.set < exercise.sets.length ? exercise.sets[widget.set] : null;
  }

  @override
  void initState() {
    super.initState();
    if (_setValue case final set?) {
      _assisted = set.weightKg < 0;
      _weight = NumberPad.text(set.weightKg.abs());
      _reps = set.reps > 0 ? '${set.reps}' : '';
    }
  }

  String get _current => _field == SetField.weight ? _weight : _reps;

  void _setCurrent(String text) => setState(() {
    if (_field == SetField.weight) {
      _weight = text;
      _replacesWeight = false;
    } else {
      _reps = text;
      _replacesReps = false;
    }
  });

  /// Unplausible Werte (625 statt 62,5 kg) erst nach Rückfrage übernehmen.
  Future<void> _save() async {
    final exercise = _exercise;
    if (exercise == null) return Navigator.of(context).pop();
    final gymSettings = ref.read(coachSettingsProvider).gym;
    final isTime = gymSettings.exercise(exercise.exerciseID)?.tracking == ExerciseTracking.time;
    final history = widget.gym.history(exercise.exerciseID);
    final best = history.isEmpty ? null : history.map((point) => point.topWeightKg).reduce((a, b) => a > b ? a : b);
    final weight = NumberPad.value(_weight) ?? 0;
    final reps = (NumberPad.value(_reps) ?? 0).toInt();
    final warning =
        SetCheck.warning(weightKg: _assisted ? 0 : weight, reps: 0, isTime: isTime, previousBestKg: best) ??
        SetCheck.warning(weightKg: 0, reps: reps, isTime: isTime, previousBestKg: null);
    if (warning != null) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialog) => AlertDialog(
          title: const Text('Wirklich?'),
          content: Text(warning),
          actions: [
            TextButton(onPressed: () => Navigator.of(dialog).pop(false), child: const Text('Korrigieren')),
            TextButton(onPressed: () => Navigator.of(dialog).pop(true), child: const Text('Übernehmen')),
          ],
        ),
      );
      if (confirmed != true) return;
    }
    _apply();
  }

  /// Übernimmt nur Werte, die sich geändert haben – ein unberührtes Feld bleibt, wie es war.
  void _apply() {
    final set = _setValue;
    if (set == null) return Navigator.of(context).pop();
    final weight = (NumberPad.value(_weight) ?? 0) * (_assisted ? -1 : 1);
    final reps = (NumberPad.value(_reps) ?? 0).toInt();
    final weightChanged = (weight - set.weightKg).abs() >= 0.001;
    final repsChanged = reps != set.reps;
    final done = set.done;
    if (weightChanged) widget.gym.setWeight(weight, set: widget.set, of: widget.exerciseID);
    if (repsChanged) widget.gym.setReps(reps, set: widget.set, of: widget.exerciseID);
    // Einstellung „Satz nach Eingabe abhaken“: abhaken und Pause starten, als hätte man „Satz erledigt“ getippt.
    final completeOnEdit = ref.read(coachSettingsProvider).gym.completeOnEdit;
    if (completeOnEdit.completes(afterEditingReps: repsChanged || widget.field == SetField.reps) && !done) {
      widget.gym.complete(set: widget.set, of: widget.exerciseID);
    }
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final exercise = _exercise;
    final gymSettings = ref.watch(coachSettingsProvider).gym;
    final info = exercise == null ? null : gymSettings.exercise(exercise.exerciseID);
    final isTime = info?.tracking == ExerciseTracking.time;
    final isWeight = _field == SetField.weight;
    final step = exercise == null
        ? 2.5
        : ExerciseLibrary.rule(exercise.exerciseID, name: exercise.name, custom: gymSettings.customExercises).step;
    final deltas = isWeight ? [-step, step, 5.0, 10.0] : (isTime ? [-5.0, 5.0, 15.0] : [-1.0, 1.0, 2.0]);
    final previous = widget.set > 0 && exercise != null && widget.set - 1 < exercise.sets.length
        ? (isWeight
              ? NumberPad.text(exercise.sets[widget.set - 1].weightKg.abs())
              : '${exercise.sets[widget.set - 1].reps}')
        : null;
    final theme = Theme.of(context);

    Widget valueBox(SetField box, String text, String unit, String label, bool replacing) {
      final selected = _field == box;
      return Expanded(
        child: Semantics(
          label: '$label: ${text.isEmpty ? '0' : text} $unit',
          selected: selected,
          button: true,
          excludeSemantics: true,
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () => setState(() => _field = box),
            child: Container(
              constraints: const BoxConstraints(minHeight: 84),
              decoration: BoxDecoration(
                color: selected
                    ? theme.colorScheme.primary.withValues(alpha: 0.18)
                    : theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: selected ? theme.colorScheme.primary : Colors.transparent, width: 2),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(label, style: AppText.caption(context).copyWith(color: theme.colorScheme.onSurfaceVariant)),
                  FittedBox(
                    child: Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: text.isEmpty ? '0' : text,
                            style: TextStyle(
                              fontSize: 40,
                              fontWeight: FontWeight.bold,
                              fontFeatures: const [FontFeature.tabularFigures()],
                              // Wird beim ersten Tippen ersetzt: leicht markiert wie ausgewählter Text.
                              color: text.isEmpty || (selected && replacing)
                                  ? theme.colorScheme.onSurfaceVariant
                                  : null,
                            ),
                          ),
                          TextSpan(
                            text: ' $unit',
                            style: AppText.body(context).copyWith(color: theme.colorScheme.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    Widget key(String title, NumberPadKey key, {String? semantics}) => Expanded(
      child: Padding(
        padding: const EdgeInsets.all(5),
        child: Semantics(
          label: semantics,
          button: true,
          excludeSemantics: semantics != null,
          child: Material(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(14),
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () {
                HapticFeedback.selectionClick();
                final replacing = isWeight ? _replacesWeight : _replacesReps;
                // Erste Ziffer ersetzt den alten Wert; Löschen nimmt beim ersten Mal den ganzen Wert weg.
                _setCurrent(NumberPad.apply(key, replacing ? '' : _current, allowsDecimals: isWeight));
              },
              child: SizedBox(
                height: 56,
                child: Center(
                  child: Text(title, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          spacing: 12,
          children: [
            Text(
              'Satz ${widget.set + 1}${exercise == null ? '' : ' · ${exercise.name}'}',
              style: theme.textTheme.titleMedium,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            Row(
              spacing: 10,
              children: [
                valueBox(SetField.weight, _weight, _assisted ? 'kg Hilfe' : 'kg', 'Gewicht', _replacesWeight),
                valueBox(
                  SetField.reps,
                  _reps,
                  isTime ? 's' : 'Wdh.',
                  isTime ? 'Dauer' : 'Wiederholungen',
                  _replacesReps,
                ),
              ],
            ),
            if (isWeight && ExerciseUnits.allowsAssistance(info))
              SegmentedButton<bool>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: false, label: Text('Zusatzgewicht')),
                  ButtonSegment(value: true, label: Text('Unterstützung')),
                ],
                selected: {_assisted},
                onSelectionChanged: (value) => setState(() => _assisted = value.first),
              ),
            Row(
              spacing: 6,
              children: [
                for (final delta in deltas)
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(0, 44)),
                      onPressed: () {
                        final value = (NumberPad.value(_current) ?? 0) + delta;
                        final clamped = value < 0 ? 0.0 : value;
                        _setCurrent(isWeight ? NumberPad.text(clamped) : (clamped > 0 ? '${clamped.toInt()}' : ''));
                      },
                      child: Text('${delta > 0 ? '+' : '−'}${GermanFormat.number(delta.abs())}'),
                    ),
                  ),
                if (previous != null)
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(0, 44)),
                      onPressed: () => _setCurrent(previous),
                      child: FittedBox(child: Text('wie Satz ${widget.set}')),
                    ),
                  ),
              ],
            ),
            Column(
              children: [
                for (final row in const [
                  [1, 2, 3],
                  [4, 5, 6],
                  [7, 8, 9],
                ])
                  Row(children: [for (final digit in row) key('$digit', NumberPadDigit(digit))]),
                Row(
                  children: [
                    if (isWeight) key(',', const NumberPadComma()) else const Expanded(child: SizedBox(height: 66)),
                    key('0', const NumberPadDigit(0)),
                    key('⌫', const NumberPadDelete(), semantics: 'Löschen'),
                  ],
                ),
              ],
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(56),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
              onPressed: _save,
              child: const Text('Übernehmen', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }
}
