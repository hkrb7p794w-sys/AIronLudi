import 'dart:async';

import 'package:coach_core/coach_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../data/settings/coach_settings.dart';
import '../../services/providers.dart';
import 'exercise_picker.dart';
import 'gym_controller.dart';
import 'gym_library.dart';
import 'muscle_views.dart';

/// Welcher Wert gerade über den Ziffernblock eingegeben wird.
enum SetField { weight, reps }

/// „1:05“ bzw. „1:02:05“ seit [start].
String elapsedText(DateTime start, DateTime now) {
  final seconds = now.difference(start).inSeconds.clamp(0, 359999);
  final (hours, minutes, rest) = (seconds ~/ 3600, seconds % 3600 ~/ 60, seconds % 60);
  String two(int value) => value.toString().padLeft(2, '0');
  return hours > 0 ? '$hours:${two(minutes)}:${two(rest)}' : '$minutes:${two(rest)}';
}

/// Gewicht × Wiederholungen eines Satzes, kurz.
String setValues(LoggedSet set) =>
    set.weightKg != 0 ? '${GermanFormat.number(set.weightKg)} kg × ${set.reps}' : '${set.reps} Wdh.';

/// Gym-Einstellungen ändern und speichern.
void changeGym(CoachSettings settings, void Function(GymSettings gym) change) {
  final gym = settings.gym;
  change(gym);
  settings.gym = gym;
}

/// Notiz, letztes Mal, Progression, Aufwärmen und Scheiben – klein unter dem Satz.
class ExerciseNotes extends ConsumerWidget {
  const ExerciseNotes({
    super.key,
    required this.exercise,
    required this.gym,
    this.set,
    this.offersWarmUp = false,
    this.centered = true,
  });

  final LoggedExercise exercise;
  final GymController gym;

  /// Satz der Fokus-Karte (Scheiben für genau dieses Gewicht); `null` = schwerster Satz.
  final int? set;
  final bool offersWarmUp;
  final bool centered;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(coachSettingsProvider);
    final gymSettings = settings.gym;
    final info = gymSettings.exercise(exercise.exerciseID);
    final theme = Theme.of(context);
    final style = TextStyle(fontSize: 13, color: theme.colorScheme.onSurfaceVariant);
    final strong = style.copyWith(color: theme.colorScheme.onSurface);
    final align = centered ? TextAlign.center : TextAlign.start;
    final note = gymSettings.notes[exercise.exerciseID];
    final last = centered ? null : gym.lastTime(exercise.exerciseID);
    final progress = gym.progress.where((item) => item.exerciseID == exercise.exerciseID).firstOrNull;
    final working = exercise.sets
        .where((set) => set.kind != SetKind.warmup)
        .fold<double>(0, (top, set) => set.weightKg > top ? set.weightKg : top);
    final shown = set != null && set! < exercise.sets.length ? exercise.sets[set!].weightKg : working;
    final level = settings.profile.level(TrainingSport.strength);
    final warmUp = info == null ? const <WarmUpStep>[] : gym.warmUpSteps(exercise, level: level);
    final bar = info == null ? PlateCalculator.standardBar : gymSettings.bar(info.id);
    final plates = info != null && info.equipment.firstOrNull == Equipment.barbell
        ? PlateCalculator.plates(shown, bar: bar, available: gymSettings.plates)
        : null;
    return Column(
      crossAxisAlignment: centered ? CrossAxisAlignment.center : CrossAxisAlignment.start,
      spacing: 6,
      children: [
        if (note != null && note.isNotEmpty) _IconText(Icons.sticky_note_2_outlined, note, strong, align),
        if (last != null) Text(last, style: style, textAlign: align),
        // Was die Progression für heute vorschlägt – sichtbar statt nur vorbefüllt.
        if (progress != null)
          Text(
            GymTarget.text(progress, recovered: gym.recovered),
            style: strong.copyWith(fontSize: 14, fontWeight: FontWeight.w500),
            textAlign: align,
          ),
        if (warmUp.isNotEmpty) ...[
          _IconText(Icons.local_fire_department_outlined, WarmUp.text(warmUp), strong, align),
          if (offersWarmUp)
            OutlinedButton.icon(
              onPressed: () => gym.insertWarmUp(exercise.id, level: level),
              icon: const Icon(Icons.add),
              label: const Text('Aufwärmsätze einfügen'),
            ),
        ],
        if (plates != null)
          Text(
            '${GermanFormat.number(shown)} kg · Stange ${GermanFormat.number(bar)} kg · ${PlateCalculator.text(plates)}',
            style: style,
            textAlign: align,
          ),
      ],
    );
  }
}

class _IconText extends StatelessWidget {
  const _IconText(this.icon, this.text, this.style, this.align);

  final IconData icon;
  final String text;
  final TextStyle style;
  final TextAlign align;

  @override
  Widget build(BuildContext context) => Text.rich(
    TextSpan(
      children: [
        WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: Padding(padding: const EdgeInsets.only(right: 4), child: Icon(icon, size: 15)),
        ),
        TextSpan(text: text),
      ],
    ),
    style: style,
    textAlign: align,
  );
}

/// Menü einer Übung: später, überspringen, ersetzen, Reihenfolge, Supersatz, Satz, Pause, Notiz, Stange, entfernen.
class ExerciseMenu extends ConsumerWidget {
  const ExerciseMenu({super.key, required this.exercise, required this.gym, this.showsFocus = false});

  final LoggedExercise exercise;
  final GymController gym;
  final bool showsFocus;

  static const bars = [
    (20.0, 'Langhantel 20 kg'),
    (15.0, 'Langhantel 15 kg'),
    (10.0, 'SZ-Stange 10 kg'),
    (25.0, 'Trap Bar 25 kg'),
    (7.5, 'Kurze Stange 7,5 kg'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = gym.active;
    if (session == null) return const SizedBox.shrink();
    final settings = ref.read(coachSettingsProvider);
    final info = settings.gym.exercise(exercise.exerciseID);
    final index = session.exercises.indexWhere((other) => other.id == exercise.id);
    final isLast = index >= session.exercises.length - 1;
    final note = settings.gym.notes[exercise.exerciseID];
    PopupMenuItem<VoidCallback> item(String title, IconData icon, VoidCallback action, {bool destructive = false}) =>
        PopupMenuItem(
          value: action,
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(icon, color: destructive ? Colors.red : null),
            title: Text(title, style: destructive ? const TextStyle(color: Colors.red) : null),
          ),
        );
    return PopupMenuButton<VoidCallback>(
      tooltip: 'Optionen für ${exercise.name}',
      icon: const Icon(Icons.more_horiz),
      onSelected: (action) => action(),
      itemBuilder: (_) => [
        if (showsFocus) item('Auf der Fokus-Karte zeigen', Icons.center_focus_strong, () => gym.focus(exercise.id)),
        if (!isLast) item('Später (Gerät belegt)', Icons.low_priority, () => gym.moveToEnd(exercise.id)),
        if (exercise.skipped)
          item('Wieder aufnehmen', Icons.undo, () => gym.resume(exercise.id))
        else if (exercise.sets.any((set) => !set.done))
          item('Überspringen', Icons.skip_next, () => gym.skip(exercise.id)),
        item('Ersetzen …', Icons.swap_horiz, () => _push(context, ReplaceExerciseScreen(exercise: exercise, gym: gym))),
        item('Reihenfolge ändern …', Icons.swap_vert, () => _push(context, ReorderExercisesScreen(gym: gym))),
        if (exercise.supersetID != null)
          item('Supersatz auflösen', Icons.link_off, () => gym.toggleSuperset(exercise.id))
        else if (!isLast)
          item('Supersatz mit ${session.exercises[index + 1].name}', Icons.link, () => gym.toggleSuperset(exercise.id)),
        const PopupMenuDivider(),
        item('Satz hinzufügen', Icons.add_circle_outline, () => gym.addSet(exercise.id)),
        item('Pause ${RestText.format(exercise.restSeconds)}', Icons.timer_outlined, () => _pickRest(context, ref)),
        item(note == null ? 'Notiz …' : 'Notiz ändern …', Icons.sticky_note_2_outlined, () => _editNote(context, ref)),
        if (info?.equipment.firstOrNull == Equipment.barbell)
          item(
            'Stange: ${GermanFormat.number(settings.gym.bar(exercise.exerciseID))} kg',
            Icons.horizontal_rule,
            () => _pickBar(context, ref),
          ),
        item(
          'Anleitung und Verlauf',
          Icons.info_outline,
          () => _push(context, ExerciseDetailScreen(exerciseID: exercise.exerciseID, gym: gym, showsDone: true)),
        ),
        const PopupMenuDivider(),
        item('Übung entfernen', Icons.delete_outline, () => gym.removeExercise(exercise.id), destructive: true),
      ],
    );
  }

  void _push(BuildContext context, Widget page) =>
      unawaited(Navigator.of(context).push(MaterialPageRoute<void>(fullscreenDialog: true, builder: (_) => page)));

  /// Pause der Übung; gilt sofort und – gemerkt – auch beim nächsten Mal.
  Future<void> _pickRest(BuildContext context, WidgetRef ref) async {
    final current = RestText.options.reduce(
      (a, b) => (a - exercise.restSeconds).abs() <= (b - exercise.restSeconds).abs() ? a : b,
    );
    final seconds = await showDialog<int>(
      context: context,
      builder: (dialog) => SimpleDialog(
        title: const Text('Pause'),
        children: [
          for (final option in RestText.options)
            SimpleDialogOption(
              onPressed: () => Navigator.of(dialog).pop(option),
              child: Text(
                RestText.format(option),
                style: TextStyle(fontWeight: option == current ? FontWeight.bold : null),
              ),
            ),
        ],
      ),
    );
    if (seconds == null) return;
    if (gym.setRest(seconds, of: exercise.id) case final remembered?) {
      changeGym(
        ref.read(coachSettingsProvider),
        (gym) => gym.restOverrides[remembered.exerciseID] = remembered.seconds,
      );
    }
  }

  Future<void> _editNote(BuildContext context, WidgetRef ref) async {
    final settings = ref.read(coachSettingsProvider);
    final controller = TextEditingController(text: settings.gym.notes[exercise.exerciseID] ?? '');
    final text = await showDialog<String>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: Text('Notiz zu ${exercise.name}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Steht ab jetzt bei jeder Einheit unter der Übung.'),
            TextField(
              controller: controller,
              autofocus: true,
              decoration: const InputDecoration(hintText: 'z. B. Sitz 4, Griff weit'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialog).pop(), child: const Text('Abbrechen')),
          TextButton(onPressed: () => Navigator.of(dialog).pop(controller.text), child: const Text('Sichern')),
        ],
      ),
    );
    controller.dispose();
    if (text == null) return;
    final trimmed = text.trim();
    changeGym(settings, (gym) {
      if (trimmed.isEmpty) {
        gym.notes.remove(exercise.exerciseID);
      } else {
        gym.notes[exercise.exerciseID] = trimmed;
      }
    });
  }

  Future<void> _pickBar(BuildContext context, WidgetRef ref) async {
    final weight = await showDialog<double>(
      context: context,
      builder: (dialog) => SimpleDialog(
        title: const Text('Stange'),
        children: [
          for (final (weight, label) in bars)
            SimpleDialogOption(onPressed: () => Navigator.of(dialog).pop(weight), child: Text(label)),
        ],
      ),
    );
    if (weight == null) return;
    changeGym(ref.read(coachSettingsProvider), (gym) => gym.bars[exercise.exerciseID] = weight);
  }
}

/// Alternativen für dieselbe Muskelgruppe mit der eigenen Ausstattung.
class ReplaceExerciseScreen extends ConsumerWidget {
  const ReplaceExerciseScreen({super.key, required this.exercise, required this.gym});

  final LoggedExercise exercise;
  final GymController gym;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(coachSettingsProvider).gym;
    final options = WorkoutEdits.alternatives(
      exercise.exerciseID,
      custom: settings.customExercises,
      equipment: settings.equipment,
    );
    void choose(ExerciseInfo option) {
      gym.replace(exercise.id, option);
      Navigator.of(context).pop();
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('${exercise.name} ersetzen'),
        leading: TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Abbrechen')),
        leadingWidth: 100,
      ),
      body: ListView(
        children: [
          for (final option in options) ExerciseLabel(exercise: option, onTap: () => choose(option)),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              exercise.sets.any((set) => set.done)
                  ? 'Erledigte Sätze bleiben bei ${exercise.name}; die offenen übernimmt die neue Übung.'
                  : 'Satzzahl und Wiederholungen bleiben, das Gewicht kommt aus deinem Verlauf.',
              style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
          ),
          ListTile(
            title: const Text('Andere Übung wählen …'),
            onTap: () async {
              final option = await Navigator.of(context).push<ExerciseInfo>(
                MaterialPageRoute(fullscreenDialog: true, builder: (_) => const ExercisePickerScreen()),
              );
              if (option != null) choose(option);
            },
          ),
        ],
      ),
    );
  }
}

class ReorderExercisesScreen extends StatelessWidget {
  const ReorderExercisesScreen({super.key, required this.gym});

  final GymController gym;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: gym,
    builder: (context, _) {
      final exercises = gym.active?.exercises ?? const <LoggedExercise>[];
      return Scaffold(
        appBar: AppBar(
          title: const Text('Reihenfolge'),
          automaticallyImplyLeading: false,
          actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Fertig'))],
        ),
        body: ReorderableListView(
          onReorderItem: (from, to) => gym.moveExercises(fromOffsets: {from}, toOffset: to > from ? to + 1 : to),
          children: [
            for (final exercise in exercises)
              ListTile(
                key: ValueKey(exercise.id),
                leading: const Icon(Icons.drag_handle),
                title: Text(exercise.name),
                trailing: Text(() {
                  final progress = WorkoutFlow.progress(exercise);
                  return '${progress.done}/${progress.total}';
                }()),
              ),
          ],
        ),
      );
    },
  );
}

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
                  Text(label, style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurfaceVariant)),
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
                            style: TextStyle(fontSize: 16, color: theme.colorScheme.onSurfaceVariant),
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

/// Dauer, Sätze, Volumen als Kacheln.
class SummaryGrid extends StatelessWidget {
  const SummaryGrid({super.key, required this.summary});

  final FlowSummary summary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget cell(String value, String label) => Expanded(
      child: Container(
        constraints: const BoxConstraints(minHeight: 64),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            Text(label, style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurfaceVariant)),
          ],
        ),
      ),
    );
    return Row(
      spacing: 8,
      children: [
        cell('${summary.minutes} min', 'Dauer'),
        cell('${summary.doneSets}', 'Sätze'),
        cell('${GermanFormat.number(summary.volumeKg.roundToDouble())} kg', 'Volumen'),
      ],
    );
  }
}

/// Vor dem Speichern: Zusammenfassung und vergessene Sätze. Gibt `true` (mit offenen Sätzen), `false` (nur abgehakte)
/// oder `null` (weiter trainieren) zurück.
class FinishWorkoutSheet extends StatelessWidget {
  const FinishWorkoutSheet({super.key, required this.session});

  final GymSession session;

  @override
  Widget build(BuildContext context) {
    final summary = WorkoutFlow.summary(session);
    final skipped = WorkoutFlow.skippedCount(session);
    Widget big(String title, {required bool prominent, required bool completing}) {
      final style = ButtonStyle(
        minimumSize: const WidgetStatePropertyAll(Size.fromHeight(52)),
        shape: WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
      );
      final text = Text(title, style: const TextStyle(fontWeight: FontWeight.bold));
      void tap() => Navigator.of(context).pop(completing);
      return prominent
          ? FilledButton(style: style, onPressed: tap, child: text)
          : OutlinedButton(style: style, onPressed: tap, child: text);
    }

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 14,
          children: [
            Text('Einheit beenden', style: Theme.of(context).textTheme.titleMedium, textAlign: TextAlign.center),
            SummaryGrid(summary: summary),
            if (skipped > 0)
              ListTile(
                leading: const Icon(Icons.skip_next),
                title: Text(
                  skipped == 1
                      ? '1 Übung übersprungen – ihre offenen Sätze werden nicht gespeichert.'
                      : '$skipped Übungen übersprungen – ihre offenen Sätze werden nicht gespeichert.',
                ),
              ),
            if (summary.openSets > 0) ...[
              ListTile(
                leading: const Icon(Icons.error_outline),
                title: Text(
                  summary.openSets == 1
                      ? '1 Satz ist eingetragen, aber nicht abgehakt.'
                      : '${summary.openSets} Sätze sind eingetragen, aber nicht abgehakt.',
                ),
              ),
              big('Mit offenen Sätzen speichern', prominent: true, completing: true),
              if (summary.doneSets > 0) big('Nur abgehakte speichern', prominent: false, completing: false),
            ] else if (summary.doneSets > 0)
              big('Speichern', prominent: true, completing: false)
            else
              const Text('Noch kein Satz erledigt – nichts zu speichern.', textAlign: TextAlign.center),
            TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Weiter trainieren')),
          ],
        ),
      ),
    );
  }
}

/// Erscheint, sobald der letzte Satz des Plans erledigt ist: beenden, Übung dazu oder weiter trainieren.
enum PlanCompleteChoice { finish, addExercise }

class PlanCompleteSheet extends StatelessWidget {
  const PlanCompleteSheet({super.key, required this.session});

  final GymSession session;

  @override
  Widget build(BuildContext context) {
    final summary = WorkoutFlow.summary(session);
    final skipped = WorkoutFlow.skippedCount(session);
    final theme = Theme.of(context);
    final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(14));
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 12,
          children: [
            Icon(Icons.sports_score, size: 40, color: theme.colorScheme.primary),
            Text('Plan geschafft', style: theme.textTheme.headlineSmall, textAlign: TextAlign.center),
            Text(
              '${summary.doneSets} Sätze · ${summary.minutes} min · '
              '${GermanFormat.number(summary.volumeKg.roundToDouble())} kg',
              textAlign: TextAlign.center,
              style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
            ),
            if (skipped > 0)
              Text(
                '$skipped Übung(en) übersprungen – beim Fortsetzen nachholbar.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: theme.colorScheme.onSurfaceVariant),
              ),
            FilledButton.icon(
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52), shape: shape),
              onPressed: () => Navigator.of(context).pop(PlanCompleteChoice.finish),
              icon: const Icon(Icons.check),
              label: const Text('Training beenden'),
            ),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48), shape: shape),
              onPressed: () => Navigator.of(context).pop(PlanCompleteChoice.addExercise),
              icon: const Icon(Icons.add),
              label: const Text('Übung hinzufügen'),
            ),
            TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Training fortsetzen')),
          ],
        ),
      ),
    );
  }
}

/// Abschluss nach dem Speichern. Steht in der Einheit selbst, damit nie ein leerer Bildschirm bleibt.
class WorkoutResultView extends StatelessWidget {
  const WorkoutResultView({super.key, required this.finished, required this.gym, required this.onClose});

  final FinishedWorkout finished;
  final GymController gym;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final secondary = TextStyle(fontSize: 12, color: theme.colorScheme.onSurfaceVariant);
    final heading = theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold);
    final muscles = finished.muscles.entries.where((entry) => entry.value > 0).toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final next = [
      for (final id in finished.exerciseIDs) ?gym.progress.where((item) => item.exerciseID == id).firstOrNull,
    ];
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Icon(Icons.verified, size: 48, color: Colors.green),
        const SizedBox(height: 8),
        Text(finished.title, style: theme.textTheme.headlineSmall, textAlign: TextAlign.center),
        const SizedBox(height: 16),
        SummaryGrid(summary: finished.summary),
        if (finished.volumeChange case final change?)
          ListTile(
            leading: Icon(change >= 0 ? Icons.north_east : Icons.south_east),
            title: Text('${change.abs()} % ${change >= 0 ? 'mehr' : 'weniger'} Volumen als beim letzten Mal'),
          ),
        if (finished.records.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text('Bestleistungen', style: heading),
          for (final record in finished.records)
            ListTile(
              dense: true,
              leading: const Icon(Icons.emoji_events, color: Colors.amber),
              title: Text(record),
            ),
        ],
        if (muscles.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text('Beanspruchte Muskeln', style: heading),
          const SizedBox(height: 8),
          BodyMap(values: finished.muscles, full: 6),
          const SizedBox(height: 6),
          Text(
            '${muscles.take(5).map((entry) => '${entry.key.label} ${GermanFormat.decimal(entry.value)}').join(' · ')}'
            ' Sätze. Hauptmuskel zählt voll, mitarbeitende halb – eine Schätzung.',
            style: secondary,
          ),
        ],
        // „Nächstes Mal“: die Entscheidung der Progression, sobald die neue Einheit eingerechnet ist.
        if (next.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text('Nächstes Mal', style: heading),
          for (final item in next)
            ListTile(
              dense: true,
              title: Text(item.name, style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text(item.headline),
            ),
        ],
        if (gym.hints.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text('Hinweise', style: heading),
          for (final hint in gym.hints) Padding(padding: const EdgeInsets.only(top: 4), child: Text('• $hint')),
          Text(gym.hintSource, style: secondary),
        ],
        const SizedBox(height: 12),
        Text(finished.status, style: secondary),
        const SizedBox(height: 16),
        FilledButton(
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(52),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
          onPressed: onClose,
          child: const Text('Fertig', style: TextStyle(fontWeight: FontWeight.bold)),
        ),
      ],
    );
  }
}

/// Die letzten Leistungen der Übung, klein unter der Eingabe: „80 kg × 10“, neueste zuerst.
class RecentPerformances extends ConsumerWidget {
  const RecentPerformances({super.key, required this.exercise, required this.gym});

  final LoggedExercise exercise;
  final GymController gym;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final info = ref.watch(coachSettingsProvider).gym.exercise(exercise.exerciseID);
    final items = gym.recentPerformances(exercise.exerciseID);
    if (items.isEmpty) return const SizedBox.shrink();
    final style = TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant);
    return Semantics(
      label: 'Letzte Leistungen',
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: 3,
          children: [
            Text('Zuletzt', style: style.copyWith(fontSize: 11, fontWeight: FontWeight.bold)),
            for (final item in items)
              Row(
                children: [
                  Text(
                    item.text(
                      isTime: info?.tracking == ExerciseTracking.time,
                      allowsAssistance: ExerciseUnits.allowsAssistance(info),
                    ),
                    style: style,
                  ),
                  const Spacer(),
                  Text(DateFormat('d. MMM', 'de_DE').format(item.day.referenceDate), style: style),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
