import 'dart:async';
import 'dart:math' as math;

import 'package:coach_core/coach_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/settings/settings_store.dart';
import '../../data/storage.dart';
import '../../services/gym/rest_alarm.dart';
import '../../services/providers.dart';
import 'exercise_picker.dart';
import 'gym_controller.dart';
import 'gym_providers.dart';
import 'workout_parts.dart';

/// Welche Übung und welcher Satz auf der Fokus-Karte stehen; `set == null`: alle Sätze dieser Übung erledigt.
({int exercise, int? set})? focusTarget(GymSession session, String? focus) {
  final index = focus == null ? -1 : session.exercises.indexWhere((exercise) => exercise.id == focus);
  if (index >= 0) {
    final open = session.exercises[index].sets.indexWhere((set) => !set.done);
    return (exercise: index, set: open < 0 ? null : open);
  }
  final position = WorkoutFlow.current(session);
  return position == null ? null : (exercise: position.exercise, set: position.set);
}

/// Laufende Einheit. Standard ist die Fokus-Karte: nur der nächste Satz, groß, mit einem Knopf zum Abhaken im
/// Daumenbereich. Die Liste zeigt alle Übungen auf einmal (Port von `ActiveWorkoutView`).
class ActiveWorkoutScreen extends ConsumerStatefulWidget {
  const ActiveWorkoutScreen({super.key});

  @override
  ConsumerState<ActiveWorkoutScreen> createState() => _ActiveWorkoutScreenState();
}

class _ActiveWorkoutScreenState extends ConsumerState<ActiveWorkoutScreen> {
  late final GymController _gym = ref.read(gymControllerProvider);
  late final SettingsStore _store = ref.read(settingsStoreProvider);
  Timer? _ticker;
  Timer? _restTimer;
  Timer? _warningTimer;
  Timer? _undoTimer;
  DateTime? _scheduledRest;
  String? _undoShown;
  int _doneSets = 0;
  int _planComplete = 0;
  int _restFinished = 0;
  bool _sheetOpen = false;

  bool get _showsList => _store.boolValue(SettingsKeys.gymShowsList);

  @override
  void initState() {
    super.initState();
    NotificationRestAlarm.workoutIsOpen = true;
    _doneSets = _gym.active?.doneSetCount ?? 0;
    _planComplete = _gym.planCompleteCount;
    _restFinished = _gym.restFinishedCount;
    _gym.addListener(_changed);
    // Uhr der Einheit und Pausen-Countdown.
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && _gym.active != null) setState(() {});
    });
    _scheduleRest();
  }

  @override
  void dispose() {
    NotificationRestAlarm.workoutIsOpen = false;
    _gym.removeListener(_changed);
    for (final timer in [_ticker, _restTimer, _warningTimer, _undoTimer]) {
      timer?.cancel();
    }
    super.dispose();
  }

  void _changed() {
    if (!mounted) return;
    final gym = _gym;
    // Kurze Vibration beim Abhaken und am Ende der Pause.
    final done = gym.active?.doneSetCount ?? 0;
    if (done > _doneSets) unawaited(HapticFeedback.mediumImpact());
    _doneSets = done;
    if (gym.restFinishedCount != _restFinished) {
      _restFinished = gym.restFinishedCount;
      if (ref.read(coachSettingsProvider).gym.restHaptic) unawaited(HapticFeedback.heavyImpact());
    }
    _scheduleRest();
    // Rückgängig verschwindet nach 5 Sekunden.
    if (gym.undoLabel != _undoShown) {
      _undoShown = gym.undoLabel;
      _undoTimer?.cancel();
      if (gym.undoLabel != null) _undoTimer = Timer(const Duration(seconds: 5), gym.clearUndo);
    }
    // Letzter Satz des Plans: fragen, ob beendet oder weiter trainiert wird.
    if (gym.planCompleteCount != _planComplete) {
      _planComplete = gym.planCompleteCount;
      if (gym.active != null && !_sheetOpen) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _showPlanComplete());
      }
    }
    if (gym.message != null && gym.active != null && !_sheetOpen) {
      final message = gym.message!;
      gym.message = null;
      WidgetsBinding.instance.addPostFrameCallback((_) => _alert(message));
    }
    setState(() {});
  }

  /// 10 Sekunden vor Pausenende kurz antippen, am Ende Signal; neue Pause ersetzt die alte.
  void _scheduleRest() {
    final end = _gym.restEndsAt;
    if (end == _scheduledRest) return;
    _scheduledRest = end;
    _restTimer?.cancel();
    _warningTimer?.cancel();
    if (end == null) return;
    final remaining = end.difference(DateTime.now());
    if (remaining > const Duration(seconds: 10)) {
      _warningTimer = Timer(remaining - const Duration(seconds: 10), () {
        if (_gym.restEndsAt == end) unawaited(HapticFeedback.lightImpact());
      });
    }
    _restTimer = Timer(remaining.isNegative ? Duration.zero : remaining, () {
      if (_gym.restEndsAt == end) _gym.restFinished(end);
    });
  }

  Future<void> _alert(String message) => showDialog<void>(
    context: context,
    builder: (dialog) => AlertDialog(
      title: const Text('Hinweis'),
      content: Text(message),
      actions: [TextButton(onPressed: () => Navigator.of(dialog).pop(), child: const Text('OK'))],
    ),
  );

  Future<T?> _sheet<T>(Widget Function(BuildContext context) builder) async {
    _sheetOpen = true;
    try {
      return await showModalBottomSheet<T>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: builder,
      );
    } finally {
      _sheetOpen = false;
    }
  }

  Future<void> _showPlanComplete() async {
    final session = _gym.active;
    if (session == null) return;
    final choice = await _sheet<PlanCompleteChoice>((_) => PlanCompleteSheet(session: session));
    if (!mounted) return;
    switch (choice) {
      case PlanCompleteChoice.finish:
        await _showFinish();
      case PlanCompleteChoice.addExercise:
        await _addExercise();
      case null:
        break;
    }
  }

  Future<void> _addExercise() async {
    final exercise = await Navigator.of(context)
        .push<ExerciseInfo>(MaterialPageRoute(fullscreenDialog: true, builder: (_) => const ExercisePickerScreen()));
    if (exercise != null) _gym.addExercise(exercise);
  }

  Future<void> _showFinish() async {
    final session = _gym.active;
    if (session == null) return;
    final completing = await _sheet<bool>((_) => FinishWorkoutSheet(session: session));
    if (completing == null || !mounted) return;
    await _gym.finish(
      repository: ref.read(gymRepositoryProvider),
      writer: ref.read(workoutWriterProvider),
      strength: ref.read(garminStrengthServiceProvider),
      garmin: ref.read(garminConnectProvider),
      completingOpenSets: completing,
    );
    unawaited(ref.read(appModelProvider).refreshReminders());
  }

  Future<void> _confirmCancel() async {
    final cancel = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Einheit verwerfen?'),
        content: const Text('Alle Sätze dieser Einheit gehen verloren.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialog).pop(false), child: const Text('Abbrechen')),
          TextButton(
            onPressed: () => Navigator.of(dialog).pop(true),
            child: const Text('Verwerfen', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (cancel != true || !mounted) return;
    _gym.cancelActive();
    Navigator.of(context).pop();
  }

  void _edit(String exerciseID, int set, SetField field) =>
      unawaited(_sheet<void>((_) => SetValuePad(gym: _gym, exerciseID: exerciseID, set: set, field: field)));

  @override
  Widget build(BuildContext context) {
    final gym = _gym;
    final session = gym.active;
    final finished = gym.finished;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Ausblenden',
          icon: const Icon(Icons.keyboard_arrow_down),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: session == null
            ? null
            : SegmentedButton<bool>(
                showSelectedIcon: false,
                style: const ButtonStyle(visualDensity: VisualDensity.compact),
                segments: const [
                  ButtonSegment(value: false, label: Text('Fokus')),
                  ButtonSegment(value: true, label: Text('Liste')),
                ],
                selected: {_showsList},
                onSelectionChanged: (value) async {
                  await _store.setBool(SettingsKeys.gymShowsList, value.first);
                  if (mounted) setState(() {});
                },
              ),
        actions: [
          if (session != null) ...[
            PopupMenuButton<String>(
              tooltip: 'Mehr',
              onSelected: (value) => value == 'add' ? _addExercise() : _confirmCancel(),
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'add', child: Text('Übung hinzufügen')),
                PopupMenuItem(
                  value: 'cancel',
                  child: Text('Einheit verwerfen', style: TextStyle(color: Colors.red)),
                ),
              ],
            ),
            TextButton(
              onPressed: gym.isSaving ? null : _showFinish,
              child: const Text('Beenden', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ],
      ),
      body: Stack(
        children: [
          if (session != null)
            Column(
              children: [
                Expanded(
                  child: _showsList
                      ? WorkoutList(session: session, gym: gym, edit: _edit, addExercise: _addExercise)
                      : FocusCard(session: session, gym: gym, edit: _edit),
                ),
                SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      spacing: 10,
                      children: [
                        _HoldCorrection(session: session, gym: gym),
                        _RestPanel(gym: gym, store: _store),
                        if (!_showsList) _DoneButton(session: session, gym: gym, finish: _showFinish),
                      ],
                    ),
                  ),
                ),
              ],
            )
          else if (finished != null)
            WorkoutResultView(
              finished: finished,
              gym: gym,
              onClose: () {
                gym.dismissFinished();
                Navigator.of(context).pop();
              },
            )
          else
            const Center(child: Text('Keine laufende Einheit')),
          if (gym.isSaving) const Center(child: CircularProgressIndicator()),
          if (gym.undoLabel case final label?)
            Positioned(
              top: 8,
              left: 16,
              right: 16,
              child: _UndoToast(label: label, onUndo: gym.undo),
            ),
        ],
      ),
    );
  }
}

class FocusCard extends ConsumerWidget {
  const FocusCard({super.key, required this.session, required this.gym, required this.edit});

  final GymSession session;
  final GymController gym;
  final void Function(String exerciseID, int set, SetField field) edit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final target = focusTarget(session, gym.focusExerciseID);
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _ExerciseStrip(session: session, gym: gym, shown: target?.exercise),
        const SizedBox(height: 18),
        if (target == null)
          _allDone(context)
        else ...[
          _header(context, session.exercises[target.exercise], target.set),
          const SizedBox(height: 14),
          if (target.set case final set?)
            _SetEditor(exercise: session.exercises[target.exercise], index: set, gym: gym, edit: edit)
          else
            _exerciseDone(session.exercises[target.exercise]),
          const SizedBox(height: 14),
          ExerciseNotes(exercise: session.exercises[target.exercise], gym: gym, set: target.set, offersWarmUp: true),
          if (target.set case final set?)
            if (WorkoutFlow.upcoming(FlowPosition(exercise: target.exercise, set: set), session) case final next?
                when next.exercise == target.exercise)
              Padding(
                padding: const EdgeInsets.only(top: 14),
                child: Text(
                  'Als Nächstes: Satz ${next.set + 1} · ${setValues(session.exercises[next.exercise].sets[next.set])}',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, color: theme.colorScheme.onSurfaceVariant),
                ),
              ),
          if (WorkoutFlow.nextExercise(target.exercise, session) case final following?)
            Padding(
              padding: const EdgeInsets.only(top: 14),
              child: _NextExercisePreview(exercise: session.exercises[following], gym: gym),
            ),
        ],
      ],
    );
  }

  Widget _header(BuildContext context, LoggedExercise exercise, int? set) {
    final theme = Theme.of(context);
    final label = WorkoutFlow.supersetLabels(session)[exercise.id];
    final secondary = theme.colorScheme.onSurfaceVariant;
    return Column(
      spacing: 4,
      children: [
        Row(
          children: [
            Text(
              elapsedText(session.start, DateTime.now()),
              style: TextStyle(fontSize: 13, color: secondary, fontFeatures: const [FontFeature.tabularFigures()]),
            ),
            const Spacer(),
            ExerciseMenu(exercise: exercise, gym: gym),
          ],
        ),
        if (label != null)
          Text(
            'Supersatz $label',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: theme.colorScheme.primary),
          ),
        Text(
          exercise.name,
          textAlign: TextAlign.center,
          style: theme.textTheme.headlineMedium?.copyWith(
            fontWeight: FontWeight.bold,
            color: exercise.skipped ? secondary : null,
          ),
        ),
        if (exercise.skipped)
          Text(
            'Übersprungen',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: secondary),
          ),
        if (set != null)
          Wrap(
            alignment: WrapAlignment.center,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 12,
            children: [
              _SetKindMenu(
                set: exercise.sets[set],
                index: set,
                total: exercise.sets.length,
                change: (kind) => gym.setKind(kind, set: set, of: exercise.id),
              ),
              if (exercise.skipped)
                TextButton.icon(
                  onPressed: () => gym.resume(exercise.id),
                  icon: const Icon(Icons.undo),
                  label: const Text('Wieder aufnehmen'),
                )
              else
                Semantics(
                  hint: 'Weiter mit der nächsten Übung, offene Sätze werden nicht gespeichert',
                  child: TextButton.icon(
                    onPressed: () => gym.skip(exercise.id),
                    icon: const Icon(Icons.skip_next),
                    label: const Text('Überspringen'),
                  ),
                ),
            ],
          ),
      ],
    );
  }

  Widget _exerciseDone(LoggedExercise exercise) => Column(
    spacing: 12,
    children: [
      const Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.check_circle, color: Colors.green),
          SizedBox(width: 6),
          Text(
            'Alle Sätze erledigt',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.green),
          ),
        ],
      ),
      OutlinedButton.icon(
        onPressed: () => gym.addSet(exercise.id),
        icon: const Icon(Icons.add_circle_outline),
        label: const Text('Noch einen Satz'),
      ),
      if (WorkoutFlow.current(session, preferring: exercise.id) != null)
        OutlinedButton.icon(
          onPressed: () => gym.focus(null),
          icon: const Icon(Icons.arrow_forward),
          label: const Text('Zur nächsten Übung'),
        ),
    ],
  );

  /// Plan geschafft: beenden oder fortsetzen (Übung dazu, übersprungene wieder aufnehmen).
  Widget _allDone(BuildContext context) {
    final skipped = [
      for (final exercise in session.exercises)
        if (exercise.skipped && exercise.sets.any((set) => !set.done)) exercise,
    ];
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 30),
      child: Column(
        spacing: 14,
        children: [
          const Icon(Icons.emoji_events, size: 48, color: Colors.amber),
          Text('Plan geschafft', style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
          Text(
            '${session.doneSetCount} Sätze · ${GermanFormat.number(session.volumeKg.roundToDouble())} kg bewegt',
            style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
          ),
          if (skipped.isNotEmpty) ...[
            const Text('Übersprungen', style: TextStyle(fontWeight: FontWeight.bold)),
            for (final exercise in skipped)
              OutlinedButton.icon(
                onPressed: () => gym.resume(exercise.id),
                icon: const Icon(Icons.undo),
                label: Text('${exercise.name} nachholen'),
              ),
          ],
        ],
      ),
    );
  }
}

/// Übungen als Leiste mit Fortschritt; Tippen wählt die Übung für die Fokus-Karte.
class _ExerciseStrip extends StatelessWidget {
  const _ExerciseStrip({required this.session, required this.gym, required this.shown});

  final GymSession session;
  final GymController gym;
  final int? shown;

  @override
  Widget build(BuildContext context) {
    final labels = WorkoutFlow.supersetLabels(session);
    final theme = Theme.of(context);
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        spacing: 8,
        children: [
          for (final (index, exercise) in session.exercises.indexed)
            () {
              final progress = WorkoutFlow.progress(exercise);
              final complete = progress.total > 0 && progress.done == progress.total;
              final dimmed = exercise.skipped && !complete;
              return Opacity(
                opacity: dimmed ? 0.5 : 1,
                child: Material(
                  color: index == shown
                      ? theme.colorScheme.primary.withValues(alpha: 0.2)
                      : theme.colorScheme.surfaceContainerHighest,
                  shape: const StadiumBorder(),
                  child: InkWell(
                    customBorder: const StadiumBorder(),
                    onTap: () => gym.focus(exercise.id),
                    child: Container(
                      constraints: const BoxConstraints(minHeight: 40),
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        spacing: 4,
                        children: [
                          if (complete) const Icon(Icons.check, size: 16),
                          if (dimmed) const Icon(Icons.skip_next, size: 16),
                          if (labels[exercise.id] case final label?)
                            Text(
                              label,
                              style: TextStyle(fontWeight: FontWeight.bold, color: theme.colorScheme.primary),
                            ),
                          Text(exercise.name, maxLines: 1),
                          Text(
                            '${progress.done}/${progress.total}',
                            style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            }(),
        ],
      ),
    );
  }
}

/// Gewicht und Wiederholungen nebeneinander, je groß mit − und +. Tippen auf eine Zahl öffnet den Ziffernblock.
/// Jede Änderung betrifft nur diesen Satz.
class _SetEditor extends ConsumerWidget {
  const _SetEditor({required this.exercise, required this.index, required this.gym, required this.edit});

  final LoggedExercise exercise;
  final int index;
  final GymController gym;
  final void Function(String exerciseID, int set, SetField field) edit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(coachSettingsProvider).gym;
    final info = settings.exercise(exercise.exerciseID);
    final isTime = info?.tracking == ExerciseTracking.time;
    final step = ExerciseLibrary.rule(exercise.exerciseID, name: exercise.name, custom: settings.customExercises).step;
    final set = exercise.sets[index];
    final weight = ExerciseUnits.weightText(set.weightKg, info: info);
    // Mit Unterstützung darf das Gewicht unter 0 gehen (−20 kg = 20 kg Hilfe).
    final lowest = ExerciseUnits.allowsAssistance(info) ? -200.0 : 0.0;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        spacing: 10,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 10,
            children: [
              _ValueColumn(
                text: weight.value,
                unit: weight.unit,
                label: 'Gewicht',
                minus: () => gym.setWeight(math.max(lowest, set.weightKg - step), set: index, of: exercise.id),
                plus: () => gym.setWeight(set.weightKg + step, set: index, of: exercise.id),
                edit: () => edit(exercise.id, index, SetField.weight),
              ),
              _ValueColumn(
                text: '${set.reps}',
                unit: ExerciseUnits.repsUnit(exercise.exerciseID, isTime: isTime),
                label: isTime ? 'Sekunden' : 'Wiederholungen',
                minus: () => gym.setReps(set.reps - (isTime ? 5 : 1), set: index, of: exercise.id),
                plus: () => gym.setReps(set.reps + (isTime ? 5 : 1), set: index, of: exercise.id),
                edit: () => edit(exercise.id, index, SetField.reps),
              ),
            ],
          ),
          RecentPerformances(exercise: exercise, gym: gym),
        ],
      ),
    );
  }
}

/// Eine Spalte: Zahl (Tippen = Ziffernblock), darunter − und +.
class _ValueColumn extends StatelessWidget {
  const _ValueColumn({
    required this.text,
    required this.unit,
    required this.label,
    required this.minus,
    required this.plus,
    required this.edit,
  });

  final String text;
  final String unit;
  final String label;
  final VoidCallback minus;
  final VoidCallback plus;
  final VoidCallback edit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget round(IconData icon, String semantics, VoidCallback action) => Expanded(
      child: Semantics(
        label: semantics,
        button: true,
        excludeSemantics: true,
        child: Material(
          color: theme.colorScheme.surfaceContainerHighest,
          shape: const StadiumBorder(),
          child: InkWell(
            customBorder: const StadiumBorder(),
            onTap: () {
              HapticFeedback.selectionClick();
              action();
            },
            child: SizedBox(height: 52, child: Icon(icon, size: 28)),
          ),
        ),
      ),
    );
    return Expanded(
      child: Column(
        spacing: 8,
        children: [
          Semantics(
            label: '$label: $text $unit',
            hint: 'Tippen zum Eintippen',
            button: true,
            excludeSemantics: true,
            child: Material(
              color: theme.colorScheme.surfaceContainer,
              borderRadius: BorderRadius.circular(16),
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: edit,
                child: Container(
                  constraints: const BoxConstraints(minHeight: 92),
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      FittedBox(
                        child: Text(
                          text,
                          maxLines: 1,
                          style: TextStyle(
                            fontSize: text.length > 5 ? 30 : 46,
                            fontWeight: FontWeight.bold,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ),
                      FittedBox(
                        child: Text(
                          unit.isEmpty ? label : unit,
                          style: TextStyle(fontWeight: FontWeight.bold, color: theme.colorScheme.onSurfaceVariant),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Row(
            spacing: 8,
            children: [round(Icons.remove, '$label verringern', minus), round(Icons.add, '$label erhöhen', plus)],
          ),
        ],
      ),
    );
  }
}

/// „Satz 2 von 4“ mit Satzart (Aufwärmen, Drop-Satz …) zum Umstellen.
class _SetKindMenu extends StatelessWidget {
  const _SetKindMenu({required this.set, required this.index, required this.total, required this.change});

  final LoggedSet set;
  final int index;
  final int total;
  final ValueChanged<SetKind> change;

  @override
  Widget build(BuildContext context) {
    final secondary = Theme.of(context).colorScheme.onSurfaceVariant;
    return Semantics(
      label: 'Satz ${index + 1} von $total, ${set.kind.label}. Satzart ändern',
      button: true,
      excludeSemantics: true,
      child: PopupMenuButton<SetKind>(
        initialValue: set.kind,
        onSelected: change,
        itemBuilder: (_) => [for (final kind in SetKind.values) PopupMenuItem(value: kind, child: Text(kind.label))],
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            spacing: 6,
            children: [
              Text(
                'Satz ${index + 1} von $total',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16, color: secondary),
              ),
              if (set.kind != SetKind.working)
                Text(
                  set.kind.label,
                  style: const TextStyle(fontWeight: FontWeight.w600, color: Colors.orange),
                ),
              Icon(Icons.unfold_more, size: 16, color: secondary),
            ],
          ),
        ),
      ),
    );
  }
}

/// Vorschau der nächsten Übung: Name, Sätze und Startwerte – mit „Überspringen“, falls sie heute ausfällt.
class _NextExercisePreview extends StatelessWidget {
  const _NextExercisePreview({required this.exercise, required this.gym});

  final LoggedExercise exercise;
  final GymController gym;

  @override
  Widget build(BuildContext context) {
    final open = exercise.sets.where((set) => !set.done).toList();
    final theme = Theme.of(context);
    final secondary = TextStyle(fontSize: 12, color: theme.colorScheme.onSurfaceVariant);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 2,
              children: [
                Text('Danach', style: secondary.copyWith(fontSize: 11, fontWeight: FontWeight.bold)),
                Text(exercise.name, maxLines: 1, style: const TextStyle(fontWeight: FontWeight.bold)),
                Text('${open.length} Sätze${open.isEmpty ? '' : ' · ${setValues(open.first)}'}', style: secondary),
              ],
            ),
          ),
          IconButton(
            tooltip: '${exercise.name} überspringen',
            icon: const Icon(Icons.skip_next),
            onPressed: () => gym.skip(exercise.id),
          ),
        ],
      ),
    );
  }
}

/// Großer Knopf im Daumenbereich: hakt den Satz der Fokus-Karte ab (bei Halteübungen die Stoppuhr).
class _DoneButton extends ConsumerWidget {
  const _DoneButton({required this.session, required this.gym, required this.finish});

  final GymSession session;
  final GymController gym;
  final VoidCallback finish;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final target = focusTarget(session, gym.focusExerciseID);
    final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(18));
    if (target == null) {
      return FilledButton.icon(
        style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(60), shape: shape),
        onPressed: finish,
        icon: const Icon(Icons.sports_score),
        label: const Text('Einheit beenden', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
      );
    }
    final set = target.set;
    if (set == null) return const SizedBox.shrink();
    final exercise = session.exercises[target.exercise];
    if (ref.watch(coachSettingsProvider).gym.exercise(exercise.exerciseID)?.tracking == ExerciseTracking.time) {
      return _HoldControls(exercise: exercise, set: set, gym: gym);
    }
    return FilledButton.icon(
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(60),
        shape: shape,
        backgroundColor: Colors.green,
      ),
      onPressed: () => gym.complete(set: set, of: exercise.id),
      icon: const Icon(Icons.check),
      label: const Text('Satz erledigt', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
    );
  }
}

/// Stoppuhr für Plank & Co.: Start, mitlaufende Zeit gegen das Ziel, Stopp übernimmt die Zeit und hakt ab.
class _HoldControls extends StatefulWidget {
  const _HoldControls({required this.exercise, required this.set, required this.gym});

  final LoggedExercise exercise;
  final int set;
  final GymController gym;

  @override
  State<_HoldControls> createState() => _HoldControlsState();
}

class _HoldControlsState extends State<_HoldControls> {
  bool _reached = false;

  @override
  Widget build(BuildContext context) {
    final gym = widget.gym;
    final target = widget.set < widget.exercise.sets.length ? widget.exercise.sets[widget.set].reps : 0;
    final hold = gym.hold;
    final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(18));
    if (hold != null && hold.exercise == widget.exercise.id && hold.set == widget.set) {
      final elapsed = math.max(0, DateTime.now().difference(hold.start).inSeconds);
      if (target > 0 && elapsed >= target && !_reached) {
        _reached = true;
        unawaited(HapticFeedback.mediumImpact());
      }
      return Column(
        mainAxisSize: MainAxisSize.min,
        spacing: 8,
        children: [
          Text(
            elapsedText(hold.start, DateTime.now()),
            style: const TextStyle(
              fontSize: 48,
              fontWeight: FontWeight.bold,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
          if (target > 0)
            Text(
              HoldTimer.targetText(elapsed: elapsed, target: target),
              style: TextStyle(
                fontWeight: FontWeight.w500,
                color: elapsed >= target ? Colors.green : Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(60),
              shape: shape,
              backgroundColor: Colors.red,
            ),
            onPressed: () {
              _reached = false;
              gym.stopHold();
            },
            icon: const Icon(Icons.stop),
            label: const Text('Stopp – Zeit übernehmen', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ),
          TextButton(
            onPressed: () {
              _reached = false;
              gym.cancelHold();
            },
            child: const Text('Abbrechen'),
          ),
        ],
      );
    }
    return Row(
      spacing: 10,
      children: [
        Expanded(
          child: FilledButton.icon(
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(60),
              shape: shape,
              backgroundColor: Colors.green,
            ),
            onPressed: () => gym.startHold(set: widget.set, of: widget.exercise.id),
            icon: const Icon(Icons.timer),
            label: Text(
              target > 0 ? 'Start · Ziel $target s' : 'Stoppuhr starten',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ),
        ),
        SizedBox(
          width: 60,
          height: 60,
          child: OutlinedButton(
            style: OutlinedButton.styleFrom(padding: EdgeInsets.zero, shape: shape),
            onPressed: () => gym.complete(set: widget.set, of: widget.exercise.id),
            child: Semantics(label: 'Ohne Stoppuhr erledigt ($target s)', child: const Icon(Icons.check)),
          ),
        ),
      ],
    );
  }
}

/// Nach dem Stopp: gemessene Zeit korrigieren, falls zu spät oder zu früh gestoppt.
class _HoldCorrection extends ConsumerWidget {
  const _HoldCorrection({required this.session, required this.gym});

  final GymSession session;
  final GymController gym;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final last = gym.lastDone;
    if (gym.hold != null || (gym.restEndsAt == null && gym.pendingRest == null) || last == null) {
      return const SizedBox.shrink();
    }
    final exercise = session.exercises.where((exercise) => exercise.id == last.exercise).firstOrNull;
    if (exercise == null ||
        last.set >= exercise.sets.length ||
        ref.watch(coachSettingsProvider).gym.exercise(exercise.exerciseID)?.tracking != ExerciseTracking.time) {
      return const SizedBox.shrink();
    }
    final seconds = exercise.sets[last.set].reps;
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            Text('Gehalten $seconds s', style: const TextStyle(fontWeight: FontWeight.w600)),
            const Spacer(),
            for (final delta in const [-5, -1, 1, 5])
              Padding(
                padding: const EdgeInsets.only(left: 6),
                child: Semantics(
                  label: '${delta.abs()} Sekunden ${delta > 0 ? 'mehr' : 'weniger'}',
                  button: true,
                  excludeSemantics: true,
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(minimumSize: const Size(44, 40), padding: EdgeInsets.zero),
                    onPressed: () => gym.correctHold(delta),
                    child: Text(delta > 0 ? '+$delta' : '−${-delta}'),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Pause groß mit Fortschrittsbalken; darunter freiwillig RIR für den gerade erledigten Satz. Klein gemacht nur
/// Restzeit und „Weiter“ (bleibt für die nächsten Pausen).
class _RestPanel extends ConsumerWidget {
  const _RestPanel({required this.gym, required this.store});

  final GymController gym;
  final SettingsStore store;

  /// Die neue Pause gilt auch für die nächsten Male dieser Übung.
  void _adjust(WidgetRef ref, int seconds) {
    final remembered = gym.adjustRestAndRemember(seconds);
    if (remembered == null) return;
    changeGym(ref.read(coachSettingsProvider), (gym) => gym.restOverrides[remembered.exerciseID] = remembered.seconds);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final end = gym.restEndsAt;
    final now = DateTime.now();
    if (gym.pendingRest case final pending? when end == null) {
      return OutlinedButton.icon(
        style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
        onPressed: gym.startRest,
        icon: const Icon(Icons.timer_outlined),
        label: Text('Pause starten · ${RestText.format(pending)}'),
      );
    }
    if (end == null || !end.isAfter(now)) return const SizedBox.shrink();
    final remaining = end.difference(now).inSeconds + 1;
    final countdown = '${remaining ~/ 60}:${(remaining % 60).toString().padLeft(2, '0')}';
    final collapsed = store.boolValue(SettingsKeys.gymRestPanelCollapsed);
    final theme = Theme.of(context);
    if (collapsed) {
      return Material(
        color: theme.colorScheme.surfaceContainerHigh,
        shape: const StadiumBorder(),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          child: Row(
            spacing: 10,
            children: [
              const ExcludeSemantics(child: Icon(Icons.timer_outlined)),
              Text(countdown, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              const Spacer(),
              OutlinedButton(onPressed: gym.skipRest, child: const Text('Weiter')),
              IconButton(
                tooltip: 'Pause groß anzeigen',
                icon: const Icon(Icons.keyboard_arrow_up),
                onPressed: () => store
                    .setBool(SettingsKeys.gymRestPanelCollapsed, false)
                    .then((_) => gym.focus(gym.focusExerciseID)),
              ),
            ],
          ),
        ),
      );
    }
    final total = math.max(gym.restSeconds, 1);
    return Material(
      color: theme.colorScheme.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(18),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          spacing: 10,
          children: [
            Row(
              children: [
                const Icon(Icons.timer_outlined),
                const SizedBox(width: 6),
                const Text('Pause', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
                IconButton(
                  tooltip: 'Pause klein machen',
                  icon: const Icon(Icons.keyboard_arrow_down),
                  onPressed: () => store
                      .setBool(SettingsKeys.gymRestPanelCollapsed, true)
                      .then((_) => gym.focus(gym.focusExerciseID)),
                ),
                const Spacer(),
                Text(
                  countdown,
                  style: const TextStyle(
                    fontSize: 36,
                    fontWeight: FontWeight.bold,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
            LinearProgressIndicator(value: (remaining / total).clamp(0, 1)),
            Row(
              spacing: 10,
              children: [
                Expanded(
                  child: Semantics(
                    label: 'Pause 15 Sekunden kürzer',
                    button: true,
                    excludeSemantics: true,
                    child: OutlinedButton(onPressed: () => _adjust(ref, -15), child: const Text('−15 s')),
                  ),
                ),
                Expanded(
                  child: Semantics(
                    label: 'Pause 15 Sekunden länger',
                    button: true,
                    excludeSemantics: true,
                    child: OutlinedButton(onPressed: () => _adjust(ref, 15), child: const Text('+15 s')),
                  ),
                ),
                Expanded(
                  child: FilledButton.tonal(
                    onPressed: gym.skipRest,
                    child: const Text('Weiter', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
            _ReserveQuestion(gym: gym),
          ],
        ),
      ),
    );
  }
}

/// „Wie viele wären noch gegangen?“ – fünf große Knöpfe statt eines zweiten Pflicht-Tipps pro Satz.
class _ReserveQuestion extends ConsumerWidget {
  const _ReserveQuestion({required this.gym});

  final GymController gym;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(coachSettingsProvider).gym;
    final last = gym.lastDone;
    final exercise = gym.active?.exercises.where((exercise) => exercise.id == last?.exercise).firstOrNull;
    if (!settings.tracksRIR ||
        last == null ||
        exercise == null ||
        last.set >= exercise.sets.length ||
        settings.exercise(exercise.exerciseID)?.tracking == ExerciseTracking.time) {
      return const SizedBox.shrink();
    }
    final current = exercise.sets[last.set].rir;
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 6,
      children: [
        Text(
          '${exercise.name}, Satz ${last.set + 1}: wie viele wären noch gegangen?',
          style: TextStyle(fontSize: 13, color: theme.colorScheme.onSurfaceVariant),
        ),
        Semantics(
          label: 'Wiederholungen in Reserve',
          child: Row(
            spacing: 8,
            children: [
              for (var value = 0; value < 5; value++)
                Expanded(
                  child: current == value
                      ? FilledButton(
                          style: FilledButton.styleFrom(minimumSize: const Size(0, 44), padding: EdgeInsets.zero),
                          onPressed: () => gym.setRIR(null, set: last.set, of: exercise.id),
                          child: Text(value == 4 ? '4+' : '$value'),
                        )
                      : OutlinedButton(
                          style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44), padding: EdgeInsets.zero),
                          onPressed: () => gym.setRIR(value, set: last.set, of: exercise.id),
                          child: Text(value == 4 ? '4+' : '$value'),
                        ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _UndoToast extends StatelessWidget {
  const _UndoToast({required this.label, required this.onUndo});

  final String label;
  final VoidCallback onUndo;

  @override
  Widget build(BuildContext context) => Material(
    elevation: 3,
    shape: const StadiumBorder(),
    color: Theme.of(context).colorScheme.surfaceContainerHighest,
    child: Container(
      constraints: const BoxConstraints(minHeight: 48),
      padding: const EdgeInsets.only(left: 16, right: 4),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          TextButton(
            onPressed: onUndo,
            child: const Text('Rückgängig', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    ),
  );
}

/// Liste aller Übungen mit ihren Sätzen.
class WorkoutList extends ConsumerWidget {
  const WorkoutList({
    super.key,
    required this.session,
    required this.gym,
    required this.edit,
    required this.addExercise,
  });

  final GymSession session;
  final GymController gym;
  final void Function(String exerciseID, int set, SetField field) edit;
  final VoidCallback addExercise;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(coachSettingsProvider);
    final labels = WorkoutFlow.supersetLabels(session);
    final theme = Theme.of(context);
    final secondary = theme.colorScheme.onSurfaceVariant;
    return ListView(
      padding: const EdgeInsets.only(bottom: 16),
      children: [
        ListTile(
          title: Text(
            elapsedText(session.start, DateTime.now()),
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
          trailing: Text('${session.doneSetCount} Sätze', style: TextStyle(color: secondary)),
        ),
        for (final exercise in session.exercises)
          Card(
            margin: const EdgeInsets.fromLTRB(12, 6, 12, 6),
            child: Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 4, 0),
                    child: Row(
                      spacing: 6,
                      children: [
                        if (labels[exercise.id] case final label?)
                          Text(
                            label,
                            style: TextStyle(fontWeight: FontWeight.bold, color: theme.colorScheme.primary),
                          ),
                        Expanded(
                          child: Text(
                            exercise.name + (exercise.skipped ? ' · übersprungen' : ''),
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                              color: exercise.skipped ? secondary : null,
                            ),
                          ),
                        ),
                        ExerciseMenu(exercise: exercise, gym: gym, showsFocus: true),
                      ],
                    ),
                  ),
                  for (final (index, set) in exercise.sets.indexed)
                    Dismissible(
                      key: ValueKey(set.id),
                      direction: DismissDirection.endToStart,
                      background: Container(color: Colors.red),
                      onDismissed: (_) => gym.removeSet(index, from: exercise.id),
                      // Übersprungen: offene Sätze leicht ausgegraut, bleiben aber bedienbar.
                      child: Opacity(
                        opacity: exercise.skipped && !set.done ? 0.45 : 1,
                        child: _SetRow(
                          index: index,
                          set: set,
                          info: settings.gym.exercise(exercise.exerciseID),
                          exerciseID: exercise.id,
                          gym: gym,
                          edit: (field) => edit(exercise.id, index, field),
                        ),
                      ),
                    ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: () => gym.addSet(exercise.id),
                      icon: const Icon(Icons.add_circle_outline),
                      label: const Text('Satz hinzufügen'),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      spacing: 6,
                      children: [
                        if (ComplaintArea.hint(
                              ComplaintArea.loaded(
                                exercise.exerciseID,
                                group: exercise.group,
                                custom: settings.gym.customExercises,
                                complaints: settings.mobility.complaints,
                              ),
                            )
                            case final hint?)
                          Text(hint, style: const TextStyle(fontSize: 12, color: Colors.orange)),
                        ExerciseNotes(exercise: exercise, gym: gym, centered: false),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ListTile(leading: const Icon(Icons.add), title: const Text('Übung hinzufügen'), onTap: addExercise),
      ],
    );
  }
}

/// Ein Satz in der Liste: Werte groß und antippbar (Ziffernblock), Abhaken mit großem Tippziel; lange drücken für
/// Satzart und Wiederholungen in Reserve.
class _SetRow extends StatelessWidget {
  const _SetRow({
    required this.index,
    required this.set,
    required this.info,
    required this.exerciseID,
    required this.gym,
    required this.edit,
  });

  final int index;
  final LoggedSet set;
  final ExerciseInfo? info;
  final String exerciseID;
  final GymController gym;
  final ValueChanged<SetField> edit;

  Future<void> _menu(BuildContext context, bool isTime) async {
    final action = await showModalBottomSheet<VoidCallback>(
      context: context,
      showDragHandle: true,
      builder: (sheet) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const ListTile(
              title: Text('Satzart', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
            for (final kind in SetKind.values)
              ListTile(
                title: Text(kind.label),
                trailing: kind == set.kind ? const Icon(Icons.check) : null,
                onTap: () => Navigator.of(sheet).pop(() => gym.setKind(kind, set: index, of: exerciseID)),
              ),
            if (set.done && !isTime) ...[
              const ListTile(
                title: Text('Wiederholungen in Reserve', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
              for (var value = 0; value < 5; value++)
                ListTile(
                  title: Text(value == 4 ? '4 oder mehr' : '$value'),
                  trailing: set.rir == value ? const Icon(Icons.check) : null,
                  onTap: () => Navigator.of(sheet).pop(() => gym.setRIR(value, set: index, of: exerciseID)),
                ),
              ListTile(
                title: const Text('Keine Angabe'),
                onTap: () => Navigator.of(sheet).pop(() => gym.setRIR(null, set: index, of: exerciseID)),
              ),
            ],
          ],
        ),
      ),
    );
    action?.call();
  }

  @override
  Widget build(BuildContext context) {
    final isTime = info?.tracking == ExerciseTracking.time;
    final weight = ExerciseUnits.weightText(set.weightKg, info: info);
    final theme = Theme.of(context);
    const big = TextStyle(fontSize: 20, fontWeight: FontWeight.bold, fontFeatures: [FontFeature.tabularFigures()]);
    return InkWell(
      onLongPress: () => _menu(context, isTime),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          spacing: 12,
          children: [
            SizedBox(
              width: 22,
              child: Semantics(
                label: set.kind == SetKind.working ? 'Satz ${index + 1}' : set.kind.label,
                excludeSemantics: true,
                child: Text(
                  set.kind.badge ?? '${index + 1}',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: set.kind == SetKind.working ? theme.colorScheme.onSurfaceVariant : Colors.orange,
                  ),
                ),
              ),
            ),
            Expanded(
              child: InkWell(
                onTap: () => edit(SetField.weight),
                child: Container(
                  constraints: const BoxConstraints(minHeight: 44),
                  alignment: Alignment.centerLeft,
                  // In der Liste kurz: „je Hantel“ steht auf der Fokus-Karte.
                  child: Text(
                    set.weightKg == 0 ? 'Körpergew.' : '${weight.value} ${weight.unit.replaceAll(' je Hantel', '')}',
                    style: big,
                  ),
                ),
              ),
            ),
            InkWell(
              onTap: () => edit(SetField.reps),
              child: Container(
                constraints: const BoxConstraints(minHeight: 44, minWidth: 64),
                alignment: Alignment.centerLeft,
                child: Text(isTime ? '${set.reps} s' : '× ${set.reps}', style: big),
              ),
            ),
            if (set.done && set.rir != null)
              Text(
                'RIR ${set.rir == 4 ? '4+' : set.rir}',
                style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurfaceVariant),
              ),
            IconButton(
              iconSize: 32,
              tooltip: set.done ? 'Satz erledigt, tippen für wieder offen' : 'Satz abhaken',
              icon: Icon(
                set.done ? Icons.check_circle : Icons.radio_button_unchecked,
                color: set.done ? Colors.green : theme.colorScheme.onSurfaceVariant,
              ),
              onPressed: () => gym.toggleDone(set: index, of: exerciseID),
            ),
          ],
        ),
      ),
    );
  }
}
