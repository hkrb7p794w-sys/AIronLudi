import 'dart:async';

import 'package:coach_core/coach_core.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../app/day_change.dart';
import '../../data/repositories/gym_repository.dart';
import '../../data/storage.dart';
import '../../services/garmin/garmin_connect_session.dart';
import '../../services/providers.dart';
import '../../ui/components.dart';
import '../../ui/liquid.dart';
import '../../ui/platform_names.dart';
import '../../ui/tokens.dart';
import 'active_workout_screen.dart';
import 'gym_controller.dart';
import 'gym_library.dart';
import 'gym_providers.dart';
import 'gym_share_views.dart';
import 'muscle_views.dart';

part 'gym_history_screens.dart';

String _day(CalendarDay day) => DateFormat('EEE, d.M.', 'de_DE').format(day.referenceDate);

String _duration(Duration duration) {
  final minutes = duration.inMinutes;
  return minutes >= 60 ? '${minutes ~/ 60} h ${minutes % 60} min' : '$minutes min';
}

/// Gym (Bereich im Reiter Training): Einheit von heute starten, Planen und Auswerten, letzte Einheiten
/// (Port von `GymView.swift`).
class GymScreen extends ConsumerStatefulWidget {
  const GymScreen({super.key, this.startWorkout = false});

  /// Von „Training starten“ (Schnellaktion, Widget, Link): laufende Einheit öffnen, sonst die heutige des Plans starten;
  /// ohne Plan für heute bleibt die Auswahl hier.
  final bool startWorkout;

  @override
  ConsumerState<GymScreen> createState() => _GymScreenState();
}

class _GymScreenState extends ConsumerState<GymScreen> {
  List<StoredGymSession> _records = const [];

  @override
  void initState() {
    super.initState();
    unawaited(
      _reload(loadHints: true).then((_) {
        if (!mounted || !widget.startWorkout) return;
        final gym = ref.read(gymControllerProvider);
        if (gym.active == null) {
          final workout = gym.todayWorkout;
          if (workout == null) return;
          gym.startWorkout(workout);
        }
        unawaited(_open());
      }),
    );
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
    // Neuer Kalendertag (Mitternacht, Rückkehr in die App): neu laden wie `onDayChange`.
    ref.listen(currentDayProvider, (_, _) => unawaited(_reload()));
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
                        'deine Datenquellen übertragen wird.',
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
                  title: 'Trainingspläne',
                  icon: Icons.view_list_outlined,
                  caption: settings.gym.routines.isEmpty
                      ? 'Plan anlegen oder Vorlage übernehmen'
                      : '${settings.gym.routines.length} Pläne · bearbeiten, neu anlegen',
                  onTap: () => _push(
                    (context) => RoutinesScreen(
                      gym: gym,
                      start: (routine) {
                        gym.startRoutine(routine);
                        Navigator.of(context).pop();
                        unawaited(_open());
                      },
                    ),
                  ),
                ),
                _HubTile(
                  title: 'Übungen',
                  icon: Icons.menu_book_outlined,
                  caption: 'Suchen, nach Muskel filtern, Anleitung',
                  onTap: () => _push((_) => ExerciseLibraryScreen(gym: gym)),
                ),
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
                      trailing: const DisclosureChevron(),
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
                Text(
                  next.items.map((item) => item.name).join(' · '),
                  style: AppText.footnote(context).copyWith(color: secondary.color),
                ),
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
      Icon(Icons.warning_amber, size: 16, color: AppColors.of(context).caution),
      const SizedBox(width: 6),
      Expanded(
        child: Text(text, style: AppText.footnote(context).copyWith(color: AppColors.of(context).caution)),
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
                  style: AppText.footnote(context).copyWith(color: theme.colorScheme.onSurfaceVariant),
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
        // Freies Training als eigener Wert: ein Eintrag ohne Wert (`null`) würde nie ausgewählt.
        PopupMenuButton<(Workout?,)>(
          onSelected: (choice) => start(choice.$1),
          itemBuilder: (_) => [
            for (final workout in gym.plan.workouts) PopupMenuItem(value: (workout,), child: Text(workout.name)),
            const PopupMenuItem(value: (null,), child: Text('Freies Training')),
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
    trailing: const DisclosureChevron(),
    onTap: onTap,
  );
}
