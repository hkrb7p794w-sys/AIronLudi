import 'dart:async';

import 'package:coach_core/coach_core.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../data/repositories/gym_repository.dart';
import '../../data/storage.dart';
import '../../services/garmin/garmin_connect_session.dart';
import '../../services/providers.dart';
import '../../ui/components.dart';
import '../evidence/evidence_views.dart';
import 'active_workout_screen.dart';
import 'gym_controller.dart';
import 'gym_providers.dart';
import 'muscle_views.dart';

String _day(CalendarDay day) => DateFormat('EEE, d.M.', 'de_DE').format(day.referenceDate);

String _duration(Duration duration) {
  final minutes = duration.inMinutes;
  return minutes >= 60 ? '${minutes ~/ 60} h ${minutes % 60} min' : '$minutes min';
}

/// Gym (Bereich im Reiter Training): Einheit von heute starten, Planen und Auswerten, letzte Einheiten
/// (Port von `GymView.swift`).
class GymScreen extends ConsumerStatefulWidget {
  const GymScreen({super.key});

  @override
  ConsumerState<GymScreen> createState() => _GymScreenState();
}

class _GymScreenState extends ConsumerState<GymScreen> {
  List<StoredGymSession> _records = const [];

  @override
  void initState() {
    super.initState();
    unawaited(_reload(loadHints: true));
  }

  /// Daten laden und den Controller aktualisieren; einmal je Öffnen KI-Hinweise (automatisch, wenn erlaubt).
  Future<void> _reload({bool loadHints = false}) async {
    final today = CalendarDay.today();
    final results = await (
      ref.read(gymRepositoryProvider).all(),
      ref.read(activityRepositoryProvider).all(),
      ref.read(metricsRepositoryProvider).range(from: today.adding(-120), to: today),
    ).wait;
    if (!mounted) return;
    final records = [...results.$1]..sort((a, b) => b.session.start.compareTo(a.session.start));
    final days = [...results.$3]..sort((a, b) => b.day.compareTo(a.day));
    setState(() => _records = records);
    final gym = ref.read(gymControllerProvider);
    final settings = ref.read(coachSettingsProvider);
    gym.update(
      sessions: [for (final record in records) record.session],
      activities: results.$2,
      days: days.take(3).toList(),
      gym: settings.gym,
    );
    if (loadHints && !gym.hintSource.startsWith('KI')) {
      unawaited(
        gym.loadHints(ref.read(aiClientProvider), goal: settings.coachingProfile.goal, trigger: AITrigger.automatic),
      );
    }
  }

  Future<void> _open() async {
    await Navigator.of(context)
        .push(MaterialPageRoute<void>(fullscreenDialog: true, builder: (_) => const ActiveWorkoutScreen()));
    if (mounted) await _reload();
  }

  Future<void> _push(Widget Function(BuildContext context) builder) async {
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: builder));
    if (mounted) await _reload();
  }

  @override
  Widget build(BuildContext context) {
    final gym = ref.watch(gymControllerProvider);
    final settings = ref.watch(coachSettingsProvider);
    final active = gym.active;
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Gym')),
      body: RefreshIndicator(
        onRefresh: _reload,
        child: ListView(
          padding: const EdgeInsets.only(bottom: 32),
          children: [
            if (active != null)
              FormSection(
                footer: switch (gym.sessionState()) {
                  ActiveSessionState.unfinished =>
                    'Diese Einheit vom ${DateFormat('d. MMM', 'de_DE').format(active.day.referenceDate)} wurde nicht '
                        'beendet. Öffnen und „Beenden“ tippen, damit sie gespeichert, für die Woche gezählt und an '
                        'Garmin übertragen wird.',
                  ActiveSessionState.notStarted =>
                    'Noch kein Satz abgehakt – erst mit dem ersten Satz gilt die Einheit als gestartet.',
                  _ => null,
                },
                children: [
                  ListTile(
                    leading: Icon(Icons.play_circle_fill, color: theme.colorScheme.primary),
                    title: Text(
                      '${active.title} fortsetzen · ${active.doneSetCount} Sätze',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    onTap: _open,
                  ),
                ],
              )
            else if (settings.profile.mode == ProfileMode.personal)
              _PersonalGymSection(
                gym: gym,
                start: (routine) {
                  routine == null ? gym.startEmpty() : gym.startRoutine(routine);
                  unawaited(_open());
                },
              )
            else
              _TodaySection(
                gym: gym,
                start: (workout) {
                  workout == null ? gym.startEmpty() : gym.startWorkout(workout);
                  unawaited(_open());
                },
              ),
            if (gym.message case final message?)
              FormSection(
                children: [ListTile(title: Text(message, style: theme.textTheme.bodySmall))],
              ),
            FormSection(
              header: 'Planen und auswerten',
              children: [
                _HubTile(
                  title: 'Auswertung',
                  icon: Icons.fitness_center,
                  caption: 'Muskel-Heatmap, Erholung, Fortschritt',
                  onTap: () => _push((_) => const GymAnalysisScreen()),
                ),
              ],
            ),
            if (_records.isNotEmpty)
              FormSection(
                header: 'Letzte Einheiten',
                children: [
                  for (final record in _records.take(3))
                    SessionRow(
                      record: record,
                      onTap: () => _push((_) => SessionDetailScreen(record: record)),
                    ),
                  if (_records.length > 3)
                    ListTile(
                      title: Text('Alle ${_records.length} Einheiten'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => _push((_) => const GymHistoryScreen()),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

/// Krafttraining für Profile ohne Saisonplan: Karte „Nächste Einheit“ (Rotation der eigenen Routinen) mit großem
/// Start-Knopf, darunter die übrigen Routinen als Leiste.
class _PersonalGymSection extends ConsumerWidget {
  const _PersonalGymSection({required this.gym, required this.start});

  final GymController gym;
  final void Function(Routine? routine) start;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(coachSettingsProvider);
    final day = CalendarDay.today();
    final today = [
      for (final slot in settings.schedule(day).slots(Weekday.of(day)))
        if (slot.sport == TrainingSport.strength) slot,
    ];
    final routines = settings.gym.routines;
    final next = RoutineRotation.next(routines: routines, sessions: gym.sessions);
    final theme = Theme.of(context);
    final secondary = TextStyle(color: theme.colorScheme.onSurfaceVariant);
    final legs = gym.daysSinceLegs;
    return FormSection(
      footer: routines.isEmpty
          ? 'Lege unter „Trainingspläne“ deine Einheiten an oder übernimm einen Vorschlag passend zu deinem Plan.'
          : 'Die nächste Einheit folgt der Reihenfolge deiner Trainingspläne nach dem zuletzt trainierten.',
      children: [
        if (next != null)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 6,
              children: [
                Text(today.isEmpty ? 'Nächste Einheit' : 'Heute laut Wochenplan', style: theme.textTheme.labelMedium),
                Text(next.name, style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
                Text(
                  '${next.items.length} Übungen · ca. ${RoutineRotation.estimatedMinutes(next)} min',
                  style: secondary,
                ),
                Text(next.items.map((item) => item.name).join(' · '), style: secondary.copyWith(fontSize: 13)),
                if (legs != null && legs >= 7 && !next.setsPerGroup.containsKey(MuscleGroup.legs))
                  _Warning('Beine seit $legs Tagen nicht trainiert'),
                if (gym.recovered == false)
                  const _Warning('Erholung heute eingeschränkt: Gewichte halten, ggf. weniger Sätze.'),
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(50),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    onPressed: () => start(next),
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('Starten', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          )
        else if (today.firstOrNull case final slot?)
          ListTile(
            title: Text(slot.title, style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text(slot.guide),
          ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
          child: Row(
            spacing: 8,
            children: [
              for (final routine in routines.where((routine) => routine.id != next?.id))
                OutlinedButton.icon(
                  onPressed: () => start(routine),
                  icon: const Icon(Icons.play_circle_outline),
                  label: Text(routine.name),
                ),
              OutlinedButton.icon(
                onPressed: () => start(null),
                icon: const Icon(Icons.add),
                label: const Text('Freies Training'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Warning extends StatelessWidget {
  const _Warning(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Icon(Icons.warning_amber, size: 16, color: Colors.orange),
      const SizedBox(width: 6),
      Expanded(
        child: Text(text, style: const TextStyle(fontSize: 13, color: Colors.orange)),
      ),
    ],
  );
}

/// Saisonplan: Einheit laut Plan für heute, andere Einheit oder freies Training.
class _TodaySection extends StatelessWidget {
  const _TodaySection({required this.gym, required this.start});

  final GymController gym;
  final void Function(Workout? workout) start;

  @override
  Widget build(BuildContext context) {
    final workout = gym.todayWorkout;
    final theme = Theme.of(context);
    final week = [for (final item in gym.weekPlan) '${_day(item.day)}: ${item.workout.name}${item.done ? ' ✓' : ''}'];
    return FormSection(
      header: 'Heute',
      footer: week.isEmpty ? null : 'Diese Woche: ${week.join(' · ')}',
      children: [
        if (workout != null) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 4,
              children: [
                Text(workout.name, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
                Text(
                  workout.exercises.map((exercise) => exercise.name).join(' · '),
                  style: TextStyle(fontSize: 13, color: theme.colorScheme.onSurfaceVariant),
                ),
                if (gym.recovered == false)
                  const _Warning('Erholung heute eingeschränkt: Gewichte halten, ggf. ⅓ weniger Sätze.'),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(50),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              onPressed: () => start(workout),
              icon: const Icon(Icons.play_arrow),
              label: const Text('Einheit starten', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ),
        ] else
          ListTile(
            title: Text(
              'Heute steht laut Plan kein Krafttraining an.',
              style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
        PopupMenuButton<Workout?>(
          onSelected: start,
          itemBuilder: (_) => [
            for (final workout in gym.plan.workouts) PopupMenuItem(value: workout, child: Text(workout.name)),
            const PopupMenuItem(child: Text('Freies Training')),
          ],
          child: ListTile(
            title: Text('Andere Einheit starten', style: TextStyle(color: theme.colorScheme.primary)),
            trailing: const Icon(Icons.expand_more),
          ),
        ),
      ],
    );
  }
}

/// Zeile mit Symbol, Titel und kurzer Beschreibung.
class _HubTile extends StatelessWidget {
  const _HubTile({required this.title, required this.icon, required this.caption, required this.onTap});

  final String title;
  final IconData icon;
  final String caption;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ListTile(
    leading: Icon(icon, color: Theme.of(context).colorScheme.primary),
    title: Text(title, style: const TextStyle(fontWeight: FontWeight.w500)),
    subtitle: Text(caption),
    trailing: const Icon(Icons.chevron_right),
    onTap: onTap,
  );
}

class SessionRow extends StatelessWidget {
  const SessionRow({super.key, required this.record, required this.onTap});

  final StoredGymSession record;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final session = record.session;
    return ListTile(
      title: Text(session.title, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(
        '${_day(session.day)} · ${session.doneSetCount} Sätze · '
        '${GermanFormat.number((session.volumeKg / 100).roundToDouble() / 10)} t',
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (record.savedToHealth)
            const Icon(Icons.favorite, size: 14, color: Colors.pink, semanticLabel: 'In Health'),
          const Icon(Icons.chevron_right),
        ],
      ),
      onTap: onTap,
    );
  }
}

/// Eine gespeicherte Einheit: Daten, Health, Garmin-Abgleich und die Sätze.
class SessionDetailScreen extends ConsumerStatefulWidget {
  const SessionDetailScreen({super.key, required this.record});

  final StoredGymSession record;

  @override
  ConsumerState<SessionDetailScreen> createState() => _SessionDetailScreenState();
}

class _SessionDetailScreenState extends ConsumerState<SessionDetailScreen> {
  late StoredGymSession _record = widget.record;
  String? _message;
  bool _working = false;

  GymRepository get _repository => ref.read(gymRepositoryProvider);

  /// Nach einer Aktion den gespeicherten Datensatz neu lesen, damit der Status sofort stimmt.
  Future<void> _run(Future<String> Function() action) async {
    setState(() => _working = true);
    final text = await action();
    final fresh = await _repository.byID(_record.session.id);
    if (!mounted) return;
    setState(() {
      _working = false;
      _message = text;
      if (fresh != null) _record = fresh;
    });
  }

  @override
  Widget build(BuildContext context) {
    final session = _record.session;
    final connect = ref.watch(garminConnectProvider);
    return Scaffold(
      appBar: AppBar(title: Text(session.title)),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          FormSection(
            children: [
              LabeledRow(label: 'Datum', value: _day(session.day)),
              if (session.end case final end?)
                LabeledRow(label: 'Dauer', value: _duration(end.difference(session.start))),
              LabeledRow(label: 'Bewegte Last', value: '${GermanFormat.number(session.volumeKg)} kg'),
              if (_record.savedToHealth)
                const ListTile(
                  leading: Icon(Icons.favorite, color: Colors.pink),
                  title: Text('In Apple Health gespeichert', style: TextStyle(color: Colors.pink)),
                )
              else
                ListTile(
                  title: const Text('In Apple Health speichern'),
                  enabled: !_working,
                  onTap: () => _run(
                    () => GymController.saveToHealth(
                      session,
                      repository: _repository,
                      writer: ref.read(workoutWriterProvider),
                    ),
                  ),
                ),
              if (_message case final message?) ListTile(title: Text(message, style: const TextStyle(fontSize: 13))),
            ],
          ),
          if (connect.isLoggedIn) _garminSection(connect),
          for (final exercise in session.exercises)
            FormSection(
              header: exercise.name,
              children: [
                for (final (index, set) in exercise.sets.indexed)
                  LabeledRow(
                    label: 'Satz ${index + 1}',
                    value: set.weightKg > 0
                        ? '${GermanFormat.number(set.weightKg)} kg × ${set.reps}'
                        : '${set.reps} Wdh.',
                  ),
              ],
            ),
        ],
      ),
    );
  }

  /// Abgleich mit Garmin: Status, Sätze in die Uhr-Aufzeichnung schreiben, als eigene Aktivität hochladen,
  /// ursprüngliche Sätze der Uhr wiederherstellen.
  Widget _garminSection(GarminConnectSession connect) {
    final session = _record.session;
    final link = session.garmin;
    final strength = ref.read(garminStrengthServiceProvider);
    final gym = ref.read(coachSettingsProvider).gym;
    final Widget status = switch (link?.status) {
      GarminLinkStatus.enriched => const ListTile(
        leading: Icon(Icons.check_circle, color: Colors.blue),
        title: Text('Sätze in der Aufzeichnung der Uhr'),
      ),
      GarminLinkStatus.uploaded => const ListTile(
        leading: Icon(Icons.check_circle, color: Colors.blue),
        title: Text('Als eigene Aktivität hochgeladen'),
      ),
      GarminLinkStatus.pending => const ListTile(
        leading: Icon(Icons.hourglass_empty),
        title: Text('Wartet auf die Aufzeichnung der Uhr'),
      ),
      GarminLinkStatus.failed => ListTile(
        leading: const Icon(Icons.warning_amber, color: Colors.orange),
        title: Text(link?.note ?? 'Abgleich fehlgeschlagen', style: const TextStyle(color: Colors.orange)),
      ),
      null when _record.uploadedToGarmin => const ListTile(
        leading: Icon(Icons.check_circle, color: Colors.blue),
        title: Text('Als eigene Aktivität hochgeladen'),
      ),
      null => const ListTile(leading: Icon(Icons.circle_outlined), title: Text('Noch nicht in Garmin Connect')),
    };
    return FormSection(
      header: 'Garmin Connect',
      footer:
          'Abgleichen schreibt die Sätze in die Krafttraining-Aufzeichnung der Uhr (Start höchstens 2 Stunden '
          'entfernt) – Kalorien und Puls der Uhr bleiben, es entsteht keine zweite Aktivität. Hochladen legt eine '
          'eigene Aktivität an; nur, wenn die Uhr nicht dabei war.',
      children: [
        status,
        if (_working) const LinearProgressIndicator(),
        ...switch (link?.status) {
          GarminLinkStatus.enriched => [
            if (link?.activityID case final id?) ...[
              // Z. B. nach besserer Übungszuordnung: neu aus der gesicherten Uhr-Aufzeichnung schreiben.
              ListTile(
                leading: const Icon(Icons.refresh),
                title: const Text('Sätze erneut übertragen'),
                enabled: !_working,
                onTap: () => _run(
                  () => strength.enrich(session, activityID: id, garmin: connect, gym: gym, now: DateTime.now()),
                ),
              ),
              if (strength.hasBackup(id))
                ListTile(
                  title: const Text(
                    'Ursprüngliche Sätze der Uhr wiederherstellen',
                    style: TextStyle(color: Colors.red),
                  ),
                  enabled: !_working,
                  onTap: () => _run(() => strength.restore(session, activityID: id, garmin: connect)),
                ),
            ],
          ],
          GarminLinkStatus.uploaded => const <Widget>[],
          _ when _record.uploadedToGarmin => const <Widget>[],
          _ => [
            ListTile(
              leading: const Icon(Icons.sync),
              title: const Text('Mit Aufzeichnung der Uhr abgleichen'),
              enabled: !_working,
              onTap: () => _run(() async {
                await _repository.setGarmin(
                  session.id,
                  GarminLink(status: GarminLinkStatus.pending, updatedAt: DateTime.now()),
                );
                return await strength.reconcile(garmin: connect, gym: gym) ?? 'Nichts zu tun.';
              }),
            ),
            ListTile(
              leading: const Icon(Icons.upload),
              title: const Text('Als eigene Aktivität hochladen'),
              enabled: !_working,
              onTap: () => _run(() async {
                final text = await GymController.uploadToGarmin(session, repository: _repository, garmin: connect);
                if ((await _repository.byID(session.id))?.uploadedToGarmin ?? false) {
                  await _repository.setGarmin(
                    session.id,
                    GarminLink(status: GarminLinkStatus.uploaded, note: text, updatedAt: DateTime.now()),
                  );
                }
                return text;
              }),
            ),
          ],
        },
      ],
    );
  }
}

/// Alle Einheiten; Löschen erst nach Rückfrage – eine Einheit ist Verlauf und Grundlage der Progression.
class GymHistoryScreen extends ConsumerStatefulWidget {
  const GymHistoryScreen({super.key});

  @override
  ConsumerState<GymHistoryScreen> createState() => _GymHistoryScreenState();
}

class _GymHistoryScreenState extends ConsumerState<GymHistoryScreen> {
  List<StoredGymSession> _records = const [];

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final records = await ref.read(gymRepositoryProvider).all();
    if (!mounted) return;
    setState(() => _records = [...records]..sort((a, b) => b.session.start.compareTo(a.session.start)));
  }

  Future<bool> _confirmDelete() async =>
      await showDialog<bool>(
        context: context,
        builder: (dialog) => AlertDialog(
          title: const Text('Einheit löschen?'),
          content: const Text('Sätze, Bestleistungen und die Progression dieser Einheit gehen verloren.'),
          actions: [
            TextButton(onPressed: () => Navigator.of(dialog).pop(false), child: const Text('Abbrechen')),
            TextButton(
              onPressed: () => Navigator.of(dialog).pop(true),
              child: const Text('Löschen', style: TextStyle(color: Colors.red)),
            ),
          ],
        ),
      ) ??
      false;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Verlauf')),
    body: ListView(
      children: [
        for (final record in _records)
          Dismissible(
            key: ValueKey(record.session.id),
            direction: DismissDirection.endToStart,
            background: Container(
              color: Colors.red,
              alignment: Alignment.centerRight,
              padding: const EdgeInsets.only(right: 16),
              child: const Icon(Icons.delete, color: Colors.white),
            ),
            confirmDismiss: (_) => _confirmDelete(),
            onDismissed: (_) async {
              setState(() => _records = [..._records]..remove(record));
              await ref.read(gymRepositoryProvider).delete(record.session.id);
            },
            child: SessionRow(
              record: record,
              onTap: () async {
                await Navigator.of(context)
                    .push(MaterialPageRoute<void>(builder: (_) => SessionDetailScreen(record: record)));
                await _load();
              },
            ),
          ),
      ],
    ),
  );
}

/// Auswertung: Kalender, Hinweise, Muskeln, Fortschritt je Übung, Sätze je Muskel.
class GymAnalysisScreen extends ConsumerWidget {
  const GymAnalysisScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gym = ref.watch(gymControllerProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Auswertung')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          _CalendarSection(gym: gym),
          GymHintsSection(gym: gym),
          MuscleOverviewSection(sessions: gym.sessions),
          _ProgressSection(gym: gym),
          _VolumeSection(gym: gym),
        ],
      ),
    );
  }
}

/// Einheiten je Woche (8 Wochen) und Serie.
class _CalendarSection extends StatelessWidget {
  const _CalendarSection({required this.gym});

  final GymController gym;

  @override
  Widget build(BuildContext context) {
    final weeks = GymCalendar.weeks(sessions: gym.sessions, today: gym.today);
    final streak = GymCalendar.streak(sessions: gym.sessions, today: gym.today);
    final color = Theme.of(context).colorScheme.primary;
    final maxY = weeks.fold<int>(1, (top, week) => week.sessions > top ? week.sessions : top).toDouble();
    return FormSection(
      header: 'Kalender',
      children: [
        Semantics(
          label: 'Einheiten je Woche, letzte 8 Wochen',
          excludeSemantics: true,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 16, 16, 8),
            child: SizedBox(
              height: 140,
              child: BarChart(
                BarChartData(
                  maxY: maxY,
                  barGroups: [
                    for (final (index, week) in weeks.indexed)
                      BarChartGroupData(
                        x: index,
                        barRods: [
                          BarChartRodData(
                            toY: week.sessions.toDouble(),
                            width: 16,
                            color: color,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ],
                      ),
                  ],
                  titlesData: FlTitlesData(
                    topTitles: const AxisTitles(),
                    rightTitles: const AxisTitles(),
                    leftTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: true, reservedSize: 24, interval: 1),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (value, meta) => SideTitleWidget(
                          meta: meta,
                          child: Text(
                            DateFormat('d.M.', 'de_DE').format(weeks[value.toInt()].monday.referenceDate),
                            style: const TextStyle(fontSize: 10),
                          ),
                        ),
                      ),
                    ),
                  ),
                  gridData: const FlGridData(drawVerticalLine: false, horizontalInterval: 1),
                  borderData: FlBorderData(show: false),
                ),
              ),
            ),
          ),
        ),
        ListTile(
          leading: Icon(
            streak > 0 ? Icons.local_fire_department : Icons.local_fire_department_outlined,
            color: streak > 0 ? Colors.orange : null,
          ),
          title: Text(streak == 1 ? '1 Woche in Folge trainiert' : '$streak Wochen in Folge trainiert'),
        ),
      ],
    );
  }
}

/// Tipps für die nächste Einheit: KI-Hinweise oder Regeln.
class GymHintsSection extends ConsumerWidget {
  const GymHintsSection({super.key, required this.gym});

  final GymController gym;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (gym.progress.isEmpty) return const SizedBox.shrink();
    final ai = ref.watch(aiClientProvider);
    return FormSection(
      header: 'Tipps für die nächste Einheit',
      footer: 'Quelle: ${gym.hintSource}. Die Gewichte bestimmen die Regeln; die KI formuliert nur.',
      children: [
        if (ai.allows('gym_hints'))
          Align(
            alignment: Alignment.centerRight,
            child: IconButton(
              tooltip: 'Neue Tipps',
              icon: const Icon(Icons.auto_awesome),
              onPressed: gym.isLoadingHints
                  ? null
                  : () => gym.loadHints(ai, goal: ref.read(coachSettingsProvider).coachingProfile.goal),
            ),
          ),
        for (final hint in gym.hints) ListTile(dense: true, leading: const Icon(Icons.north_east), title: Text(hint)),
        if (gym.isLoadingHints) const LinearProgressIndicator(),
        EvidenceDisclosure(ruleIDs: gym.hintEvidence),
      ],
    );
  }
}

class _ProgressSection extends StatefulWidget {
  const _ProgressSection({required this.gym});

  final GymController gym;

  @override
  State<_ProgressSection> createState() => _ProgressSectionState();
}

class _ProgressSectionState extends State<_ProgressSection> {
  static const _urgent = {ProgressStatus.increase, ProgressStatus.restart, ProgressStatus.check};

  @override
  Widget build(BuildContext context) {
    final progress = widget.gym.progress;
    final active = progress.where((item) => _urgent.contains(item.status)).toList();
    final rest = progress.where((item) => !_urgent.contains(item.status)).toList();
    final secondary = TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 13);
    return FormSection(
      header: 'Gewichts-Progression',
      footer:
          'Regel: alle Arbeitssätze an der Obergrenze → +2,5–5 % und wieder unten im Bereich anfangen (ACSM 2009). '
          'Bleiben in allen Sätzen 4 oder mehr Wiederholungen in Reserve, sofort steigern. Die Tagesampel verschiebt '
          'nur den Zeitpunkt.',
      children: [
        if (progress.isEmpty)
          ListTile(title: Text('Noch keine Einheiten mit Gewicht im Verlauf.', style: secondary))
        else if (active.isEmpty)
          ListTile(
            title: Text(
              'Gerade keine Übung an der Obergrenze – Gewichte halten, Wiederholungen steigern.',
              style: secondary,
            ),
          ),
        for (final item in active) _ProgressRow(item: item),
        if (rest.isNotEmpty)
          ExpansionTile(
            title: Text('${rest.length} weitere Übungen'),
            children: [for (final item in rest) _ProgressRow(item: item)],
          ),
        const EvidenceDisclosure(ruleIDs: ['gym.progression', 'gym.rir']),
      ],
    );
  }
}

class _ProgressRow extends StatelessWidget {
  const _ProgressRow({required this.item});

  final ExerciseProgress item;

  @override
  Widget build(BuildContext context) {
    final tag = switch (item.status) {
      ProgressStatus.increase => (
        item.nextWeightKg == null ? '↑' : '↑ ${GermanFormat.number(item.nextWeightKg!)} kg',
        Colors.green,
      ),
      ProgressStatus.check => ('prüfen', Colors.red),
      ProgressStatus.restart => ('Wiedereinstieg', Colors.orange),
      _ => null,
    };
    return ListTile(
      title: Text(item.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
      subtitle: Text(
        '${item.weightKg > 0 ? '${GermanFormat.number(item.weightKg)} kg' : 'Körpergewicht'} × '
        '${item.reps.join('/')} · Ziel ${item.target.lower}–${item.target.upper}',
      ),
      trailing: tag == null
          ? null
          : Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(color: tag.$2.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(12)),
              child: Text(tag.$1, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
            ),
    );
  }
}

class _VolumeSection extends StatelessWidget {
  const _VolumeSection({required this.gym});

  final GymController gym;

  @override
  Widget build(BuildContext context) => FormSection(
    header: 'Sätze je Muskel · 7 Tage',
    footer:
        'Grün ab 5 Sätzen pro Woche: solider Kraftaufbau neben dem Ausdauertraining. Mehr Sätze bringen mehr, aber mit '
        'abnehmendem Ertrag (Schoenfeld 2017, Pelland 2025). Für Lauf- und Radökonomie zählt Beintraining am meisten.',
    children: [
      if ((gym.daysSinceLegs ?? 99) > 10)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: _Warning(
            gym.daysSinceLegs == null ? 'Beine bisher nicht erfasst.' : 'Beine zuletzt vor ${gym.daysSinceLegs} Tagen.',
          ),
        ),
      for (final group in MuscleVolume.groups)
        () {
          final count = gym.volume[group] ?? 0;
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Row(
              children: [
                SizedBox(width: 90, child: Text(group.rawValue)),
                Expanded(
                  child: LinearProgressIndicator(
                    value: (count > 14 ? 14 : count) / 14,
                    color: count == 0 ? Colors.red : (count >= MuscleVolume.goodLower ? Colors.green : Colors.orange),
                  ),
                ),
                SizedBox(
                  width: 28,
                  child: Text(
                    '$count',
                    textAlign: TextAlign.right,
                    style: const TextStyle(fontFeatures: [FontFeature.tabularFigures()]),
                  ),
                ),
              ],
            ),
          );
        }(),
      const EvidenceDisclosure(ruleIDs: ['gym.volume', 'strength.economy', 'strength.interference']),
    ],
  );
}
