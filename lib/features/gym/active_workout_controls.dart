part of 'active_workout_screen.dart';

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
                color: elapsed >= target ? AppColors.of(context).good : Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(60),
              shape: shape,
              backgroundColor: AppColors.of(context).alert,
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
              backgroundColor: AppColors.of(context).good,
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
                Text('Pause', style: AppText.body(context).copyWith(fontWeight: FontWeight.w600)),
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
            LiquidProgressBar(value: (remaining / total).clamp(0, 1)),
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
          style: AppText.footnote(context).copyWith(color: theme.colorScheme.onSurfaceVariant),
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
                      background: Container(color: AppColors.of(context).alert),
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
                          Text(hint, style: AppText.caption(context).copyWith(color: AppColors.of(context).caution)),
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
                    color: set.kind == SetKind.working
                        ? theme.colorScheme.onSurfaceVariant
                        : AppColors.of(context).caution,
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
                style: AppText.caption(context).copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            IconButton(
              iconSize: 32,
              tooltip: set.done ? 'Satz erledigt, tippen für wieder offen' : 'Satz abhaken',
              icon: Icon(
                set.done ? Icons.check_circle : Icons.radio_button_unchecked,
                color: set.done ? AppColors.of(context).good : theme.colorScheme.onSurfaceVariant,
              ),
              onPressed: () => gym.toggleDone(set: index, of: exerciseID),
            ),
          ],
        ),
      ),
    );
  }
}
