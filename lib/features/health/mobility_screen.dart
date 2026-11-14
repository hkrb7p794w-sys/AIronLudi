import 'dart:async';

import 'package:coach_core/coach_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/settings/coach_settings.dart';
import '../../data/storage.dart';
import '../../services/providers.dart';
import '../../ui/components.dart';
import '../evidence/evidence_views.dart';

/// Mobility-Einstellungen ändern und neu zuweisen (die Setter speichern).
void changeMobility(CoachSettings settings, void Function(MobilitySettings mobility) change) {
  final mobility = settings.mobility;
  change(mobility);
  settings.mobility = mobility;
}

Color mobilityColor(MobilityRating rating) => switch (rating) {
  MobilityRating.limited => Colors.orange,
  MobilityRating.moderate => Colors.amber,
  MobilityRating.good => Colors.green,
};

/// Mobility: Einheit nach Belastung der letzten Tage und eigenen Selbsttests, dazu die Tests mit Verlauf. Die Auswahl
/// trifft `MobilityPlanner` (Regeln), keine KI (Port von `MobilityView`).
class MobilityScreen extends ConsumerStatefulWidget {
  const MobilityScreen({super.key});

  static int minutes(int seconds) => (seconds / 60).round().clamp(1, 1 << 30);

  static String detail(MobilityBlock block) {
    final drill = block.drill;
    final time = '${drill.seconds} s${drill.perSide ? ' je Seite' : ''}';
    final style = drill.style == DrillStyle.hold ? 'halten' : 'in Bewegung';
    return '$time · $style · ${block.area.label}';
  }

  /// Neuer Eintrag, Verlauf höchstens ein Jahr.
  static List<MobilityLogEntry> appending(MobilityLogEntry entry, List<MobilityLogEntry> log, CalendarDay today) {
    final cutoff = today.adding(-365);
    return [
      for (final item in log)
        if (item.day >= cutoff) item,
      entry,
    ];
  }

  @override
  ConsumerState<MobilityScreen> createState() => _MobilityScreenState();
}

class _MobilityScreenState extends ConsumerState<MobilityScreen> {
  MobilityContext _context = MobilityContext.restDay;
  List<GymSession> _sessions = const [];
  List<GarminActivity> _activities = const [];

  @override
  void initState() {
    super.initState();
    unawaited(_reload());
  }

  Future<void> _reload() async {
    final results = await (ref.read(gymRepositoryProvider).all(), ref.read(activityRepositoryProvider).all()).wait;
    if (!mounted) return;
    final sessions = [for (final record in results.$1) record.session]..sort((a, b) => b.start.compareTo(a.start));
    final activities = [...results.$2]..sort((a, b) => (a.startLocal ?? '').compareTo(b.startLocal ?? ''));
    setState(() {
      _sessions = sessions.take(30).toList();
      _activities = activities.length > 60 ? activities.sublist(activities.length - 60) : activities;
    });
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(coachSettingsProvider);
    final mobility = settings.mobility;
    final today = CalendarDay.today();
    final routine = MobilityPlanner.routine(
      context: _context,
      minutes: mobility.minutes,
      recentSets: MobilityPlanner.recentSets(_sessions, now: DateTime.now(), custom: settings.gym.customExercises),
      enduranceMinutes: MobilityPlanner.enduranceMinutes(_activities, today: today),
      results: mobility.results,
      complaints: mobility.complaints,
    );
    final doneToday = mobility.log.any((entry) => entry.day == today);
    final latest = MobilityTestResult.latest(mobility.results);
    final secondary = Theme.of(context).colorScheme.onSurfaceVariant;
    final total = MobilityScreen.minutes(routine.totalSeconds);
    return Scaffold(
      appBar: AppBar(title: const Text('Mobility')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          FormSection(
            footer: _context == MobilityContext.preTraining
                ? 'Vor dem Training nur Übungen in Bewegung – langes Halten direkt davor kann die Leistung kurz mindern.'
                : 'Nach dem Training und am Ruhetag zuerst Halteübungen, je etwa 45 Sekunden.',
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: DropdownButtonFormField<MobilityContext>(
                  initialValue: _context,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Wann'),
                  items: [
                    for (final context in MobilityContext.values)
                      DropdownMenuItem(value: context, child: Text(context.label)),
                  ],
                  onChanged: (value) => setState(() => _context = value ?? _context),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(12),
                child: SizedBox(
                  width: double.infinity,
                  child: SegmentedButton<int>(
                    segments: [
                      for (final minutes in MobilityPlanner.durations)
                        ButtonSegment(value: minutes, label: Text('$minutes min')),
                    ],
                    selected: {mobility.minutes},
                    showSelectedIcon: false,
                    onSelectionChanged: (selection) =>
                        changeMobility(settings, (mobility) => mobility.minutes = selection.first),
                  ),
                ),
              ),
            ],
          ),
          FormSection(
            header: 'Schwerpunkte heute',
            children: [for (final reason in routine.reasons) ListTile(dense: true, title: Text(reason))],
          ),
          FormSection(
            header: 'Ablauf · etwa $total min',
            children: [
              for (final block in routine.blocks)
                ExpansionTile(
                  title: Text(block.drill.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text(MobilityScreen.detail(block)),
                  expandedAlignment: Alignment.centerLeft,
                  childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  children: [
                    for (final (index, step) in block.drill.steps.indexed)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text('${index + 1}. $step', style: const TextStyle(fontSize: 13)),
                      ),
                  ],
                ),
            ],
          ),
          FormSection(
            footer: 'Diese Woche: ${mobility.sessions(inWeekEnding: today)} Mobility-Einheiten',
            children: [
              ListTile(
                enabled: !doneToday,
                leading: Icon(doneToday ? Icons.check_circle : Icons.check_circle_outline),
                title: Text(doneToday ? 'Heute erledigt' : 'Als erledigt eintragen'),
                onTap: () => changeMobility(
                  settings,
                  (mobility) => mobility.log = MobilityScreen.appending(
                    MobilityLogEntry(day: today, minutes: total, areas: routine.focus),
                    mobility.log,
                    today,
                  ),
                ),
              ),
            ],
          ),
          FormSection(
            header: 'Selbsttests',
            footer:
                'Etwa alle vier Wochen wiederholen. Eingeschränkte Bereiche bekommen in der Einheit Vorrang. Die Grenzen '
                'sind Orientierungswerte, keine Diagnose – bei Schmerzen ärztlich abklären lassen.',
            children: [
              for (final test in MobilityTest.all)
                ListTile(
                  title: Text(test.name),
                  subtitle: Text(test.areas.map((area) => area.label).join(', ')),
                  trailing: switch (latest[test.id]) {
                    final result? => Text(
                      test.rating(result.value).label,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: mobilityColor(test.rating(result.value)),
                      ),
                    ),
                    null => Text('noch nicht getestet', style: TextStyle(fontSize: 12, color: secondary)),
                  },
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(fullscreenDialog: true, builder: (_) => MobilityTestScreen(test: test)),
                  ),
                ),
            ],
          ),
          FormSection(
            header: 'Beschwerden',
            footer:
                'Diese Bereiche bekommen in der Mobility-Einheit Vorrang, Krafttraining-Übungen, die sie belasten, zeigen '
                'einen Hinweis, und der KI-Coach berücksichtigt sie. Keine Diagnose – bei anhaltenden oder starken '
                'Schmerzen ärztlich abklären lassen.',
            children: [
              for (final area in ComplaintArea.values)
                SwitchListTile(
                  title: Text(area.label),
                  value: mobility.complaints.contains(area),
                  onChanged: (on) => changeMobility(settings, (mobility) {
                    final complaints = {...mobility.complaints.where((item) => item != area), if (on) area};
                    mobility.complaints = [
                      for (final item in ComplaintArea.values)
                        if (complaints.contains(item)) item,
                    ];
                  }),
                ),
            ],
          ),
          const FormSection(
            children: [
              EvidenceDisclosure(ruleIDs: ['mobility.stretching', 'mobility.focus']),
            ],
          ),
        ],
      ),
    );
  }
}

/// Ein Selbsttest: Anleitung, Eingabe, bisherige Ergebnisse (Port von `MobilityTestSheet`).
class MobilityTestScreen extends ConsumerStatefulWidget {
  const MobilityTestScreen({super.key, required this.test});

  final MobilityTest test;

  static String text(double value, MobilityTest test) => switch (test.input) {
    MobilityCentimeters() => '${value.toInt()} cm',
    MobilityLevels(:final levels) => 'Stufe ${value.toInt() + 1} von ${levels.length}',
  };

  @override
  ConsumerState<MobilityTestScreen> createState() => _MobilityTestScreenState();
}

class _MobilityTestScreenState extends ConsumerState<MobilityTestScreen> {
  late double _value = _initial();

  double _initial() {
    final history = _history();
    if (history.isNotEmpty) return history.first.value;
    return switch (widget.test.input) {
      MobilityCentimeters(:final lower, :final upper) => 0.0.clamp(lower, upper),
      MobilityLevels() => 0,
    };
  }

  List<MobilityTestResult> _history() => [
    for (final result in ref.read(coachSettingsProvider).mobility.results)
      if (result.testID == widget.test.id) result,
  ]..sort((a, b) => b.day.compareTo(a.day));

  @override
  Widget build(BuildContext context) {
    ref.watch(coachSettingsProvider);
    final test = widget.test;
    final history = _history();
    final rating = test.rating(_value);
    return Scaffold(
      appBar: AppBar(
        title: Text(test.name),
        leading: TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Abbrechen')),
        leadingWidth: 100,
        actions: [
          TextButton(
            onPressed: () {
              changeMobility(
                ref.read(coachSettingsProvider),
                (mobility) => mobility.results = [
                  ...mobility.results,
                  MobilityTestResult(testID: test.id, day: CalendarDay.today(), value: _value),
                ],
              );
              Navigator.of(context).pop();
            },
            child: const Text('Speichern'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          FormSection(
            header: 'So geht’s',
            children: [
              for (final (index, step) in test.steps.indexed) ListTile(dense: true, title: Text('${index + 1}. $step')),
            ],
          ),
          FormSection(
            header: 'Ergebnis',
            children: [
              switch (test.input) {
                MobilityCentimeters(:final lower, :final upper) => ListTile(
                  title: Text('${_value.toInt()} cm'),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: 'Weniger',
                        icon: const Icon(Icons.remove),
                        onPressed: _value > lower ? () => setState(() => _value -= 1) : null,
                      ),
                      IconButton(
                        tooltip: 'Mehr',
                        icon: const Icon(Icons.add),
                        onPressed: _value < upper ? () => setState(() => _value += 1) : null,
                      ),
                    ],
                  ),
                ),
                MobilityLevels(:final levels) => RadioGroup<int>(
                  groupValue: _value.toInt(),
                  onChanged: (value) => setState(() => _value = (value ?? 0).toDouble()),
                  child: Column(
                    children: [
                      for (final (index, label) in levels.indexed) RadioListTile<int>(value: index, title: Text(label)),
                    ],
                  ),
                ),
              },
              ListTile(
                dense: true,
                title: Text('Einstufung: ${rating.label}', style: TextStyle(color: mobilityColor(rating))),
              ),
            ],
          ),
          if (history.isNotEmpty)
            FormSection(
              header: 'Bisher',
              children: [
                for (final result in history.take(6))
                  ListTile(
                    dense: true,
                    title: Text(GermanFormat.date(result.day)),
                    trailing: Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(text: MobilityTestScreen.text(result.value, test)),
                          TextSpan(
                            text: '  ${test.rating(result.value).label}',
                            style: TextStyle(fontSize: 12, color: mobilityColor(test.rating(result.value))),
                          ),
                        ],
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

/// Karte im Gesundheitsbereich (Port von `MobilitySummaryCard`).
class MobilitySummary extends ConsumerWidget {
  const MobilitySummary({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mobility = ref.watch(coachSettingsProvider).mobility;
    final count = mobility.sessions(inWeekEnding: CalendarDay.today());
    final tested = mobility.results.isNotEmpty;
    final secondary = Theme.of(context).colorScheme.onSurfaceVariant;
    return Row(
      spacing: 12,
      children: [
        const Icon(Icons.self_improvement, color: Colors.teal, size: 28),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 2,
            children: [
              const Text('Mobility', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
              Text(
                '${count == 0 ? 'Diese Woche noch keine Einheit' : 'Diese Woche $count Einheiten'}'
                '${tested ? '' : ' · Selbsttests noch offen'}',
                style: TextStyle(fontSize: 13, color: secondary),
              ),
            ],
          ),
        ),
        Icon(Icons.chevron_right, color: secondary),
      ],
    );
  }
}
