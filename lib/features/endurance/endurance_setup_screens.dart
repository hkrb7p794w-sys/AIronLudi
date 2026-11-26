part of 'endurance_screens.dart';

/// Eingabe der Schwellen (Lauf-Pace, FTP, CSS, Schwellenpuls).
class ThresholdFields {
  ThresholdFields(AthleteThresholds initial)
    : pace = TextEditingController(text: initial.runThresholdPace == null ? '' : clockText(initial.runThresholdPace!)),
      ftp = TextEditingController(text: initial.ftpWatts?.toString() ?? ''),
      css = TextEditingController(text: initial.swimCss == null ? '' : clockText(initial.swimCss!)),
      heartRate = TextEditingController(text: initial.runThresholdHeartRate?.toString() ?? '');

  final TextEditingController pace;
  final TextEditingController ftp;
  final TextEditingController css;
  final TextEditingController heartRate;

  /// Werte oder Fehlermeldung.
  (AthleteThresholds?, String?) read() {
    int? clock(TextEditingController field, String label, int low, int high) {
      if (field.text.trim().isEmpty) return null;
      final value = parseClock(field.text);
      if (value == null || value < low || value > high) throw FormatException('$label bitte als m:ss angeben.');
      return value;
    }

    int? whole(TextEditingController field, String label, int low, int high) {
      if (field.text.trim().isEmpty) return null;
      final value = int.tryParse(field.text.trim());
      if (value == null || value < low || value > high) throw FormatException('$label zwischen $low und $high.');
      return value;
    }

    try {
      return (
        AthleteThresholds(
          runThresholdPace: clock(pace, 'Schwellen-Pace Laufen', 150, 600),
          ftpWatts: whole(ftp, 'FTP', 60, 600),
          swimCss: clock(css, 'CSS', 60, 300),
          runThresholdHeartRate: whole(heartRate, 'Schwellenpuls', 100, 220),
        ),
        null,
      );
    } on FormatException catch (error) {
      return (null, error.message);
    }
  }

  List<Widget> widgets() => [
    _field(pace, 'Schwellen-Pace Laufen (m:ss /km)', TextInputType.datetime),
    _field(ftp, 'FTP Rad (Watt)', TextInputType.number),
    _field(css, 'CSS Schwimmen (m:ss /100 m)', TextInputType.datetime),
    _field(heartRate, 'Schwellenpuls (bpm)', TextInputType.number),
  ];

  static Widget _field(TextEditingController controller, String label, TextInputType type) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    child: TextField(
      controller: controller,
      keyboardType: type,
      decoration: InputDecoration(labelText: label, border: InputBorder.none),
    ),
  );

  void dispose() {
    pace.dispose();
    ftp.dispose();
    css.dispose();
    heartRate.dispose();
  }
}

class ThresholdsScreen extends ConsumerStatefulWidget {
  const ThresholdsScreen({super.key, required this.initial});

  final AthleteThresholds initial;

  @override
  ConsumerState<ThresholdsScreen> createState() => _ThresholdsScreenState();
}

class _ThresholdsScreenState extends ConsumerState<ThresholdsScreen> {
  late final ThresholdFields _fields = ThresholdFields(widget.initial);
  String? _error;

  @override
  void dispose() {
    _fields.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final (thresholds, error) = _fields.read();
    if (thresholds == null) {
      setState(() => _error = error);
      return;
    }
    await ref.read(enduranceControllerProvider).updateThresholds(thresholds);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Schwellenwerte'),
      actions: [TextButton(onPressed: () => unawaited(_save()), child: const Text('Sichern'))],
    ),
    body: ListView(
      children: [
        FormSection(
          footer:
              _error ??
              'Kommende Einheiten werden mit den neuen Zielen neu gebaut; erledigte bleiben. Ohne Wert plant der Plan '
                  'mit Puls bzw. nur mit Zonen.',
          children: _fields.widgets(),
        ),
      ],
    ),
  );
}

/// Plan erstellen: Ziel oder Zeitraum, Disziplinen, Tage, Zeit, Schwellen.
class EndurancePlanSetupScreen extends ConsumerStatefulWidget {
  const EndurancePlanSetupScreen({super.key, this.goal});

  /// Vorausgewählter Wettkampf (z. B. nach einer Zieländerung); sonst der nächste aus den Zielen der App.
  final KnownGoal? goal;

  @override
  ConsumerState<EndurancePlanSetupScreen> createState() => _EndurancePlanSetupScreenState();
}

class _EndurancePlanSetupScreenState extends ConsumerState<EndurancePlanSetupScreen> {
  PlanningMode _mode = PlanningMode.goal;
  EnduranceEvent _event = EnduranceEvent.run10k;
  late CalendarDay _eventDay = CalendarDay.today().adding(7 * 12);
  final _target = TextEditingController();
  int _weeks = 8;
  PeriodFocus _focus = PeriodFocus.fitness;
  final Set<EnduranceSport> _sports = {EnduranceSport.run};
  final Set<Weekday> _days = {Weekday.tuesday, Weekday.thursday, Weekday.saturday, Weekday.sunday};
  Weekday _longDay = Weekday.sunday;
  double _hours = 5;
  late final ThresholdFields _fields;
  String? _error;
  bool _saving = false;

  /// Wettkämpfe aus den Zielen der App (Einrichtung, Saisonplan).
  List<KnownGoal> _known = const [];

  /// Gewählter bekannter Wettkampf; `null` = anderes Ziel von Hand.
  KnownGoal? _goal;
  String _basis = '';

  @override
  void initState() {
    super.initState();
    final settings = ref.read(coachSettingsProvider);
    final existing = ref.read(enduranceControllerProvider).plan?.request.thresholds;
    final thresholds = existing ?? EnduranceController.suggestedThresholds(settings.profile, settings.season);
    _fields = ThresholdFields(thresholds);
    final today = CalendarDay.today();
    final profile = settings.profile;
    _known = EnduranceGoals.known(profile, settings.season, today: today);
    final preferred = widget.goal ?? _known.where((goal) => goal.event != null).firstOrNull ?? _known.firstOrNull;
    final suggestion = EnduranceGoals.suggestion(
      profile,
      settings.season,
      username: ref.read(currentUserProvider).username,
      today: today,
      thresholds: thresholds,
      goal: preferred,
    );
    _goal = preferred;
    _mode = preferred == null ? PlanningMode.period : PlanningMode.goal;
    if (preferred != null) _applyGoal(preferred);
    _sports
      ..clear()
      ..addAll(suggestion.sports);
    _days
      ..clear()
      ..addAll(suggestion.days);
    _longDay = _days.contains(suggestion.longDay)
        ? suggestion.longDay
        : Weekday.values.lastWhere(_days.contains, orElse: () => suggestion.longDay);
    _hours = (suggestion.weeklyMinutes / 60).clamp(1, 20).toDouble();
    _focus = suggestion.focus;
    _basis = EnduranceGoals.explanation(profile, today: today, goal: preferred);
  }

  void _applyGoal(KnownGoal goal) {
    _goal = goal;
    if (goal.event case final event?) _event = event;
    _eventDay = goal.day;
    _target.text = switch (goal.targetMinutes) {
      final minutes? => '${minutes ~/ 60}:${(minutes % 60).toString().padLeft(2, '0')}',
      null => '',
    };
  }

  @override
  void dispose() {
    _target.dispose();
    _fields.dispose();
    super.dispose();
  }

  Future<void> _pickDay() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _eventDay.referenceDate.toLocal(),
      firstDate: now,
      lastDate: now.add(const Duration(days: 7 * 52)),
      locale: const Locale('de', 'DE'),
    );
    if (picked != null) setState(() => _eventDay = CalendarDay.fromDate(picked));
  }

  Future<void> _create() async {
    final (thresholds, thresholdError) = _fields.read();
    int? target;
    if (_target.text.trim().isNotEmpty) {
      final match = RegExp(r'^\s*(\d{1,2}):(\d{2})\s*$').firstMatch(_target.text);
      target = match == null ? null : int.parse(match.group(1)!) * 60 + int.parse(match.group(2)!);
      if (target == null || target <= 0) {
        setState(() => _error = 'Zielzeit bitte als h:mm angeben (z. B. 1:45).');
        return;
      }
    }
    if (thresholds == null) {
      setState(() => _error = thresholdError);
      return;
    }
    final days = Weekday.values.where(_days.contains).toList();
    final request = TrainingPlanRequest(
      username: ref.read(currentUserProvider).username,
      mode: _mode,
      sports: EnduranceSport.values.where(_sports.contains).toList(),
      start: CalendarDay.today(),
      weeklyMinutes: (_hours * 60).round(),
      days: days,
      longDay: _days.contains(_longDay) ? _longDay : (days.isEmpty ? _longDay : days.last),
      weeks: _weeks,
      focus: _focus,
      event: _mode == PlanningMode.goal ? _event : null,
      eventDay: _mode == PlanningMode.goal ? _eventDay : null,
      eventName: _mode == PlanningMode.goal ? _goal?.name : null,
      targetMinutes: _mode == PlanningMode.goal ? target : null,
      thresholds: thresholds,
    );
    if (TrainingPlanEngine.validate(request) case final error?) {
      setState(() => _error = error);
      return;
    }
    setState(() => _saving = true);
    await ref.read(enduranceControllerProvider).create(request);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final eventSports = _mode == PlanningMode.goal ? _event.sports.toSet() : <EnduranceSport>{};
    final trainingDays = Weekday.values.where(_days.contains).toList();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Plan erstellen'),
        actions: [TextButton(onPressed: _saving ? null : () => unawaited(_create()), child: const Text('Erstellen'))],
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          FormSection(
            children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: SegmentedButton<PlanningMode>(
                  segments: [
                    for (final mode in PlanningMode.values) ButtonSegment(value: mode, label: Text(mode.label)),
                  ],
                  selected: {_mode},
                  onSelectionChanged: (value) => setState(() => _mode = value.single),
                ),
              ),
            ],
          ),
          FormSection(
            footer: 'Vorgaben aus deinen Zielen und deinem Wochenplan – alles lässt sich ändern. $_basis',
            children: const [],
          ),
          if (_mode == PlanningMode.goal) ...[
            if (_known.isNotEmpty)
              FormSection(
                header: 'Deine Wettkämpfe',
                footer: 'Aus der Einrichtung bzw. deinem Saisonplan. Ändern unter Einstellungen › Profil.',
                children: [
                  for (final goal in _known)
                    ListTile(
                      leading: Icon(
                        _goal?.id == goal.id ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                        color: _goal?.id == goal.id ? Theme.of(context).colorScheme.primary : null,
                      ),
                      title: Text(goal.name),
                      subtitle: Text(
                        [
                          GermanFormat.date(goal.day),
                          goal.event?.label ?? 'Art bitte unten wählen',
                          if (goal.targetMinutes case final minutes?)
                            'Ziel ${minutes ~/ 60}:${(minutes % 60).toString().padLeft(2, '0')} h',
                          goal.source,
                        ].join(' · '),
                      ),
                      onTap: () => setState(() => _applyGoal(goal)),
                    ),
                  ListTile(
                    leading: Icon(
                      _goal == null ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                      color: _goal == null ? Theme.of(context).colorScheme.primary : null,
                    ),
                    title: const Text('Anderes Ziel'),
                    onTap: () => setState(() => _goal = null),
                  ),
                ],
              ),
            FormSection(
              header: _goal == null ? 'Ziel' : null,
              footer:
                  'Der Plan läuft vom heutigen Tag bis zum Wettkampf: Grundlage, Aufbau, Spitze, Tapering. Ohne '
                  'Zielzeit plant er mit einer üblichen Dauer.',
              children: [
                if (_goal == null || _goal!.event == null)
                  _Choice<EnduranceEvent>(
                    key: ValueKey('event-${_goal?.id}'),
                    label: 'Art des Wettkampfs',
                    value: _event,
                    items: [
                      for (final event in EnduranceEvent.values)
                        DropdownMenuItem(value: event, child: Text(event.label)),
                    ],
                    onChanged: (value) => setState(() => _event = value ?? _event),
                  ),
                if (_goal == null)
                  ListTile(title: const Text('Datum'), trailing: Text(GermanFormat.date(_eventDay)), onTap: _pickDay),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  child: TextField(
                    controller: _target,
                    keyboardType: TextInputType.datetime,
                    decoration: const InputDecoration(labelText: 'Zielzeit (h:mm, optional)', border: InputBorder.none),
                  ),
                ),
              ],
            ),
          ] else
            FormSection(
              header: 'Zeitraum',
              children: [
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: SegmentedButton<int>(
                    segments: const [
                      ButtonSegment(value: 4, label: Text('4 Wochen')),
                      ButtonSegment(value: 8, label: Text('8 Wochen')),
                      ButtonSegment(value: 12, label: Text('12 Wochen')),
                    ],
                    selected: {_weeks},
                    onSelectionChanged: (value) => setState(() => _weeks = value.single),
                  ),
                ),
                _Choice<PeriodFocus>(
                  label: 'Schwerpunkt',
                  value: _focus,
                  items: [
                    for (final focus in PeriodFocus.values) DropdownMenuItem(value: focus, child: Text(focus.label)),
                  ],
                  onChanged: (value) => setState(() => _focus = value ?? _focus),
                ),
              ],
            ),
          FormSection(
            header: 'Disziplinen',
            footer: eventSports.isEmpty ? null : 'Die Disziplinen des Wettkampfs sind immer dabei.',
            children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: FlowChips<EnduranceSport>(
                  items: EnduranceSport.values,
                  label: (sport) => sport.label,
                  isSelected: (sport) => _sports.contains(sport) || eventSports.contains(sport),
                  onToggle: (sport) => setState(() {
                    if (!_sports.remove(sport)) _sports.add(sport);
                  }),
                ),
              ),
            ],
          ),
          FormSection(
            header: 'Trainingstage',
            children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: FlowChips<Weekday>(
                  items: Weekday.values,
                  label: (day) => day.short,
                  isSelected: _days.contains,
                  onToggle: (day) => setState(() {
                    if (!_days.remove(day)) _days.add(day);
                    // Die lange Einheit liegt immer auf einem Trainingstag: fällt ihr Tag weg, rückt sie auf den
                    // letzten gewählten Tag der Woche.
                    if (!_days.contains(_longDay)) {
                      _longDay = Weekday.values.lastWhere(_days.contains, orElse: () => _longDay);
                    }
                  }),
                ),
              ),
              // Nur die gewählten Trainingstage stehen zur Wahl (vorher alle sieben).
              if (trainingDays.isEmpty)
                const ListTile(title: Text('Lange Einheit'), subtitle: Text('Erst Trainingstage wählen.'))
              else
                _Choice<Weekday>(
                  // Neu aufbauen, wenn sich Tage oder Auswahl ändern (das Feld merkt sich sonst seinen Startwert).
                  key: ValueKey('long-${_longDay.index}-${trainingDays.map((day) => day.index).join(',')}'),
                  label: 'Lange Einheit',
                  value: _longDay,
                  items: [for (final day in trainingDays) DropdownMenuItem(value: day, child: Text(day.long))],
                  onChanged: (value) => setState(() => _longDay = value ?? _longDay),
                ),
              ListTile(
                title: const Text('Zeit je Woche'),
                subtitle: Slider(
                  value: _hours,
                  min: 1,
                  max: 20,
                  divisions: 38,
                  onChanged: (value) => setState(() => _hours = value),
                ),
                trailing: Text('${GermanFormat.decimal(_hours)} h'),
              ),
            ],
          ),
          FormSection(
            header: 'Schwellenwerte',
            footer:
                _error ??
                'Daraus werden die Ziele je Schritt: Pace, Watt bzw. Puls. Leer lassen geht – dann gibt es nur Zonen.',
            children: _fields.widgets(),
          ),
        ],
      ),
    );
  }
}

/// Freie Einheit, unabhängig vom Plan: zusammenstellen und exportieren.
class AdHocWorkoutScreen extends ConsumerStatefulWidget {
  const AdHocWorkoutScreen({super.key});

  @override
  ConsumerState<AdHocWorkoutScreen> createState() => _AdHocWorkoutScreenState();
}

class _AdHocWorkoutScreenState extends ConsumerState<AdHocWorkoutScreen> {
  EnduranceSport _sport = EnduranceSport.bike;
  EnduranceWorkoutType _type = EnduranceWorkoutType.threshold;
  int _minutes = 60;
  CalendarDay _day = CalendarDay.today();

  static const _types = [
    EnduranceWorkoutType.recovery,
    EnduranceWorkoutType.endurance,
    EnduranceWorkoutType.long,
    EnduranceWorkoutType.tempo,
    EnduranceWorkoutType.threshold,
    EnduranceWorkoutType.vo2max,
  ];

  @override
  Widget build(BuildContext context) {
    final controller = ref.watch(enduranceControllerProvider);
    final settings = ref.watch(coachSettingsProvider);
    final thresholds =
        controller.plan?.request.thresholds ??
        EnduranceController.suggestedThresholds(settings.profile, settings.season);
    final workout = EnduranceWorkouts.build(sport: _sport, type: _type, minutes: _minutes, thresholds: thresholds);
    return Scaffold(
      appBar: AppBar(title: const Text('Einzelne Einheit')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          FormSection(
            children: [
              _Choice<EnduranceSport>(
                label: 'Disziplin',
                value: _sport,
                items: [
                  for (final sport in EnduranceSport.values) DropdownMenuItem(value: sport, child: Text(sport.label)),
                ],
                onChanged: (value) => setState(() => _sport = value ?? _sport),
              ),
              _Choice<EnduranceWorkoutType>(
                label: 'Art',
                value: _type,
                items: [for (final type in _types) DropdownMenuItem(value: type, child: Text(type.label))],
                onChanged: (value) => setState(() => _type = value ?? _type),
              ),
              ListTile(
                title: const Text('Dauer'),
                subtitle: Slider(
                  value: _minutes.toDouble(),
                  min: 20,
                  max: 240,
                  divisions: 44,
                  onChanged: (value) => setState(() => _minutes = value.round()),
                ),
                trailing: Text('$_minutes min'),
              ),
              ListTile(
                title: const Text('Tag'),
                trailing: Text(GermanFormat.date(_day)),
                onTap: () async {
                  final now = DateTime.now();
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: now,
                    firstDate: now,
                    lastDate: now.add(const Duration(days: 365)),
                    locale: const Locale('de', 'DE'),
                  );
                  if (picked != null) setState(() => _day = CalendarDay.fromDate(picked));
                },
              ),
            ],
          ),
          WorkoutDetailSections(
            key: ValueKey('${_sport.name}-${_type.name}-$_minutes-${_day.iso}'),
            workout: workout,
            day: _day,
            onSend: () => controller.sendAdHoc(workout, _day),
          ),
        ],
      ),
    );
  }
}

/// Auswahl über die ganze Breite (lange Einträge wie „Triathlon Mitteldistanz“ passen nicht neben einen Titel).
class _Choice<T> extends StatelessWidget {
  const _Choice({required this.label, required this.value, required this.items, required this.onChanged, super.key});

  final String label;
  final T value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?> onChanged;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    child: DropdownButtonFormField<T>(
      initialValue: value,
      isExpanded: true,
      items: items,
      onChanged: onChanged,
      decoration: InputDecoration(labelText: label, border: InputBorder.none),
    ),
  );
}
