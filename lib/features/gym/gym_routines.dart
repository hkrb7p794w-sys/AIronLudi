part of 'gym_library.dart';

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
        leading: BarTextButton('Abbrechen', onPressed: () => Navigator.of(context).pop()),
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
                        background: Container(color: AppColors.of(context).alert),
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
          SwitchListTile.adaptive(
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
              child: Text('Entfernen', style: TextStyle(color: AppColors.of(context).alert)),
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
        leading: BarTextButton('Abbrechen', onPressed: () => Navigator.of(context).pop()),
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
            SwitchListTile.adaptive(
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
          SwitchListTile.adaptive(
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
            SwitchListTile.adaptive(
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
          ListTile(title: Text(_summary, style: AppText.footnote(context))),
          for (final text in issues.blocking)
            ListTile(
              leading: Icon(Icons.warning_amber, color: AppColors.of(context).alert),
              title: Text(text, style: TextStyle(color: AppColors.of(context).alert)),
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
                title: Text(item.name, style: AppText.callout(context).copyWith(fontWeight: FontWeight.bold)),
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
              ListTile(dense: true, title: Text(correction, style: AppText.caption(context))),
          ],
        ),
      FormSection(
        footer: 'Quelle: $_source. Ohne „Ersetzen“ kommen die Pläne zu deinen bestehenden hinzu.',
        children: [
          SwitchListTile.adaptive(
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
        ],
      ),
    ];
  }
}
