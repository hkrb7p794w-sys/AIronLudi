import 'dart:async';

import 'package:coach_core/coach_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../services/providers.dart';
import '../../ui/components.dart';
import '../evidence/evidence_views.dart';
import 'exercise_history_charts.dart';
import 'exercise_picker.dart';
import 'gym_controller.dart';
import 'muscle_views.dart';
import 'workout_parts.dart';

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
              SwitchListTile(
                title: const Text('Nur mit meiner Ausstattung'),
                value: _onlyAvailable,
                onChanged: (value) => setState(() => _onlyAvailable = value),
              ),
              ListTile(
                title: const Text('Meine Ausstattung'),
                trailing: const Icon(Icons.chevron_right),
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
                      trailing: const Icon(Icons.chevron_right),
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
    final secondary = TextStyle(fontSize: 13, color: theme.colorScheme.onSurfaceVariant);
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
                    leading: const Icon(Icons.feedback_outlined, color: Colors.orange),
                    title: Text(hint, style: const TextStyle(color: Colors.orange)),
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
                        child: Text('${index + 1}', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
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
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
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
                SwitchListTile(
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
                SwitchListTile(
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
                      background: Container(color: Colors.red),
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

/// Routine bearbeiten: Übungen, Reihenfolge, Sätze, Wiederholungs- bzw. Sekundenbereich, Pause, Supersatz und
/// Startgewicht. Gibt die geänderte Kopie zurück.
class RoutineEditor extends ConsumerStatefulWidget {
  const RoutineEditor({super.key, required this.routine});

  final Routine routine;

  @override
  ConsumerState<RoutineEditor> createState() => _RoutineEditorState();
}

class _RoutineEditorState extends ConsumerState<RoutineEditor> {
  late final Routine _routine = widget.routine.copy();
  late final _name = TextEditingController(text: _routine.name);
  bool _reordering = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Widget _stepper(
    String label,
    int value, {
    required int min,
    required int max,
    int step = 1,
    required ValueChanged<int> onChanged,
  }) => ListTile(
    title: Text(label),
    trailing: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: '$label verringern',
          icon: const Icon(Icons.remove),
          onPressed: value - step >= min ? () => setState(() => onChanged(value - step)) : null,
        ),
        IconButton(
          tooltip: '$label erhöhen',
          icon: const Icon(Icons.add),
          onPressed: value + step <= max ? () => setState(() => onChanged(value + step)) : null,
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final custom = ref.watch(coachSettingsProvider).gym.customExercises;
    final items = _routine.items;
    final canSave = _name.text.trim().isNotEmpty && items.isNotEmpty;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Trainingsplan'),
        leading: TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Abbrechen')),
        leadingWidth: 100,
        actions: [
          TextButton(
            onPressed: canSave ? () => Navigator.of(context).pop(_routine..name = _name.text.trim()) : null,
            child: const Text('Sichern'),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: TextButton.icon(
            onPressed: items.length < 2 && !_reordering ? null : () => setState(() => _reordering = !_reordering),
            icon: const Icon(Icons.swap_vert),
            label: Text(_reordering ? 'Fertig sortiert' : 'Reihenfolge ändern'),
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          FormSection(
            footer:
                'Eigener Plan: Übungen, Reihenfolge, Sätze, Ziel-Wiederholungen, Pausen und Startgewicht frei wählbar. '
                'Im Supersatz wechseln sich die Übungen ab, die Pause kommt nach der Runde.',
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: TextField(
                  controller: _name,
                  decoration: const InputDecoration(labelText: 'Name'),
                  onChanged: (_) => setState(() {}),
                ),
              ),
            ],
          ),
          if (_reordering)
            FormSection(
              header: 'Reihenfolge',
              footer: 'Ziehen zum Verschieben, zur Seite wischen zum Entfernen.',
              children: [
                ReorderableListView(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  onReorderItem: (from, to) => setState(() => items.insert(to, items.removeAt(from))),
                  children: [
                    for (final item in items)
                      Dismissible(
                        key: ValueKey(item.id),
                        direction: DismissDirection.endToStart,
                        background: Container(color: Colors.red),
                        onDismissed: (_) => setState(() => items.removeWhere((other) => other.id == item.id)),
                        child: ListTile(title: Text(item.name), trailing: Text('${item.sets} Sätze')),
                      ),
                  ],
                ),
              ],
            )
          else
            for (final (index, item) in items.indexed) _itemSection(index, item, custom),
          FormSection(
            footer:
                'Das Startgewicht gilt, solange es für die Übung noch keinen Verlauf gibt; danach schlägt die '
                'Progression das Gewicht vor. Eigene Übungen legst du in der Übungsauswahl an.',
            children: [
              ListTile(
                leading: const Icon(Icons.add),
                title: const Text('Übung hinzufügen'),
                onTap: () async {
                  final exercise = await Navigator.of(context).push<ExerciseInfo>(
                    MaterialPageRoute(fullscreenDialog: true, builder: (_) => const ExercisePickerScreen()),
                  );
                  if (exercise != null) setState(() => items.add(RoutineItem.fromExercise(exercise)));
                },
              ),
            ],
          ),
          if (items.isNotEmpty)
            MuscleHeatmapSection(
              title: 'Beanspruchung je Einheit',
              values: MuscleLoad.routine(_routine, custom: custom),
              footer:
                  'Geplante Arbeitssätze je Muskel: Hauptmuskel 1, mitarbeitende Muskeln 0,5. So siehst du, was der '
                  'Plan auslässt oder doppelt trifft.',
            ),
        ],
      ),
    );
  }

  /// Einstellungen je Übung (Sätze, Bereich, Pause, Supersatz, Startgewicht).
  Widget _itemSection(int index, RoutineItem item, List<ExerciseInfo> custom) {
    final items = _routine.items;
    final isTime = ExerciseLibrary.info(item.exerciseID, custom: custom)?.tracking == ExerciseTracking.time;
    final unit = isTime ? 's' : 'Wdh.';
    return FormSection(
      header: '${index + 1}. ${item.name}',
      children: [
        _stepper('${item.sets} Sätze', item.sets, min: 1, max: 10, onChanged: (value) => item.sets = value),
        _stepper(
          'ab ${item.lowerReps} $unit',
          item.lowerReps,
          min: 1,
          max: item.upperReps < 1 ? 1 : item.upperReps,
          step: isTime ? 5 : 1,
          onChanged: (value) => item.lowerReps = value,
        ),
        _stepper(
          'bis ${item.upperReps} $unit',
          item.upperReps,
          min: item.lowerReps,
          max: isTime ? 600 : 100,
          step: isTime ? 5 : 1,
          onChanged: (value) => item.upperReps = value,
        ),
        _stepper(
          'Pause ${item.restSeconds} s',
          item.restSeconds,
          min: 30,
          max: 300,
          step: 15,
          onChanged: (value) => item.restSeconds = value,
        ),
        if (index < items.length - 1)
          SwitchListTile(
            title: Text('Supersatz mit ${items[index + 1].name}'),
            value: item.supersetWithNext,
            onChanged: (value) => setState(() => item.supersetWithNext = value),
          ),
        if (!isTime)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextFormField(
              key: ValueKey('weight-${item.id}'),
              initialValue: item.weightKg == null ? '' : GermanFormat.number(item.weightKg!),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
              decoration: const InputDecoration(labelText: 'Startgewicht', hintText: 'aus Verlauf', suffixText: 'kg'),
              onChanged: (text) => item.weightKg = parseNumber(text),
            ),
          ),
        Row(
          children: [
            IconButton(
              tooltip: 'Nach oben',
              icon: const Icon(Icons.arrow_upward),
              onPressed: index == 0 ? null : () => setState(() => items.insert(index - 1, items.removeAt(index))),
            ),
            IconButton(
              tooltip: 'Nach unten',
              icon: const Icon(Icons.arrow_downward),
              onPressed: index == items.length - 1
                  ? null
                  : () => setState(() => items.insert(index + 1, items.removeAt(index))),
            ),
            const Spacer(),
            TextButton(
              onPressed: () => setState(() => items.removeWhere((other) => other.id == item.id)),
              child: const Text('Entfernen', style: TextStyle(color: Colors.red)),
            ),
          ],
        ),
      ],
    );
  }
}

/// KI-Trainingsplan: erst ein kurzer Fragebogen, dann ein Vorschlag aus Profil, Ausstattung und Verlauf. Die Regeln
/// prüfen den Vorschlag (bekannte Übungen, eigene Ausstattung, Grenzen für Sätze und Pausen, Wochenvolumen).
class GymPlanScreen extends ConsumerStatefulWidget {
  const GymPlanScreen({super.key, required this.gym});

  final GymController gym;

  @override
  ConsumerState<GymPlanScreen> createState() => _GymPlanScreenState();
}

class _GymPlanScreenState extends ConsumerState<GymPlanScreen> {
  final _request = PlanRequest();
  final _limitations = TextEditingController();
  PlanResult? _result;
  String _source = '';
  bool _loading = false;
  bool _replaceExisting = false;

  @override
  void initState() {
    super.initState();
    // Nur beim ersten Öffnen vorbelegen, sonst würden eigene Eingaben überschrieben.
    final settings = ref.read(coachSettingsProvider);
    final days = settings.profile.schedule.count(TrainingSport.strength);
    _request
      ..daysPerWeek = days < 2 ? 2 : days
      ..experience = settings.profile.level(TrainingSport.strength)
      ..equipment = {...settings.gym.equipment};
  }

  @override
  void dispose() {
    _limitations.dispose();
    super.dispose();
  }

  Set<Equipment> get _usable => _request.equipment ?? ref.read(coachSettingsProvider).gym.equipment;

  /// Genau das, was an die KI geht.
  String get _summary {
    final settings = ref.read(coachSettingsProvider);
    final focus = _request.focus.isEmpty
        ? 'ohne Schwerpunkt'
        : _request.focus.map((group) => group.rawValue).join(', ');
    final equipment = Equipment.values.where(_usable.contains).map((item) => item.label).join(', ');
    final experience = (_request.experience ?? settings.profile.level(TrainingSport.strength)).label;
    return '${_request.goal.label}, ${_request.daysPerWeek} Tage pro Woche, ${_request.minutesPerSession} Minuten. '
        'Schwerpunkt: $focus. Erfahrung: $experience. Ausstattung: $equipment.'
        '${_request.limitations.isEmpty ? '' : ' Einschränkungen: ${_request.limitations}.'}';
  }

  /// Regel-Vorschlag mit den letzten Gewichten als Startwert.
  PlanResult _fallback(Map<String, double> lastWeights) {
    final routines = RoutineTemplates.suggest(profile: ref.read(coachSettingsProvider).profile, equipment: _usable);
    for (final routine in routines) {
      for (final item in routine.items) {
        item.weightKg = lastWeights[item.exerciseID];
      }
    }
    return PlanResult(
      routines: routines,
      notes: const ['Jeder große Muskel kommt mindestens zweimal pro Woche dran.'],
      corrections: const [],
    );
  }

  Future<void> _generate() async {
    final settings = ref.read(coachSettingsProvider);
    final ai = ref.read(aiClientProvider);
    final lastWeights = {
      for (final MapEntry(:key, :value) in GymCoach.lastSets(widget.gym.sessions).entries) key: value.weightKg,
    };
    if (!ai.isConfigured) {
      setState(() {
        _result = _fallback(lastWeights);
        _source = 'Regeln (ohne KI)';
      });
      return;
    }
    setState(() => _loading = true);
    try {
      final response = await ai.run(
        'gym_plan',
        input: GymCoach.planInput(
          request: _request,
          profile: settings.profile,
          equipment: settings.gym.equipment,
          routines: settings.gym.routines,
          sessions: widget.gym.sessions,
          custom: settings.gym.customExercises,
          today: CalendarDay.today(),
          notes: settings.gym.notes,
        ),
      );
      final checked = GymCoach.validatePlan(
        response.output,
        request: _request,
        equipment: _usable,
        custom: settings.gym.customExercises,
        lastWeights: lastWeights,
      );
      if (!mounted) return;
      setState(() {
        if (checked.routines.isEmpty) {
          _result = _fallback(lastWeights);
          _source = 'Regeln (KI-Vorschlag unbrauchbar)';
        } else {
          _result = checked;
          _source = 'KI · ${response.model}, geprüft von den Regeln';
        }
      });
    } on Object {
      if (!mounted) return;
      setState(() {
        _result = _fallback(lastWeights);
        _source = 'Regeln (KI nicht erreichbar)';
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _adopt(PlanResult result) {
    changeGym(ref.read(coachSettingsProvider), (gym) {
      if (_replaceExisting) {
        gym.routines = [...result.routines];
      } else {
        final existing = {for (final routine in gym.routines) routine.name};
        gym.routines.addAll([
          for (final routine in result.routines)
            routine..name = existing.contains(routine.name) ? '${routine.name} (KI)' : routine.name,
        ]);
      }
    });
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final result = _result;
    return Scaffold(
      appBar: AppBar(
        title: Text(result == null ? 'KI-Trainingsplan' : 'Vorschlag'),
        leading: TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Abbrechen')),
        leadingWidth: 100,
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: result == null ? _questions() : _preview(result),
      ),
    );
  }

  List<Widget> _questions() {
    final settings = ref.watch(coachSettingsProvider);
    final ai = ref.watch(aiClientProvider);
    final issues = GymCoach.planIssues(_request, equipment: settings.gym.equipment);
    Widget stepper(String label, int value, int min, int max, int step, ValueChanged<int> onChanged) => ListTile(
      title: Text(label),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: '$label verringern',
            icon: const Icon(Icons.remove),
            onPressed: value - step >= min ? () => setState(() => onChanged(value - step)) : null,
          ),
          IconButton(
            tooltip: '$label erhöhen',
            icon: const Icon(Icons.add),
            onPressed: value + step <= max ? () => setState(() => onChanged(value + step)) : null,
          ),
        ],
      ),
    );
    return [
      FormSection(
        header: 'Ziel',
        children: [
          // Volle Breite: die Ziele sind für eine Auswahl rechts neben dem Titel zu lang.
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: DropdownButtonFormField<PlanGoal>(
              initialValue: _request.goal,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Ziel'),
              items: [for (final goal in PlanGoal.values) DropdownMenuItem(value: goal, child: Text(goal.label))],
              onChanged: (goal) => setState(() => _request.goal = goal ?? _request.goal),
            ),
          ),
          stepper('${_request.daysPerWeek} Tage pro Woche', _request.daysPerWeek, 1, 6, 1, (value) {
            _request.daysPerWeek = value;
          }),
          stepper('${_request.minutesPerSession} Minuten je Einheit', _request.minutesPerSession, 30, 120, 15, (value) {
            _request.minutesPerSession = value;
          }),
        ],
      ),
      FormSection(
        header: 'Schwerpunkt (optional)',
        children: [
          for (final group in [...GymCoach.majorGroups, MuscleGroup.biceps, MuscleGroup.triceps, MuscleGroup.core])
            SwitchListTile(
              title: Text(group.rawValue),
              value: _request.focus.contains(group),
              onChanged: (on) => setState(() => on ? _request.focus.add(group) : _request.focus.remove(group)),
            ),
        ],
      ),
      FormSection(
        header: 'Beschwerden oder Einschränkungen',
        footer: 'Übungen, die das belasten, lässt die KI weg. Bei Schmerzen bitte ärztlich abklären.',
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              controller: _limitations,
              maxLines: null,
              decoration: const InputDecoration(hintText: 'z. B. Schulter links, Knie'),
              onChanged: (text) => setState(() => _request.limitations = text),
            ),
          ),
        ],
      ),
      FormSection(
        footer: 'Außerdem fließen deine letzten Gewichte, die Beobachtungen aus dem Verlauf und deine anderen Sportarten ein.',
        children: [
          SwitchListTile(
            title: const Text('Übungen aus meinen Trainingsplänen bevorzugen'),
            value: _request.keepFavorites,
            onChanged: (value) => setState(() => _request.keepFavorites = value),
          ),
        ],
      ),
      FormSection(
        header: 'Erfahrung',
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: DropdownButtonFormField<ExperienceLevel>(
              initialValue: _request.experience ?? settings.profile.level(TrainingSport.strength),
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Erfahrung im Krafttraining'),
              items: [
                for (final level in ExperienceLevel.values) DropdownMenuItem(value: level, child: Text(level.label)),
              ],
              onChanged: (level) => setState(() => _request.experience = level),
            ),
          ),
        ],
      ),
      FormSection(
        header: 'Ausstattung für diesen Plan',
        footer: 'Gilt nur für diesen Plan. Deine Standard-Ausstattung bleibt in den Einstellungen unverändert.',
        children: [
          for (final item in Equipment.values)
            SwitchListTile(
              title: Text(item.label),
              value: _usable.contains(item),
              onChanged: (on) => setState(() {
                final value = {..._usable};
                on ? value.add(item) : value.remove(item);
                _request.equipment = value;
              }),
            ),
        ],
      ),
      FormSection(
        header: 'Zusammenfassung',
        children: [
          ListTile(title: Text(_summary, style: const TextStyle(fontSize: 13))),
          for (final text in issues.blocking)
            ListTile(
              leading: const Icon(Icons.warning_amber, color: Colors.red),
              title: Text(text, style: const TextStyle(color: Colors.red)),
            ),
          for (final text in issues.hints)
            ListTile(dense: true, leading: const Icon(Icons.info_outline), title: Text(text)),
        ],
      ),
      FormSection(
        footer: ai.isConfigured ? null : 'Ohne KI-Worker gibt es den Regel-Vorschlag passend zu deinen Krafttagen.',
        children: [
          ListTile(
            leading: _loading
                ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.auto_awesome),
            title: Text(_loading ? 'Plan wird erstellt …' : 'Plan erstellen'),
            enabled: !_loading && issues.blocking.isEmpty,
            onTap: _generate,
          ),
        ],
      ),
    ];
  }

  List<Widget> _preview(PlanResult result) {
    final custom = ref.read(coachSettingsProvider).gym.customExercises;
    String itemText(RoutineItem item) {
      final isTime = ExerciseLibrary.info(item.exerciseID, custom: custom)?.tracking == ExerciseTracking.time;
      final weight = item.weightKg == null ? '' : ' · Start ${GermanFormat.number(item.weightKg!)} kg';
      return '${item.sets} × ${item.lowerReps}–${item.upperReps} ${isTime ? 's' : 'Wdh.'} · Pause ${item.restSeconds} s$weight';
    }

    return [
      for (final routine in result.routines)
        FormSection(
          header: routine.name,
          children: [
            for (final item in routine.items)
              ListTile(
                title: Text(item.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                subtitle: Text(itemText(item)),
              ),
          ],
        ),
      if (result.notes.isNotEmpty)
        FormSection(
          header: 'Hinweise',
          children: [for (final note in result.notes) ListTile(title: Text(note))],
        ),
      if (result.corrections.isNotEmpty)
        FormSection(
          header: 'Von den Regeln korrigiert',
          children: [
            for (final correction in result.corrections)
              ListTile(dense: true, title: Text(correction, style: const TextStyle(fontSize: 12))),
          ],
        ),
      FormSection(
        footer: 'Quelle: $_source. Ohne „Ersetzen“ kommen die Pläne zu deinen bestehenden hinzu.',
        children: [
          SwitchListTile(
            title: const Text('Bisherige Trainingspläne ersetzen'),
            value: _replaceExisting,
            onChanged: (value) => setState(() => _replaceExisting = value),
          ),
          ListTile(
            leading: const Icon(Icons.check_circle),
            title: const Text('Plan übernehmen', style: TextStyle(fontWeight: FontWeight.w600)),
            onTap: () => _adopt(result),
          ),
          ListTile(
            leading: const Icon(Icons.refresh),
            title: const Text('Neu erstellen'),
            onTap: () => setState(() => _result = null),
          ),
          const EvidenceDisclosure(ruleIDs: ['gym.frequency', 'gym.volume', 'gym.load']),
        ],
      ),
    ];
  }
}
