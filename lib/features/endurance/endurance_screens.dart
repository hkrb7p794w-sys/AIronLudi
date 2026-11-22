import 'dart:async';
import 'dart:io';

import 'package:coach_core/coach_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../app/user_providers.dart';
import '../../services/endurance/workout_exporter_service.dart';
import '../../services/providers.dart';
import '../../ui/components.dart';
import '../routes/route_for_slot.dart';
import 'endurance_controller.dart';

/// „4:30“ bzw. „1:50“ in Sekunden; `null` bei leerer oder ungültiger Eingabe.
int? parseClock(String text) {
  final match = RegExp(r'^\s*(\d{1,2}):(\d{2})\s*$').firstMatch(text);
  if (match == null) return null;
  final seconds = int.parse(match.group(2)!);
  if (seconds >= 60) return null;
  return int.parse(match.group(1)!) * 60 + seconds;
}

String clockText(int seconds) => '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';

String _weekdayDate(CalendarDay day) => '${Weekday.values[day.weekdayIndex].short} ${GermanFormat.date(day)}';

Color _phaseColor(EndurancePhase phase) => switch (phase) {
  EndurancePhase.base => Colors.blue,
  EndurancePhase.build => Colors.orange,
  EndurancePhase.peak => Colors.red,
  EndurancePhase.taper => Colors.teal,
  EndurancePhase.recovery => Colors.green,
  EndurancePhase.race => Colors.purple,
};

Color _sportColor(EnduranceSport sport) => switch (sport) {
  EnduranceSport.run => Colors.orange,
  EnduranceSport.bike => Colors.green,
  EnduranceSport.swim => Colors.blue,
};

void _push(BuildContext context, Widget Function(BuildContext) builder) =>
    unawaited(Navigator.of(context).push(MaterialPageRoute<void>(builder: builder)));

/// Übersicht des Ausdauerplans im Reiter Training.
class EnduranceScreen extends ConsumerStatefulWidget {
  const EnduranceScreen({super.key});

  @override
  ConsumerState<EnduranceScreen> createState() => _EnduranceScreenState();
}

class _EnduranceScreenState extends ConsumerState<EnduranceScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(ref.read(enduranceControllerProvider).refresh());
    });
  }

  @override
  Widget build(BuildContext context) {
    final controller = ref.watch(enduranceControllerProvider);
    ref.watch(coachSettingsProvider); // Ziele und Wettkämpfe aus dem Profil
    final plan = controller.plan;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Ausdauerplan'),
        actions: [
          if (controller.isBusy)
            const Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
            ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          await ref.read(appModelProvider).syncNow();
          await controller.refresh();
        },
        child: plan == null ? _empty(context, controller) : _plan(context, controller, plan),
      ),
    );
  }

  Widget _empty(BuildContext context, EnduranceController controller) => ListView(
    padding: const EdgeInsets.only(bottom: 32),
    children: [
      FormSection(
        footer:
            'Plan für Laufen, Rad (auch Zwift) und Schwimmen – auf einen Wettkampf hin (mit Aufbau, Spitze und '
            'Tapering) oder für einen Zeitraum. Kommende Einheiten passen sich an absolvierte Trainings, ausgefallene '
            'Einheiten und deine Erholungswerte an.',
        children: [
          ListTile(
            leading: const SportIcon(symbol: 'figure.run', color: Colors.orange),
            title: const Text('Plan erstellen'),
            subtitle: switch (_nextGoal()) {
              final goal? => Text('Für ${goal.name} am ${GermanFormat.date(goal.day)}'),
              null => const Text('Passend zu deinen Zielen und deinem Wochenplan'),
            },
            trailing: const DisclosureChevron(),
            onTap: () => _push(context, (_) => const EndurancePlanSetupScreen()),
          ),
        ],
      ),
      if (controller.hasForeignPlan)
        const FormSection(
          children: [
            ListTile(title: Text('Der gespeicherte Plan gehört einem anderen Benutzer und wird nicht angezeigt.')),
          ],
        ),
      FormSection(
        children: [
          ListTile(
            title: const Text('Einzelne Einheit exportieren'),
            subtitle: const Text('An die Uhr senden, FIT-Datei oder Zwift-Workout'),
            trailing: const DisclosureChevron(),
            onTap: () => _push(context, (_) => const AdHocWorkoutScreen()),
          ),
        ],
      ),
    ],
  );

  Widget _plan(BuildContext context, EnduranceController controller, EndurancePlan plan) {
    final today = controller.today;
    final week = plan.weekOf(today) ?? (today < plan.firstDay ? plan.weeks.first : plan.weeks.last);
    final request = plan.request;
    final goal = switch (request.mode) {
      PlanningMode.goal =>
        '${request.eventName ?? request.event?.label ?? 'Ziel'} am ${GermanFormat.date(request.eventDay ?? today)}',
      PlanningMode.period => '${request.focus.label} · ${plan.weeks.length} Wochen',
    };
    final todaySlots = plan.slotsOn(today);
    final load = controller.load;
    final recovery = controller.recovery;
    final lastChanges = plan.adjustments.reversed.take(3).toList();
    return ListView(
      padding: const EdgeInsets.only(bottom: 32),
      children: [
        FormSection(
          children: [
            ListTile(title: Text(goal), subtitle: Text(request.planSports.map((sport) => sport.label).join(' · '))),
            ListTile(
              title: Text('Woche ${week.index + 1} von ${plan.weeks.length}'),
              trailing: AppChip(text: week.phase.label, color: _phaseColor(week.phase)),
            ),
            if (load != null)
              LabeledRow(
                label: 'Fitness · Ermüdung · Form',
                value: '${load.fitness.round()} · ${load.fatigue.round()} · ${load.form.round()}',
              ),
            if (recovery != null) LabeledRow(label: 'Erholung heute', value: recovery.label),
          ],
        ),
        if (_changedGoal(plan) case final changed?)
          FormSection(
            footer: 'Dein Plan richtet sich noch nach dem bisherigen Ziel.',
            children: [
              ListTile(
                leading: const Icon(Icons.flag_outlined, color: Colors.orange),
                title: Text('Neues Ziel: ${changed.name} am ${GermanFormat.date(changed.day)}'),
                subtitle: const Text('Plan dafür erstellen'),
                trailing: const DisclosureChevron(),
                onTap: () => _push(context, (_) => EndurancePlanSetupScreen(goal: changed)),
              ),
            ],
          ),
        if (controller.message case final message?) FormSection(children: [ListTile(title: Text(message))]),
        FormSection(
          header: 'Heute',
          children: [
            if (todaySlots.isEmpty) const ListTile(title: Text('Keine Einheit geplant')),
            for (final slot in todaySlots) _SlotTile(slot: slot),
          ],
        ),
        FormSection(
          header: 'Diese Woche',
          children: [
            for (final slot in plan.slotsInWeek(week.index)) _SlotTile(slot: slot, showDay: true),
            ListTile(
              title: const Text('Gesamtplan'),
              subtitle: Text('${plan.weeks.length} Wochen, ${plan.slots.length} Einheiten'),
              trailing: const DisclosureChevron(),
              onTap: () => _push(context, (_) => const EnduranceOverviewScreen()),
            ),
          ],
        ),
        FormSection(
          header: 'Garmin',
          footer:
              'Überträgt die Einheiten der nächsten ${WorkoutExporterService.syncDays} Tage samt Schritten und Zielen (Pace, Watt, Puls) in den '
              'Garmin-Connect-Kalender und ersetzt sie, sobald sich der Plan ändert. Inoffizielle Schnittstelle – '
              'Garmin kann sie jederzeit ändern.',
          children: [
            SwitchListTile.adaptive(
              title: const Text('Automatisch in den Garmin-Kalender'),
              value: plan.autoSyncGarmin,
              onChanged: controller.isBusy ? null : (value) => unawaited(controller.setAutoSync(value)),
            ),
            if (plan.autoSyncGarmin)
              ListTile(
                title: const Text('Jetzt abgleichen'),
                textColor: Theme.of(context).colorScheme.primary,
                onTap: controller.isBusy ? null : () => unawaited(controller.refresh()),
              ),
          ],
        ),
        FormSection(
          header: 'Anpassungen',
          children: [
            if (lastChanges.isEmpty) const ListTile(title: Text('Noch keine – der Plan läuft wie erstellt.')),
            for (final entry in lastChanges)
              ListTile(title: Text('${_weekdayDate(entry.day)} · ${entry.cause.label}'), subtitle: Text(entry.reason)),
            if (plan.adjustments.length > 3)
              ListTile(
                title: const Text('Alle Anpassungen'),
                trailing: const DisclosureChevron(),
                onTap: () => _push(context, (_) => const EnduranceAdjustmentsScreen()),
              ),
          ],
        ),
        FormSection(
          children: [
            ListTile(
              title: const Text('Schwellenwerte'),
              subtitle: Text(_thresholdText(request.thresholds)),
              trailing: const DisclosureChevron(),
              onTap: () => _push(context, (_) => ThresholdsScreen(initial: request.thresholds)),
            ),
            ListTile(
              title: const Text('Einzelne Einheit exportieren'),
              trailing: const DisclosureChevron(),
              onTap: () => _push(context, (_) => const AdHocWorkoutScreen()),
            ),
            ListTile(
              title: const Text('Neuen Plan erstellen'),
              trailing: const DisclosureChevron(),
              onTap: () => _push(context, (_) => const EndurancePlanSetupScreen()),
            ),
            ListTile(
              title: const Text('Plan löschen'),
              textColor: Theme.of(context).colorScheme.error,
              onTap: () => unawaited(_confirmDelete(context, controller)),
            ),
          ],
        ),
      ],
    );
  }

  List<KnownGoal> _knownGoals() {
    final settings = ref.read(coachSettingsProvider);
    return EnduranceGoals.known(settings.profile, settings.season, today: CalendarDay.today());
  }

  KnownGoal? _nextGoal() => _knownGoals().firstOrNull;

  KnownGoal? _changedGoal(EndurancePlan plan) => EnduranceGoals.changedGoal(plan, _knownGoals());

  Future<void> _confirmDelete(BuildContext context, EnduranceController controller) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Plan löschen?'),
        content: const Text('Kommende Workouts im Garmin-Kalender werden ebenfalls entfernt.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Abbrechen')),
          TextButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Löschen')),
        ],
      ),
    );
    if (confirmed == true) await controller.delete();
  }
}

String _thresholdText(AthleteThresholds thresholds) {
  final parts = [
    if (thresholds.runThresholdPace case final pace?) 'Lauf ${clockText(pace)} /km',
    if (thresholds.ftpWatts case final ftp?) 'FTP $ftp W',
    if (thresholds.swimCss case final css?) 'CSS ${clockText(css)} /100 m',
    if (thresholds.runThresholdHeartRate case final hr?) 'Schwellenpuls $hr',
  ];
  return parts.isEmpty ? 'Keine – Ziele nur als Zonen' : parts.join(' · ');
}

class _SlotTile extends StatelessWidget {
  const _SlotTile({required this.slot, this.showDay = false});

  final PlanSlot slot;
  final bool showDay;

  @override
  Widget build(BuildContext context) {
    final workout = slot.current;
    final status = switch (slot.status) {
      SlotStatus.completed => const Icon(Icons.check_circle, color: Colors.green),
      SlotStatus.missed => const Icon(Icons.cancel, color: Colors.grey),
      SlotStatus.planned => slot.isAdapted ? const Icon(Icons.auto_fix_high, color: Colors.orange) : null,
    };
    return ListTile(
      leading: SportIcon(
        symbol: workout.sport.symbol,
        color: workout.isRest ? Colors.grey : _sportColor(workout.sport),
      ),
      title: Text(workout.isRest ? 'Ruhetag (statt ${slot.baseline.type.label})' : workout.title),
      subtitle: Text(
        [
          if (showDay) _weekdayDate(slot.day),
          if (!workout.isRest) workout.meters != null ? '${workout.meters} m' : '${workout.minutes} min',
          if (!workout.isRest) '${workout.load.round()} TSS',
          if (slot.isAdapted && slot.status == SlotStatus.planned) 'angepasst',
        ].join(' · '),
      ),
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [?status, const DisclosureChevron()]),
      onTap: () => _push(context, (_) => EnduranceWorkoutScreen(slotID: slot.id)),
    );
  }
}

/// Alle Wochen mit Phase und Umfang.
class EnduranceOverviewScreen extends ConsumerWidget {
  const EnduranceOverviewScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.watch(enduranceControllerProvider);
    final plan = controller.plan;
    if (plan == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text('Kein Plan')),
      );
    }
    final today = controller.today;
    return Scaffold(
      appBar: AppBar(title: const Text('Gesamtplan')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          FormSection(
            children: [
              for (final week in plan.weeks)
                ListTile(
                  title: Text('Woche ${week.index + 1} · ab ${GermanFormat.date(week.monday)}'),
                  subtitle: Text(() {
                    final slots = plan.slotsInWeek(week.index);
                    final done = slots.where((slot) => slot.status == SlotStatus.completed).length;
                    final minutes = slots.fold(0, (sum, slot) => sum + slot.current.minutes);
                    return '${slots.length} Einheiten · ${(minutes / 60).toStringAsFixed(1).replaceAll('.', ',')} h'
                        '${done > 0 ? ' · $done erledigt' : ''}';
                  }()),
                  selected: today >= week.monday && today <= week.monday.adding(6),
                  trailing: AppChip(text: week.phase.label, color: _phaseColor(week.phase)),
                  onTap: () => _push(context, (_) => EnduranceWeekScreen(weekIndex: week.index)),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Eine Woche des Plans.
class EnduranceWeekScreen extends ConsumerWidget {
  const EnduranceWeekScreen({super.key, required this.weekIndex});

  final int weekIndex;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final plan = ref.watch(enduranceControllerProvider).plan;
    if (plan == null || weekIndex >= plan.weeks.length) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text('Kein Plan')),
      );
    }
    final week = plan.weeks[weekIndex];
    final slots = plan.slotsInWeek(weekIndex);
    return Scaffold(
      appBar: AppBar(title: Text('Woche ${week.index + 1}')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          FormSection(
            footer: 'Geplanter Umfang ${week.minutes} min.',
            children: [
              ListTile(
                title: Text('ab ${GermanFormat.date(week.monday)}'),
                trailing: AppChip(text: week.phase.label, color: _phaseColor(week.phase)),
              ),
            ],
          ),
          FormSection(children: [for (final slot in slots) _SlotTile(slot: slot, showDay: true)]),
        ],
      ),
    );
  }
}

/// Eine Einheit des Plans mit Schritten, Anpassung und Export.
class EnduranceWorkoutScreen extends ConsumerWidget {
  const EnduranceWorkoutScreen({super.key, required this.slotID});

  final String slotID;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.watch(enduranceControllerProvider);
    final slot = controller.plan?.slot(slotID);
    if (slot == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text('Einheit nicht gefunden')),
      );
    }
    final synced = controller.plan?.synced[slot.id];
    final upToDate = synced != null && synced.fingerprint == WorkoutExport.fingerprint(slot.current, slot.day);
    return Scaffold(
      appBar: AppBar(title: Text(slot.current.isRest ? 'Ruhetag' : slot.current.title)),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          FormSection(
            children: [
              LabeledRow(label: 'Tag', value: _weekdayDate(slot.day)),
              LabeledRow(label: 'Phase', value: slot.phase.label),
              LabeledRow(label: 'Stand', value: slot.status.label),
              if (slot.actualLoad case final load?)
                LabeledRow(label: 'Belastung', value: '${load.round()} statt ${slot.current.load.round()} TSS'),
              if (synced != null)
                LabeledRow(label: 'Garmin-Kalender', value: upToDate ? 'aktuell' : 'veraltet – erneut senden'),
            ],
          ),
          if (slot.isAdapted)
            FormSection(
              header: 'Angepasst',
              children: [
                if (slot.current.note.isNotEmpty) ListTile(title: Text(slot.current.note)),
                LabeledRow(label: 'Ursprünglich', value: slot.baseline.summary),
              ],
            ),
          RouteForSlotSection(slot: slot, runThresholdPace: controller.plan?.request.thresholds.runThresholdPace),
          WorkoutDetailSections(workout: slot.current, day: slot.day, onSend: () => controller.send(slot)),
        ],
      ),
    );
  }
}

/// Schritte und Export einer Einheit (Plan oder frei).
class WorkoutDetailSections extends ConsumerStatefulWidget {
  const WorkoutDetailSections({super.key, required this.workout, required this.day, required this.onSend});

  final EnduranceWorkout workout;
  final CalendarDay day;
  final Future<String> Function() onSend;

  @override
  ConsumerState<WorkoutDetailSections> createState() => _WorkoutDetailSectionsState();
}

class _WorkoutDetailSectionsState extends ConsumerState<WorkoutDetailSections> {
  bool _busy = false;
  String? _message;

  Future<void> _run(Future<String?> Function() action) async {
    setState(() => _busy = true);
    String? text;
    try {
      text = await action();
    } on Object catch (error) {
      text = 'Hat nicht geklappt: $error';
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      _message = text;
    });
  }

  Future<String?> _share(Future<File> Function() write, String mime) async {
    final file = await write();
    await SharePlus.instance.share(ShareParams(files: [XFile(file.path, mimeType: mime)]));
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final workout = widget.workout;
    if (workout.isRest) {
      return const FormSection(children: [ListTile(title: Text('Heute nichts – Erholung ist Training.'))]);
    }
    final controller = ref.read(enduranceControllerProvider);
    final primary = Theme.of(context).colorScheme.primary;
    return Column(
      children: [
        FormSection(
          header: 'Ablauf',
          footer: '${workout.load.round()} Belastungspunkte (TSS) geplant.',
          children: [for (final line in WorkoutExport.summary(workout)) ListTile(dense: true, title: Text(line))],
        ),
        if (_message case final message?) FormSection(children: [ListTile(title: Text(message))]),
        FormSection(
          header: 'Exportieren',
          footer:
              'An die Uhr: über den Garmin-Connect-Kalender, beim nächsten Synchronisieren auf der Uhr. FIT-Datei: für '
              'Uhren und Apps, die Workouts importieren. Zwift: die .zwo-Datei in den Ordner '
              'Dokumente/Zwift/Workouts/<Zwift-ID> am PC legen, Zwift zeigt sie unter '
              '„Eigene Workouts“.',
          children: [
            ListTile(
              enabled: !_busy,
              leading: const Icon(Icons.watch),
              title: const Text('Einheit an Uhr senden'),
              textColor: primary,
              onTap: () => unawaited(_run(widget.onSend)),
            ),
            ListTile(
              enabled: !_busy,
              leading: const Icon(Icons.description_outlined),
              title: const Text('FIT-Datei teilen'),
              textColor: primary,
              onTap: () => unawaited(
                _run(() => _share(() => controller.fitFile(workout, widget.day), 'application/vnd.ant.fit')),
              ),
            ),
            if (ZwiftWorkoutFile.supports(workout))
              ListTile(
                enabled: !_busy,
                leading: const Icon(Icons.directions_bike),
                title: const Text('Für Zwift exportieren (.zwo)'),
                textColor: primary,
                onTap: () =>
                    unawaited(_run(() => _share(() => controller.zwoFile(workout, widget.day), 'application/xml'))),
              ),
          ],
        ),
      ],
    );
  }
}

/// Verlauf aller Anpassungen.
class EnduranceAdjustmentsScreen extends ConsumerWidget {
  const EnduranceAdjustmentsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final plan = ref.watch(enduranceControllerProvider).plan;
    final entries = plan?.adjustments.reversed.toList() ?? const <PlanAdjustmentEntry>[];
    return Scaffold(
      appBar: AppBar(title: const Text('Anpassungen')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          FormSection(
            children: [
              if (entries.isEmpty) const ListTile(title: Text('Noch keine Anpassungen')),
              for (final entry in entries)
                ListTile(
                  title: Text('${_weekdayDate(entry.day)} · ${entry.cause.label}'),
                  subtitle: Text('${entry.reason}\n${entry.before} → ${entry.after}'),
                  isThreeLine: true,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

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
    _longDay = suggestion.longDay;
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
                  }),
                ),
              ),
              _Choice<Weekday>(
                label: 'Lange Einheit',
                value: _longDay,
                items: [for (final day in Weekday.values) DropdownMenuItem(value: day, child: Text(day.long))],
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
