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
import '../../ui/tokens.dart';
import '../fuel/fuel_for_slot.dart';
import '../routes/route_for_slot.dart';
import 'endurance_controller.dart';

part 'endurance_detail_screens.dart';
part 'endurance_setup_screens.dart';

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
  EndurancePhase.base => AppPalette.blue,
  EndurancePhase.build => AppPalette.orange,
  EndurancePhase.peak => AppPalette.red,
  EndurancePhase.taper => AppPalette.teal,
  EndurancePhase.recovery => AppPalette.green,
  EndurancePhase.race => AppPalette.purple,
};

Color _sportColor(EnduranceSport sport) => switch (sport) {
  EnduranceSport.run => AppPalette.orange,
  EnduranceSport.bike => AppPalette.green,
  EnduranceSport.swim => AppPalette.blue,
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
            leading: SportIcon(symbol: 'figure.run', color: AppColors.of(context).caution),
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
                leading: Icon(Icons.flag_outlined, color: AppColors.of(context).caution),
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
