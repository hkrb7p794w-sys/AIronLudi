part of 'active_workout_screen.dart';

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
            _exerciseDone(context, session.exercises[target.exercise]),
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
                  style: AppText.footnote(context).copyWith(color: theme.colorScheme.onSurfaceVariant),
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
              style: AppText.footnote(context).copyWith(color: secondary, fontFeatures: [FontFeature.tabularFigures()]),
            ),
            const Spacer(),
            ExerciseMenu(exercise: exercise, gym: gym),
          ],
        ),
        if (label != null)
          Text(
            'Supersatz $label',
            style: AppText.caption(context).copyWith(fontWeight: FontWeight.bold, color: theme.colorScheme.primary),
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
            style: AppText.caption(context).copyWith(fontWeight: FontWeight.bold, color: secondary),
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

  Widget _exerciseDone(BuildContext context, LoggedExercise exercise) => Column(
    spacing: 12,
    children: [
      Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.check_circle, color: AppPalette.green),
          const SizedBox(width: 6),
          Text(
            'Alle Sätze erledigt',
            style: AppText.title(context).copyWith(fontWeight: FontWeight.bold, color: AppPalette.green),
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
          const Icon(Icons.emoji_events, size: 48, color: AppPalette.amber),
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
              Text('Satz ${index + 1} von $total', style: AppText.headline(context).copyWith(color: secondary)),
              if (set.kind != SetKind.working)
                Text(
                  set.kind.label,
                  style: TextStyle(fontWeight: FontWeight.w600, color: AppColors.of(context).caution),
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
    final secondary = AppText.caption(context).copyWith(color: theme.colorScheme.onSurfaceVariant);
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
                Text(
                  'Danach',
                  style: AppText.caption(context).copyWith(color: secondary.color, fontWeight: FontWeight.bold),
                ),
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
        label: Text('Einheit beenden', style: AppText.headline(context).copyWith(fontWeight: FontWeight.bold)),
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
        backgroundColor: AppColors.of(context).good,
      ),
      onPressed: () => gym.complete(set: set, of: exercise.id),
      icon: const Icon(Icons.check),
      label: Text('Satz erledigt', style: AppText.headline(context).copyWith(fontWeight: FontWeight.bold)),
    );
  }
}
