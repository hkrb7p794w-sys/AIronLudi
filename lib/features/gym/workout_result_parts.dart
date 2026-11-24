part of 'workout_parts.dart';

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
            Text(label, style: AppText.caption(context).copyWith(color: theme.colorScheme.onSurfaceVariant)),
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
                style: AppText.footnote(context).copyWith(color: theme.colorScheme.onSurfaceVariant),
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
    final secondary = AppText.caption(context).copyWith(color: theme.colorScheme.onSurfaceVariant);
    final heading = theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold);
    final muscles = finished.muscles.entries.where((entry) => entry.value > 0).toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final next = [
      for (final id in finished.exerciseIDs) ?gym.progress.where((item) => item.exerciseID == id).firstOrNull,
    ];
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Icon(Icons.verified, size: 48, color: AppColors.of(context).good),
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
        if (finished.share case final share?) ...[
          const SizedBox(height: 12),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(44),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                fullscreenDialog: true,
                builder: (_) => ShareWithFriendsScreen(content: ShareWorkout(share), localKeys: finished.shareKeys),
              ),
            ),
            icon: const Icon(Icons.people_outline),
            label: const Text('Mit Freunden teilen'),
          ),
        ],
        if (finished.shareText case final text?) ...[
          const SizedBox(height: 8),
          Builder(
            builder: (context) => OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(44),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              onPressed: () => unawaited(shareGymText(context, text, subject: finished.title)),
              icon: const Icon(Icons.ios_share),
              label: const Text('Teilen …'),
            ),
          ),
        ],
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
    final style = AppText.caption(context).copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant);
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
