import 'dart:async';

import 'package:coach_core/coach_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../app/app_model.dart';
import '../../services/providers.dart';
import '../../ui/components.dart';
import '../../ui/sport_style.dart';
import '../../ui/symbols.dart';
import '../evidence/evidence_views.dart';
import '../settings/backup_screen.dart';
import 'personalization_widgets.dart';
import 'schedule_editor.dart';

/// Schritte des Assistenten.
enum OnboardingStep {
  sports('Was trainierst du?'),
  goal('Was ist dein Ziel?'),
  priorities('Was ist dir wichtig?'),
  focus('Worauf bereitest du dich vor?'),
  level('Wie viel Erfahrung hast du?'),
  body('Über dich'),
  schedule('Dein Wochenplan'),
  tracker('Fitness-Tracker'),
  summary('Alles bereit');

  const OnboardingStep(this.title);

  final String title;
}

/// Einrichtung und späteres Bearbeiten des Profils: Sportarten, Ziel, Fokus, Erfahrung, Körperdaten mit
/// Sicherheitscheck und Wochenplan. Die App passt Pläne, Ernährung und Empfehlungen daran an.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key, this.isEditing = false, this.initial});

  /// Beim Bearbeiten gibt es ein Schließen-Kreuz, beim ersten Start nicht.
  final bool isEditing;

  /// Ausgangswerte; `null` = neues Profil.
  final UserProfile? initial;

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  OnboardingStep _step = OnboardingStep.sports;
  late UserProfile _draft;
  late PersonalGoals _goals;
  late TrackerSetup _tracker;

  bool _eventEnabled = false;
  final _eventName = TextEditingController();
  late DateTime _eventDate;
  EventKind _eventKind = EventKind.run10k;
  final _eventTarget = TextEditingController();
  final _runDistance = TextEditingController();
  final _runPace = TextEditingController();
  final _restingHeartRate = TextEditingController();
  final _targetWeight = TextEditingController();
  final _weeks = TextEditingController();
  final _currentRunKilometers = TextEditingController();

  final _weight = TextEditingController();
  final _height = TextEditingController();
  final _age = TextEditingController();
  bool _isFemale = true;
  Diet _diet = Diet.omnivore;

  Set<Weekday> _availableDays = {};

  AppModel get _model => ref.read(appModelProvider);

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _eventDate = DateTime(now.year, now.month + 4, now.day);
    final initial = widget.initial?.copy() ?? UserProfile();
    final today = CalendarDay.today();
    _draft = initial;
    _goals = initial.effectiveGoals(today);
    _tracker = initial.tracker;
    if (initial.event case final event?) {
      _eventEnabled = true;
      _eventName.text = event.name;
      _eventDate = DateTime(event.date.year, event.date.month, event.date.day, 12);
      _eventKind = event.kind;
      _eventTarget.text = event.targetSeconds == null ? '' : TimeText.hms(event.targetSeconds!);
    }
    final targets = initial.targets;
    _runDistance.text = targets.runDistanceKilometers == null
        ? ''
        : GermanFormat.decimal(targets.runDistanceKilometers!);
    _runPace.text = targets.runPaceSecondsPerKilometer == null
        ? ''
        : GermanFormat.minutesSeconds(targets.runPaceSecondsPerKilometer!);
    _restingHeartRate.text = targets.restingHeartRate?.toString() ?? '';
    _targetWeight.text = targets.targetWeightKilograms == null
        ? ''
        : GermanFormat.decimal(targets.targetWeightKilograms!);
    _weeks.text = targets.weeksToTargetWeight?.toString() ?? '';
    _currentRunKilometers.text = initial.currentRunKilometersPerWeek == null
        ? ''
        : GermanFormat.decimal(initial.currentRunKilometersPerWeek!);
    _availableDays = initial.schedule.trainingDays.toSet();

    final model = _model;
    final known = model.settings.nutrition;
    final garmin = model.sync.profile;
    final body = known.profile(garmin, on: today);
    if (known.weightKilograms != null || garmin != null || widget.isEditing) {
      _weight.text = GermanFormat.decimal(body.weightKilograms);
      _height.text = '${body.heightCentimeters.round()}';
      _age.text = '${body.age}';
      _isFemale = body.isFemale;
      _diet = known.diet;
    }
    for (final controller in [_weight, _height, _age, _targetWeight, _weeks, _eventTarget, _runPace]) {
      controller.addListener(() => setState(() {}));
    }
  }

  @override
  void dispose() {
    for (final controller in [
      _eventName,
      _eventTarget,
      _runDistance,
      _runPace,
      _restingHeartRate,
      _targetWeight,
      _weeks,
      _currentRunKilometers,
      _weight,
      _height,
      _age,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  // Daten

  BodyProfile? get _body {
    final (weight, height, age) = (
      parseNumber(_weight.text),
      parseNumber(_height.text),
      int.tryParse(_age.text.trim()),
    );
    if (weight == null || height == null || age == null) return null;
    return BodyProfile(weightKilograms: weight, heightCentimeters: height, age: age, isFemale: _isFemale);
  }

  bool get _bodyIsValid {
    final body = _body;
    if (body == null) return false;
    return body.weightKilograms >= 30 &&
        body.weightKilograms <= 250 &&
        body.heightCentimeters >= 120 &&
        body.heightCentimeters <= 230 &&
        body.age >= 14 &&
        body.age <= 100;
  }

  /// Eingabeprüfung: Körperdaten bei Tippfehlern, sonst Ziele gegen Körperdaten und die Prognose der Uhr.
  List<InputIssue> get _inputIssues {
    final body = _body;
    if (body == null) return const [];
    if (!_bodyIsValid) return InputCheck.body(body);
    return InputCheck.goals(
      profile: _draft,
      body: body,
      predictions: _model.sync.racePredictions,
      today: CalendarDay.today(),
    );
  }

  GoalAssessment? get _assessment {
    final body = _body;
    if (!_bodyIsValid || body == null) return null;
    return GoalRules.assess(_draft, body);
  }

  /// Übernimmt die Eingaben eines Schritts ins Profil.
  void _commit(OnboardingStep step) {
    switch (step) {
      case OnboardingStep.focus:
        _draft.event = _eventEnabled
            ? EventGoal(
                name: _eventName.text.trim().isEmpty ? _eventKind.label : _eventName.text,
                date: CalendarDay.fromDate(_eventDate),
                kind: _eventKind,
                targetSeconds: TimeText.seconds(_eventTarget.text),
              )
            : null;
        _draft.targets = ImprovementTargets(
          runDistanceKilometers: _eventEnabled ? null : parseNumber(_runDistance.text),
          runPaceSecondsPerKilometer: _eventEnabled ? null : TimeText.seconds(_runPace.text),
          restingHeartRate: int.tryParse(_restingHeartRate.text.trim()),
          targetWeightKilograms: parseNumber(_targetWeight.text),
          weeksToTargetWeight: int.tryParse(_weeks.text.trim()),
        );
      case OnboardingStep.level:
        _draft.currentRunKilometersPerWeek = parseNumber(_currentRunKilometers.text);
      default:
        break;
    }
  }

  void _go(int direction) {
    if (direction > 0) _commit(_step);
    final index = _step.index + direction;
    if (index < 0 || index >= OnboardingStep.values.length) return;
    setState(() => _step = OnboardingStep.values[index]);
  }

  bool get _canContinue => switch (_step) {
    OnboardingStep.sports => _draft.sports.isNotEmpty,
    OnboardingStep.body => _bodyIsValid,
    OnboardingStep.schedule => !_draft.schedule.isEmpty,
    _ => true,
  };

  void _finish() {
    _commit(OnboardingStep.focus);
    _commit(OnboardingStep.level);
    final model = _model;
    final today = CalendarDay.today();
    final before = _draft.effectiveGoals(today);
    _draft
      ..mode = ProfileMode.personal
      ..onboardingDone = true
      ..updateGoals(_goals, on: today)
      ..tracker = _tracker;
    final body = _body;
    model.settings.nutrition = model.settings.nutrition.copy()
      ..weightKilograms = body?.weightKilograms
      ..heightCentimeters = body?.heightCentimeters
      ..age = body?.age
      ..isFemale = _isFemale
      ..diet = _diet;
    model.settings.profile = _draft;
    model.settings.applyProfileToNutrition(model.sync.profile);
    PersonalizationApply.applyDefaults(goals: _goals, before: before, tracker: _tracker, model: model);
    final providers = _tracker.providers;
    if (providers.contains(DataProvider.appleHealth) ||
        providers.contains(DataProvider.whoop) ||
        providers.contains(DataProvider.polar)) {
      model.health.isEnabled = true;
      unawaited(model.health.importNow(garminConnected: model.garmin.isConfigured));
    }
    if (widget.isEditing && mounted) Navigator.of(context).pop();
  }

  // Oberfläche

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: widget.isEditing,
      child: Scaffold(
        appBar: AppBar(
          title: Text(_step.title),
          automaticallyImplyLeading: false,
          leading: _step == OnboardingStep.sports
              ? null
              : IconButton(tooltip: 'Zurück', icon: const Icon(Icons.arrow_back), onPressed: () => _go(-1)),
          actions: [
            if (widget.isEditing)
              IconButton(
                tooltip: 'Schließen',
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.of(context).pop(),
              )
            else if (_step == OnboardingStep.sports)
              // Nach einer Neuinstallation: Daten aus der Datensicherung zurückholen statt neu einzurichten.
              TextButton(
                onPressed: () =>
                    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const BackupScreen())),
                child: const Text('Sicherung einspielen'),
              ),
          ],
        ),
        body: switch (_step) {
          OnboardingStep.sports => _sportsStep(),
          OnboardingStep.goal => _goalStep(),
          OnboardingStep.priorities => _prioritiesStep(),
          OnboardingStep.tracker => _trackerStep(),
          OnboardingStep.focus => _focusStep(),
          OnboardingStep.level => _levelStep(),
          OnboardingStep.body => _bodyStep(),
          OnboardingStep.schedule => _scheduleStep(),
          OnboardingStep.summary => _summaryStep(),
        },
        bottomNavigationBar: _bottomBar(),
      ),
    );
  }

  Widget _intro(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Text(text, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
  );

  Widget _sportsStep() => ListView(
    padding: const EdgeInsets.all(16),
    children: [
      _intro('Wähle alles, was du regelmäßig machst oder machen möchtest. Die App richtet sich danach.'),
      for (final sport in TrainingSport.values)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: SelectionCard(
            title: sport.label,
            symbol: sport.symbol,
            color: sport.color,
            isSelected: _draft.sports.contains(sport),
            onTap: () => setState(() {
              final sports = [..._draft.sports];
              if (!sports.remove(sport)) sports.add(sport);
              _draft.sports = sports;
            }),
          ),
        ),
    ],
  );

  Widget _goalStep() => ListView(
    padding: const EdgeInsets.all(16),
    children: [
      _intro('Das Hauptziel bestimmt Plan-Vorschlag, Ernährung und worauf Empfehlungen achten.'),
      GoalsPicker(
        goals: _goals,
        onChanged: (goals) => setState(() {
          _goals = goals;
          // Ernährungs- und Gewichtsrichtung folgt den Zielen (bleibt in den Einstellungen änderbar).
          _draft.goal = Personalization.fitnessGoal(goals);
          if (goals.has(TrainingGoal.competition)) _eventEnabled = true;
        }),
      ),
    ],
  );

  Widget _prioritiesStep() => ListView(
    padding: const EdgeInsets.all(16),
    children: [
      _intro('Bis zu drei, das Wichtigste zuerst. Optional – ohne Auswahl gelten die Standards zu deinem Ziel.'),
      PrioritiesPicker(goals: _goals, onChanged: (goals) => setState(() => _goals = goals)),
    ],
  );

  Widget _trackerStep() => ListView(
    padding: const EdgeInsets.all(16),
    children: [
      _intro('Damit die App weiß, woher Schlaf, Puls und Trainings kommen. Verbinden geht auch später.'),
      TrackerPicker(setup: _tracker, onChanged: (setup) => setState(() => _tracker = setup)),
    ],
  );

  Widget _field(TextEditingController controller, String label, {TextInputType? keyboard}) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    child: TextField(
      controller: controller,
      keyboardType: keyboard,
      decoration: InputDecoration(labelText: label),
    ),
  );

  static const _decimal = TextInputType.numberWithOptions(decimal: true);
  static const _digits = TextInputType.number;
  static const _time = TextInputType.datetime;

  Widget _focusStep() => ListView(
    children: [
      FormSection(
        children: [
          RadioGroup<bool>(
            groupValue: _eventEnabled,
            onChanged: (value) => setState(() => _eventEnabled = value ?? false),
            child: const Column(
              children: [
                RadioListTile(value: false, title: Text('Allgemein besser werden')),
                RadioListTile(value: true, title: Text('Wettkampf oder Lauf')),
              ],
            ),
          ),
        ],
      ),
      if (_eventEnabled)
        FormSection(
          header: 'Wettkampf',
          children: [
            _field(_eventName, 'Name (z. B. Stadtlauf)'),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: DropdownButtonFormField<EventKind>(
                initialValue: _eventKind,
                decoration: const InputDecoration(labelText: 'Art'),
                items: [for (final kind in EventKind.values) DropdownMenuItem(value: kind, child: Text(kind.label))],
                onChanged: (kind) => setState(() => _eventKind = kind ?? _eventKind),
              ),
            ),
            ListTile(
              title: const Text('Datum'),
              trailing: Text(DateFormat('d. MMM y', 'de_DE').format(_eventDate)),
              onTap: () async {
                final now = DateTime.now();
                final picked = await showDatePicker(
                  context: context,
                  initialDate: _eventDate.isBefore(now) ? now : _eventDate,
                  firstDate: now,
                  lastDate: DateTime(now.year + 5),
                );
                if (picked != null) setState(() => _eventDate = picked);
              },
            ),
            _field(_eventTarget, 'Zielzeit (optional, z. B. 1:45:00)', keyboard: _time),
          ],
        )
      else
        FormSection(
          header: 'Ziele (alles optional)',
          footer: 'Das Tempo beim Gewicht begrenzt die App auf einen gesunden Bereich, auch wenn der Wunsch schneller wäre.',
          children: [
            if (_draft.sports.contains(TrainingSport.run)) ...[
              _field(_runDistance, 'Strecke am Stück in km (z. B. 10)', keyboard: _decimal),
              _field(_runPace, 'Wunschtempo in min/km (z. B. 5:45)', keyboard: _time),
            ],
            _field(_restingHeartRate, 'Ruhepuls senken auf … bpm', keyboard: _digits),
            if (_draft.goal.losesWeight || _draft.goal.gainsWeight) ...[
              _field(_targetWeight, 'Zielgewicht in kg', keyboard: _decimal),
              _field(_weeks, 'In wie vielen Wochen? (optional)', keyboard: _digits),
            ],
          ],
        ),
    ],
  );

  Widget _levelStep() => ListView(
    children: [
      for (final sport in _draft.sports.where((sport) => sport != TrainingSport.other))
        FormSection(
          header: sport.label,
          children: [
            RadioGroup<ExperienceLevel>(
              groupValue: _draft.level(sport),
              onChanged: (level) => setState(() {
                if (level != null) _draft.setLevel(level, sport);
              }),
              child: Column(
                children: [
                  for (final level in ExperienceLevel.values)
                    RadioListTile(value: level, title: Text(level.label), subtitle: Text(level.detail)),
                ],
              ),
            ),
          ],
        ),
      if (_draft.sports.contains(TrainingSport.run))
        FormSection(
          header: 'Aktuell gelaufen',
          footer: 'Leer lassen: Dann nutzt die App deine Garmin-Daten der letzten Wochen.',
          children: [_field(_currentRunKilometers, 'Kilometer pro Woche', keyboard: _decimal)],
        ),
    ],
  );

  Widget _bodyStep() {
    final assessment = _assessment;
    return ListView(
      children: [
        FormSection(
          header: 'Körperdaten',
          footer: 'Für Kalorien- und Proteinziele. Leer lassen geht nicht; du kannst sie später ändern.',
          children: [
            _field(_weight, 'Gewicht in kg', keyboard: _decimal),
            _field(_height, 'Größe in cm', keyboard: _digits),
            _field(_age, 'Alter', keyboard: _digits),
            Padding(
              padding: const EdgeInsets.all(16),
              child: SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: true, label: Text('Weiblich')),
                  ButtonSegment(value: false, label: Text('Männlich')),
                ],
                selected: {_isFemale},
                onSelectionChanged: (selection) => setState(() => _isFemale = selection.first),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: DropdownButtonFormField<Diet>(
                initialValue: _diet,
                decoration: const InputDecoration(labelText: 'Ernährung'),
                items: [for (final diet in Diet.values) DropdownMenuItem(value: diet, child: Text(diet.label))],
                onChanged: (diet) => setState(() => _diet = diet ?? _diet),
              ),
            ),
          ],
        ),
        FormSection(
          header: 'Sicherheits-Check',
          footer:
              'Bei diesen Angaben ist die App vorsichtiger und setzt keine Gewichtsziele. Sie ersetzt keine ärztliche '
              'Beratung.',
          children: [
            for (final flag in HealthFlag.values)
              SwitchListTile(
                title: Text(flag.label),
                value: _draft.health.contains(flag),
                onChanged: (on) => setState(() {
                  _draft.health = on
                      ? [..._draft.health, flag]
                      : _draft.health.where((other) => other != flag).toList();
                }),
              ),
          ],
        ),
        if (assessment != null && assessment.notes.isNotEmpty)
          FormSection(
            header: 'Hinweise zu deinem Ziel',
            children: [
              for (final note in assessment.notes) ListTile(title: Text(note)),
              EvidenceDisclosure(ruleIDs: assessment.evidenceIDs),
            ],
          ),
        InputIssuesSection(issues: _inputIssues),
      ],
    );
  }

  Widget _scheduleStep() {
    final scheme = Theme.of(context).colorScheme;
    return ListView(
      children: [
        FormSection(
          header: 'An welchen Tagen hast du Zeit?',
          footer: 'Die App verteilt passende Einheiten auf diese Tage. Danach kannst du alles frei ändern.',
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  for (final weekday in Weekday.values)
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 3),
                        child: Semantics(
                          label: weekday.long,
                          selected: _availableDays.contains(weekday),
                          button: true,
                          child: Material(
                            color: _availableDays.contains(weekday)
                                ? scheme.primary
                                : scheme.onSurface.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(10),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(10),
                              onTap: () => setState(() {
                                if (!_availableDays.remove(weekday)) _availableDays.add(weekday);
                              }),
                              child: SizedBox(
                                height: 44,
                                child: Center(
                                  child: Text(
                                    weekday.short,
                                    style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                      color: _availableDays.contains(weekday) ? scheme.onPrimary : scheme.onSurface,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            ListTile(
              leading: Icon(AppSymbols.of('wand.and.stars')),
              title: const Text('Wochenplan vorschlagen'),
              enabled: _availableDays.isNotEmpty && _draft.sports.isNotEmpty,
              onTap: () => setState(
                () => _draft.schedule = SchedulePlanner.suggest(
                  profile: _draft,
                  availableDays: Weekday.values.where(_availableDays.contains).toList(),
                ),
              ),
            ),
          ],
        ),
        FormSection(
          header: 'Was machst du an welchem Tag?',
          children: [
            ScheduleEditor(
              schedule: _draft.schedule,
              sports: _draft.sports,
              onChanged: (schedule) => setState(() => _draft.schedule = schedule),
            ),
          ],
        ),
        ScheduleHintsSection(hints: ScheduleCheck.hints(_draft.schedule, _draft)),
      ],
    );
  }

  Widget _summaryStep() {
    final assessment = _assessment;
    final model = ref.watch(appModelProvider);
    final event = _draft.event;
    final muted = TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant);
    return ListView(
      children: [
        FormSection(
          header: 'Dein Profil',
          children: [
            LabeledRow(label: 'Sportarten', value: _draft.sports.map((sport) => sport.shortLabel).join(', ')),
            LabeledRow(label: 'Hauptziel', value: _goals.primary.label),
            if (_goals.secondary.isNotEmpty)
              LabeledRow(label: 'Nebenziele', value: _goals.secondary.map((goal) => goal.label).join(', ')),
            LabeledRow(label: 'Wichtig', value: _goals.effectivePriorities.map((area) => area.label).join(', ')),
            if (event != null)
              LabeledRow(label: 'Wettkampf', value: '${event.name} · ${GermanFormat.date(event.date)}'),
            LabeledRow(label: 'Trainingstage', value: '${_draft.schedule.trainingDays.length} pro Woche'),
          ],
        ),
        if (assessment != null && assessment.notes.isNotEmpty)
          FormSection(
            header: 'Gut zu wissen',
            children: [for (final note in assessment.notes) ListTile(title: Text(note))],
          ),
        InputIssuesSection(issues: _inputIssues),
        if (_tracker.usesTracker == true && _tracker.providers.isNotEmpty)
          FormSection(
            header: 'Verbinden',
            children: [
              for (final provider in _tracker.providers)
                if (switch (provider) {
                      DataProvider.garmin when !model.garmin.isConfigured =>
                        'Garmin: nach dem Start unter Einstellungen › Garmin anmelden.',
                      DataProvider.appleHealth =>
                        'Apple Health: Der Import wird eingeschaltet; das Gerät fragt gleich nach den Daten.',
                      DataProvider.whoop || DataProvider.polar =>
                        '${provider.label}: kommt über Apple Health – schalte dort die Weitergabe an Health ein.',
                      DataProvider.fitbit => 'Fitbit: derzeit keine Verbindung möglich.',
                      _ => null,
                    }
                    case final text?)
                  ListTile(title: Text(text)),
            ],
          ),
        FormSection(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'Die App prüft täglich deine Erholung (Garmin) gegen deinen Wochenplan und schlägt vor, Einheiten zu '
                'verschieben oder lockerer zu machen. Ruhetage und Ziele kannst du jederzeit in den Einstellungen '
                'ändern.',
                style: muted,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _bottomBar() {
    final total = OnboardingStep.values.length;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Semantics(
              label: 'Schritt ${_step.index + 1} von $total',
              child: LinearProgressIndicator(value: (_step.index + 1) / total),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: FilledButton(
                onPressed: _canContinue ? () => _step == OnboardingStep.summary ? _finish() : _go(1) : null,
                child: Text(_step == OnboardingStep.summary ? 'Los geht’s' : 'Weiter'),
              ),
            ),
            if (_step == OnboardingStep.priorities || _step == OnboardingStep.tracker)
              TextButton(
                onPressed: () {
                  setState(() {
                    if (_step == OnboardingStep.priorities) {
                      _goals = _goals.copyWith(priorities: const []);
                    } else {
                      _tracker = const TrackerSetup();
                    }
                  });
                  _go(1);
                },
                child: const Text('Überspringen'),
              ),
          ],
        ),
      ),
    );
  }
}
