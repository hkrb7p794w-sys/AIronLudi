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
import '../../ui/liquid.dart';
import '../../ui/tokens.dart';
import 'exercise_picker.dart';
import 'gym_controller.dart';
import 'gym_providers.dart';
import 'workout_parts.dart';

part 'active_workout_focus.dart';
part 'active_workout_controls.dart';

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
            child: Text('Verwerfen', style: TextStyle(color: AppColors.of(context).alert)),
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
              itemBuilder: (_) => [
                PopupMenuItem(value: 'add', child: Text('Übung hinzufügen')),
                PopupMenuItem(
                  value: 'cancel',
                  child: Text('Einheit verwerfen', style: TextStyle(color: AppColors.of(context).alert)),
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
