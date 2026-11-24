import 'dart:async';

import 'package:coach_core/coach_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../services/providers.dart';
import '../../ui/components.dart';
import '../../ui/tokens.dart';
import '../evidence/evidence_views.dart';
import 'exercise_history_charts.dart';
import 'exercise_picker.dart';
import 'gym_controller.dart';
import 'gym_share_views.dart';
import 'muscle_views.dart';
import 'workout_parts.dart';

part 'gym_routines.dart';

/// Übungsbibliothek: nach Muskel sortiert, durchsuchbar, mit eigenen Übungen (Port von `ExerciseLibraryView`).
class ExerciseLibraryScreen extends ConsumerStatefulWidget {
  const ExerciseLibraryScreen({super.key, required this.gym});

  final GymController gym;

  @override
  ConsumerState<ExerciseLibraryScreen> createState() => _ExerciseLibraryScreenState();
}

class _ExerciseLibraryScreenState extends ConsumerState<ExerciseLibraryScreen> {
  final _search = TextEditingController();
  bool _onlyAvailable = true;
  MuscleGroup? _filter;

  @override
  void initState() {
    super.initState();
    _search.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(coachSettingsProvider).gym;
    final items = ExerciseLibrary.search(
      _search.text,
      custom: settings.customExercises,
      available: _onlyAvailable ? settings.equipment : null,
    );
    final shown = items.where((item) => _filter == null || item.group == _filter).toList();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Übungen'),
        actions: [
          IconButton(
            tooltip: 'Eigene Übung',
            icon: const Icon(Icons.add),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<ExerciseInfo>(
                fullscreenDialog: true,
                builder: (_) => CustomExerciseEditor(initialName: _search.text),
              ),
            ),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: TextField(
              controller: _search,
              decoration: const InputDecoration(
                hintText: 'Übung oder Muskel suchen',
                prefixIcon: Icon(Icons.search),
                isDense: true,
                border: OutlineInputBorder(),
              ),
            ),
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          MuscleGroupChips(selection: _filter, onChanged: (group) => setState(() => _filter = group)),
          FormSection(
            children: [
              SwitchListTile.adaptive(
                title: const Text('Nur mit meiner Ausstattung'),
                value: _onlyAvailable,
                onChanged: (value) => setState(() => _onlyAvailable = value),
              ),
              ListTile(
                title: const Text('Meine Ausstattung'),
                trailing: const DisclosureChevron(),
                onTap: () =>
                    Navigator.of(context)
                        .push(MaterialPageRoute<void>(builder: (_) => const EquipmentSettingsScreen())),
              ),
            ],
          ),
          if (shown.isEmpty)
            Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                _search.text.isEmpty ? 'Keine Übungen.' : 'Keine Ergebnisse für „${_search.text}“.',
                textAlign: TextAlign.center,
              ),
            ),
          for (final group in MuscleGroup.values.where((group) => _filter == null || group == _filter))
            if (items.where((item) => item.group == group).toList() case final inGroup when inGroup.isNotEmpty)
              FormSection(
                header: group.rawValue,
                children: [
                  for (final exercise in inGroup)
                    ExerciseLabel(
                      exercise: exercise,
                      trailing: const DisclosureChevron(),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => ExerciseDetailScreen(exerciseID: exercise.id, gym: widget.gym),
                        ),
                      ),
                    ),
                ],
              ),
        ],
      ),
    );
  }
}

/// Eine Übung: Empfehlung, Beschwerden, beanspruchte Muskeln, Anleitung, Bestwerte, Verlauf und Einheiten.
class ExerciseDetailScreen extends ConsumerWidget {
  const ExerciseDetailScreen({super.key, required this.exerciseID, required this.gym, this.showsDone = false});

  final String exerciseID;
  final GymController gym;

  /// Als Blatt aus der laufenden Einheit: „Fertig“ oben rechts.
  final bool showsDone;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(coachSettingsProvider);
    final gymSettings = settings.gym;
    final exercise = gymSettings.exercise(exerciseID);
    final history = gym.history(exerciseID);
    final records = GymStats.records(history);
    final progress = gym.progress.where((item) => item.exerciseID == exerciseID).firstOrNull;
    final theme = Theme.of(context);
    final secondary = AppText.footnote(context).copyWith(color: theme.colorScheme.onSurfaceVariant);
    final involvement = exercise == null
        ? const <Muscle, double>{}
        : MuscleMap.involvement(exercise.id, group: exercise.group, custom: gymSettings.customExercises);
    List<String> names(bool Function(double value) test) => [
      for (final entry in involvement.entries)
        if (test(entry.value)) entry.key.label,
    ]..sort();
    final hint = exercise == null
        ? null
        : ComplaintArea.hint(
            ComplaintArea.loaded(
              exercise.id,
              group: exercise.group,
              custom: gymSettings.customExercises,
              complaints: settings.mobility.complaints,
            ),
          );
    final light = names((value) => value < MuscleMap.primary);
    return Scaffold(
      appBar: AppBar(
        title: Text(exercise?.name ?? progress?.name ?? 'Übung'),
        automaticallyImplyLeading: !showsDone,
        actions: [if (showsDone) TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Fertig'))],
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          if (progress != null)
            FormSection(
              header: 'Nächste Einheit',
              children: [
                ListTile(
                  title: Text(progress.headline, style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text(progress.detail),
                ),
                const EvidenceDisclosure(ruleIDs: ['gym.progression', 'gym.rir']),
              ],
            ),
          if (exercise != null) ...[
            if (hint != null)
              FormSection(
                header: 'Deine Beschwerden',
                children: [
                  ListTile(
                    leading: Icon(Icons.feedback_outlined, color: AppColors.of(context).caution),
                    title: Text(hint, style: TextStyle(color: AppColors.of(context).caution)),
                  ),
                ],
              ),
            FormSection(
              header: 'Beanspruchte Muskeln',
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: BodyMap(values: involvement, full: 1),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: Text(
                    'Kräftig: ${names((value) => value >= MuscleMap.primary).join(', ')}'
                    '${light.isEmpty ? '' : ' · hell: ${light.join(', ')}'}',
                    style: secondary,
                  ),
                ),
              ],
            ),
            FormSection(
              children: [
                LabeledRow(
                  label: 'Muskel',
                  value: [exercise.group, ...exercise.secondary].map((group) => group.rawValue).join(', '),
                ),
                if (exercise.equipment.isNotEmpty)
                  LabeledRow(label: 'Geräte', value: exercise.equipment.map((item) => item.label).join(' / ')),
                LabeledRow(
                  label: exercise.tracking == ExerciseTracking.time ? 'Zielbereich' : 'Wiederholungen',
                  value:
                      '${exercise.lowerReps}–${exercise.upperReps}${exercise.tracking == ExerciseTracking.time ? ' s' : ''}',
                ),
              ],
            ),
            if (exercise.instructions.isNotEmpty)
              FormSection(
                header: 'Ausführung',
                children: [
                  for (final (index, step) in exercise.instructions.indexed)
                    ListTile(
                      leading: CircleAvatar(
                        radius: 11,
                        backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.15),
                        child: Text(
                          '${index + 1}',
                          style: AppText.caption(context).copyWith(fontWeight: FontWeight.bold),
                        ),
                      ),
                      title: Text(step),
                    ),
                ],
              ),
          ],
          if (history.isNotEmpty) ...[
            FormSection(
              header: 'Bestwerte',
              children: [
                if (records.heaviestKg case final heaviest?)
                  LabeledRow(label: 'Höchstgewicht', value: '${GermanFormat.number(heaviest)} kg'),
                if (records.bestOneRepMaxKg case final oneRepMax?)
                  LabeledRow(label: 'Geschätztes 1RM', value: '${GermanFormat.number(oneRepMax.roundToDouble())} kg'),
                if (records.mostReps case final reps?) LabeledRow(label: 'Meiste Wiederholungen', value: '$reps'),
                if (records.bestVolumeKg case final volume?)
                  LabeledRow(label: 'Beste bewegte Last', value: '${GermanFormat.number(volume.roundToDouble())} kg'),
              ],
            ),
            if (history.length > 1) ExerciseHistoryCharts(history: history),
            FormSection(
              header: 'Einheiten',
              children: [
                for (final point in history.reversed)
                  ListTile(
                    title: Text(
                      DateFormat('EEE, d.M.', 'de_DE').format(point.day.referenceDate),
                      style: AppText.callout(context).copyWith(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Text(
                      [
                        for (final set in point.sets)
                          '${set.weightKg > 0 ? '${GermanFormat.number(set.weightKg)} kg × ${set.reps}' : '${set.reps} Wdh.'}'
                              '${set.rir == null ? '' : ' (RIR ${set.rir})'}',
                      ].join(' · '),
                    ),
                  ),
              ],
            ),
          ] else
            FormSection(
              children: [ListTile(title: Text('Noch keine Sätze erfasst.', style: secondary))],
            ),
        ],
      ),
    );
  }
}

/// Vorhandene Geräte: bestimmt Vorschläge und die Auswahl in der Bibliothek; Stange und Scheiben für den Rechner.
class EquipmentSettingsScreen extends ConsumerWidget {
  const EquipmentSettingsScreen({super.key});

  static const plateOptions = <double>[25, 20, 15, 10, 5, 2.5, 2, 1.25, 1, 0.5];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(coachSettingsProvider);
    final gym = settings.gym;
    void change(void Function(GymSettings gym) update) => changeGym(settings, update);
    return Scaffold(
      appBar: AppBar(title: const Text('Ausstattung')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          FormSection(
            header: 'Schnellauswahl',
            children: [
              for (final (label, set) in [
                ('Fitnessstudio (alles)', Equipment.gym),
                ('Zuhause mit Kurzhanteln', Equipment.homeDumbbells),
                ('Ohne Geräte', Equipment.none),
              ])
                ListTile(
                  title: Text(label, style: TextStyle(color: Theme.of(context).colorScheme.primary)),
                  onTap: () => change((gym) => gym.equipment = {...set}),
                ),
            ],
          ),
          FormSection(
            header: 'Geräte',
            children: [
              for (final item in Equipment.values)
                SwitchListTile.adaptive(
                  title: Text(item.label),
                  value: gym.equipment.contains(item),
                  onChanged: (on) => change((gym) => on ? gym.equipment.add(item) : gym.equipment.remove(item)),
                ),
            ],
          ),
          FormSection(
            header: 'Stange und Scheiben',
            footer:
                'Für den Scheibenrechner und die Aufwärmsätze. Eine andere Stange je Übung (z. B. SZ-Stange) stellst '
                'du während der Einheit im Menü der Übung ein.',
            children: [
              ListTile(
                title: const Text('Langhantelstange'),
                trailing: DropdownButton<double>(
                  value: const <double>[20, 15, 10, 7.5].contains(gym.barKg) ? gym.barKg : 20,
                  underline: const SizedBox.shrink(),
                  items: [
                    for (final weight in const <double>[20, 15, 10, 7.5])
                      DropdownMenuItem(value: weight, child: Text('${GermanFormat.number(weight)} kg')),
                  ],
                  onChanged: (weight) {
                    if (weight != null) change((gym) => gym.barKg = weight);
                  },
                ),
              ),
              for (final plate in plateOptions)
                SwitchListTile.adaptive(
                  title: Text('Scheibe ${GermanFormat.number(plate)} kg'),
                  value: gym.plates.contains(plate),
                  onChanged: (on) => change((gym) {
                    gym.plates.removeWhere((other) => other == plate);
                    if (on) gym.plates = [...gym.plates, plate]..sort((a, b) => b.compareTo(a));
                  }),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Eigene Routinen und Vorschläge passend zu Profil und Ausstattung (Port von `RoutinesView`).
class RoutinesScreen extends ConsumerWidget {
  const RoutinesScreen({super.key, required this.gym, required this.start});

  final GymController gym;
  final void Function(Routine routine) start;

  static Routine duplicate(Routine routine) => Routine(
    name: '${routine.name} (Kopie)',
    items: [
      for (final item in routine.items) RoutineItem.fromJson({...item.toJson(), 'id': newUuid()})!,
    ],
  );

  Future<void> _edit(BuildContext context, WidgetRef ref, Routine routine) async {
    final saved = await Navigator.of(context)
        .push<Routine>(MaterialPageRoute(fullscreenDialog: true, builder: (_) => RoutineEditor(routine: routine)));
    if (saved == null) return;
    changeGym(ref.read(coachSettingsProvider), (gym) {
      final index = gym.routines.indexWhere((other) => other.id == saved.id);
      if (index >= 0) {
        gym.routines[index] = saved;
      } else {
        gym.routines.add(saved);
      }
    });
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(coachSettingsProvider);
    final routines = settings.gym.routines;
    final suggestions = RoutineTemplates.suggest(profile: settings.profile, equipment: settings.gym.equipment);
    final theme = Theme.of(context);
    final secondary = TextStyle(color: theme.colorScheme.onSurfaceVariant);
    return Scaffold(
      appBar: AppBar(title: const Text('Trainingspläne')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          FormSection(
            footer:
                'Ein paar Fragen zu Ziel, Tagen und Beschwerden, dann ein Plan aus deinem Verlauf und deiner '
                'Ausstattung – von den Regeln geprüft.',
            children: [
              ListTile(
                leading: const Icon(Icons.auto_awesome),
                title: const Text('KI-Trainingsplan erstellen', style: TextStyle(fontWeight: FontWeight.w600)),
                onTap: () =>
                    Navigator.of(context)
                        .push(MaterialPageRoute<void>(fullscreenDialog: true, builder: (_) => GymPlanScreen(gym: gym))),
              ),
            ],
          ),
          FormSection(
            header: 'Meine Trainingspläne',
            footer: 'Antippen startet, Stift bearbeitet, lange drücken dupliziert. Ziehen zum Sortieren.',
            children: [
              if (routines.isEmpty)
                ListTile(
                  title: Text(
                    'Noch kein eigener Trainingsplan. Übernimm einen Vorschlag oder lege selbst einen an.',
                    style: secondary,
                  ),
                ),
              ReorderableListView(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                buildDefaultDragHandles: false,
                onReorderItem: (from, to) => changeGym(settings, (gym) {
                  final routine = gym.routines.removeAt(from);
                  gym.routines.insert(to, routine);
                }),
                children: [
                  for (final (index, routine) in routines.indexed)
                    Dismissible(
                      key: ValueKey(routine.id),
                      direction: DismissDirection.endToStart,
                      background: Container(color: AppColors.of(context).alert),
                      onDismissed: (_) =>
                          changeGym(settings, (gym) => gym.routines.removeWhere((other) => other.id == routine.id)),
                      child: ListTile(
                        leading: ReorderableDragStartListener(index: index, child: const Icon(Icons.drag_handle)),
                        title: Text(routine.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: Text(
                          '${routine.items.length} Übungen · '
                          '${routine.items.fold<int>(0, (sum, item) => sum + item.sets)} Sätze',
                        ),
                        onTap: () => start(routine),
                        onLongPress: () => changeGym(settings, (gym) => gym.routines.add(duplicate(routine))),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            GymShareButton(onShare: (context) => shareRoutine(context, ref, routine)),
                            IconButton(
                              tooltip: 'Bearbeiten',
                              icon: const Icon(Icons.edit_outlined),
                              onPressed: () => _edit(context, ref, routine),
                            ),
                            IconButton(
                              tooltip: 'Starten',
                              icon: const Icon(Icons.play_arrow),
                              onPressed: () => start(routine),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
              ListTile(
                leading: const Icon(Icons.add),
                title: const Text('Neuen Trainingsplan anlegen'),
                onTap: () => _edit(context, ref, Routine(name: 'Neuer Plan', items: [])),
              ),
            ],
          ),
          FormSection(
            header:
                'Vorschläge für ${settings.profile.schedule.count(TrainingSport.strength).clamp(1, 7)} Krafttage pro Woche',
            footer:
                'Jeder große Muskel kommt mindestens zweimal pro Woche dran. Die Übungen passen zu deiner Ausstattung '
                'und lassen sich nach dem Übernehmen frei ändern.',
            children: [
              for (final routine in suggestions)
                ListTile(
                  title: Text(routine.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text(routine.items.map((item) => item.name).join(' · ')),
                  trailing: TextButton(
                    onPressed: routines.any((other) => other.name == routine.name)
                        ? null
                        : () => changeGym(settings, (gym) => gym.routines.add(routine)),
                    child: const Text('Übernehmen'),
                  ),
                ),
              if (suggestions.length > 1)
                ListTile(
                  title: Text('Alle übernehmen', style: TextStyle(color: theme.colorScheme.primary)),
                  onTap: () => changeGym(settings, (gym) {
                    final existing = {for (final routine in gym.routines) routine.name};
                    gym.routines.addAll(suggestions.where((routine) => !existing.contains(routine.name)));
                  }),
                ),
              const EvidenceDisclosure(ruleIDs: ['gym.frequency', 'gym.load', 'gym.volume']),
            ],
          ),
        ],
      ),
    );
  }
}
