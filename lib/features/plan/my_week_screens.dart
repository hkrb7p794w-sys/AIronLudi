part of 'my_week_screen.dart';

/// Training ohne Uhr nachtragen: Sportart, Zeitpunkt, Dauer, Anstrengung 1–10 (daraus die Belastung). Schließt mit
/// `true`, wenn gespeichert wurde (Port von `ManualActivitySheet`).
class ManualActivityScreen extends ConsumerStatefulWidget {
  const ManualActivityScreen({super.key, this.sport = TrainingSport.run, this.day, this.minutes = 45});

  final TrainingSport sport;
  final CalendarDay? day;
  final int minutes;

  @override
  ConsumerState<ManualActivityScreen> createState() => _ManualActivityScreenState();
}

class _ManualActivityScreenState extends ConsumerState<ManualActivityScreen> {
  late TrainingSport _sport = widget.sport;
  late DateTime _start = switch (widget.day) {
    final day? => DateTime(day.year, day.month, day.day, 18),
    null => DateTime.now().subtract(const Duration(hours: 1)),
  };
  late int _minutes = widget.minutes;
  int _effort = 5;
  final _name = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  static String effortLabel(int effort) => switch (effort) {
    <= 2 => 'sehr leicht',
    <= 4 => 'leicht',
    <= 6 => 'mittel',
    <= 8 => 'hart',
    _ => 'maximal',
  };

  Future<void> _pickStart() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: _start.isAfter(now) ? now : _start,
      firstDate: now.subtract(const Duration(days: 365)),
      lastDate: now,
      locale: const Locale('de', 'DE'),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(_start));
    if (!mounted) return;
    var picked = DateTime(date.year, date.month, date.day, time?.hour ?? _start.hour, time?.minute ?? _start.minute);
    if (picked.isAfter(now)) picked = now;
    setState(() => _start = picked);
  }

  Future<void> _save() async {
    final activity = ManualActivity.make(
      sport: _sport,
      start: _start.isAfter(DateTime.now()) ? DateTime.now() : _start,
      minutes: _minutes,
      effort: _effort,
      name: _name.text.trim(),
    );
    await ref.read(activityRepositoryProvider).upsert(activity);
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    String two(int value) => value.toString().padLeft(2, '0');
    final load = ManualActivity.estimatedLoad(minutes: _minutes, effort: _effort).round();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Training nachtragen'),
        leading: BarTextButton('Abbrechen', onPressed: () => Navigator.of(context).pop(false)),
        leadingWidth: 100,
        actions: [TextButton(onPressed: _save, child: const Text('Sichern'))],
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          FormSection(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: DropdownButtonFormField<TrainingSport>(
                  initialValue: _sport,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Sportart'),
                  items: [
                    for (final sport in TrainingSport.values)
                      DropdownMenuItem(
                        value: sport,
                        child: Text(sport.label, overflow: TextOverflow.ellipsis),
                      ),
                  ],
                  onChanged: (sport) => setState(() => _sport = sport ?? _sport),
                ),
              ),
              ListTile(
                title: const Text('Beginn'),
                trailing: Text(
                  '${GermanFormat.date(CalendarDay.fromDate(_start))}, ${two(_start.hour)}:${two(_start.minute)}',
                ),
                onTap: _pickStart,
              ),
              ListTile(
                title: Text('$_minutes min'),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: 'Weniger',
                      icon: const Icon(Icons.remove),
                      onPressed: _minutes > 5 ? () => setState(() => _minutes -= 5) : null,
                    ),
                    IconButton(
                      tooltip: 'Mehr',
                      icon: const Icon(Icons.add),
                      onPressed: _minutes < 600 ? () => setState(() => _minutes += 5) : null,
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: TextField(
                  controller: _name,
                  decoration: const InputDecoration(labelText: 'Bezeichnung (optional)'),
                ),
              ),
            ],
          ),
          FormSection(
            footer:
                'Belastung ≈ $load (Minuten × Anstrengung, „session RPE“). Ohne Uhr gibt es keine Herzfrequenz; die '
                'Einheit zählt trotzdem für Wochenplan und Belastung.',
            children: [
              ListTile(title: const Text('Anstrengung'), trailing: Text('$_effort – ${effortLabel(_effort)}')),
              Slider(
                value: _effort.toDouble(),
                min: 1,
                max: 10,
                divisions: 9,
                label: '$_effort',
                onChanged: (value) => setState(() => _effort = value.round()),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Wochenplan bearbeiten, mit Hinweisen und dem Zugang zum Profil (Port von `ScheduleEditorSheet`).
class ScheduleEditorScreen extends ConsumerWidget {
  const ScheduleEditorScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(coachSettingsProvider);
    final profile = settings.profile;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Wochenplan'),
        automaticallyImplyLeading: false,
        actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Fertig'))],
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          FormSection(
            footer: 'Tippe auf eine Einheit, um die Intensität zu ändern oder sie zu entfernen.',
            children: [
              ScheduleEditor(
                schedule: profile.schedule,
                sports: profile.sports,
                highlight: Weekday.of(CalendarDay.today()),
                onChanged: (schedule) => settings.profile = settings.profile..schedule = schedule,
              ),
            ],
          ),
          ScheduleHintsSection(hints: ScheduleCheck.hints(profile.schedule, profile)),
          FormSection(
            children: [
              ListTile(
                title: const Text('Sportarten, Ziel und Körperdaten ändern'),
                textColor: Theme.of(context).colorScheme.primary,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    fullscreenDialog: true,
                    builder: (_) => OnboardingScreen(isEditing: true, initial: settings.profile),
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

/// „Nächste Woche planen“ (Sonntags-Erinnerung oder Plan): eigener Wochenplan nur für diese Woche anpassen bzw. im
/// Saisonplan die Einheiten der nächsten Woche mit Ausrüstung (Port von `NextWeekPlanSheet`).
class NextWeekPlanScreen extends ConsumerStatefulWidget {
  const NextWeekPlanScreen({super.key, this.monday, this.initial});

  /// Andere Woche (Montag), z. B. „Anpassen“ bei einem Vorschlag; Standard ist die nächste Woche.
  final CalendarDay? monday;

  /// Vorbelegung statt des aktuellen Plans der Woche (der Vorschlag).
  final WeekSchedule? initial;

  @override
  ConsumerState<NextWeekPlanScreen> createState() => _NextWeekPlanScreenState();
}

class _NextWeekPlanScreenState extends ConsumerState<NextWeekPlanScreen> {
  late final CalendarDay _monday = widget.monday ?? PlanAdjustments.monday(CalendarDay.today()).adding(7);
  late WeekSchedule _schedule = widget.initial ?? ref.read(coachSettingsProvider).schedule(_monday);

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(coachSettingsProvider);
    final personal = settings.profile.mode == ProfileMode.personal;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.monday == null ? 'Nächste Woche planen' : 'Woche anpassen'),
        automaticallyImplyLeading: false,
        leading: personal
            ? TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Abbrechen'))
            : null,
        leadingWidth: personal ? 100 : null,
        actions: [
          if (personal)
            TextButton(
              onPressed: () {
                settings.planAdjustments = settings.planAdjustments
                  ..setWeekPlan(_schedule, base: settings.profile.schedule, inWeekOf: _monday);
                Navigator.of(context).pop();
              },
              child: const Text('Sichern'),
            )
          else
            TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Fertig')),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          FormSection(
            children: [
              ListTile(
                title: Text(
                  'Woche ab ${GermanFormat.date(_monday)}',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          if (personal) ..._personal(settings) else ..._season(settings),
        ],
      ),
    );
  }

  List<Widget> _personal(CoachSettings settings) {
    final profile = settings.profile;
    return [
      FormSection(
        footer:
            'Gilt nur für diese Woche – Termine, Urlaub oder Wetter. Dein Wochenplan bleibt unverändert; die '
            'Erinnerungen richten sich nach diesem Plan.',
        children: [
          ScheduleEditor(
            schedule: _schedule,
            sports: profile.sports,
            onChanged: (schedule) => setState(() => _schedule = schedule),
          ),
        ],
      ),
      ScheduleHintsSection(hints: ScheduleCheck.hints(_schedule, profile)),
      if (_schedule != profile.schedule)
        FormSection(
          children: [
            ListTile(
              leading: const Icon(Icons.undo),
              title: const Text('Wie im Wochenplan'),
              onTap: () => setState(() => _schedule = profile.schedule),
            ),
          ],
        ),
    ];
  }

  List<Widget> _season(CoachSettings settings) {
    final plan = ref.read(seasonScheduleProvider);
    final week = plan?.week(_monday);
    if (plan == null || week == null) {
      return [
        const FormSection(children: [ListTile(title: Text('Für die nächste Woche gibt es keinen Saisonplan mehr.'))]),
      ];
    }
    final units = plan.units(week, config: settings.season, decisions: settings.competitionDecisions);
    final equipment = SwimStepText.equipment(week.ss ?? const []);
    return [
      FormSection(
        header: 'Einheiten · ${week.ph}',
        footer: week.f.isEmpty ? null : week.f,
        children: [
          for (final unit in units)
            ListTile(
              title: Text(unit.title, style: const TextStyle(fontWeight: FontWeight.w500)),
              subtitle: unit.detail.isEmpty ? null : Text(unit.detail),
            ),
        ],
      ),
      if (equipment.isNotEmpty)
        FormSection(
          header: 'Fürs Schwimmen einpacken',
          children: [ListTile(leading: const Icon(Icons.shopping_bag_outlined), title: Text(equipment.join(', ')))],
        ),
    ];
  }
}

bool _onOrAfter(CalendarDay? day, CalendarDay monday) => day != null && day >= monday;
