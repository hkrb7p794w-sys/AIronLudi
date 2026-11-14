import 'dart:async';
import 'dart:math' as math;

import 'package:coach_core/coach_core.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/settings/coach_settings.dart';
import '../../data/storage.dart';
import '../../platform/notifications.dart';
import '../../services/providers.dart';
import '../../ui/components.dart';
import '../evidence/evidence_views.dart';

/// Erinnerung 30 Minuten vor der empfohlenen Schlafenszeit, täglich bis zur Neuberechnung (Port von
/// `BedtimeReminder`).
abstract final class BedtimeReminder {
  static const identifier = 'coach.bedtime';

  static Future<void> schedule(
    NotificationCenterBridge? center, {
    required SleepSettings settings,
    required int? bedtimeMinutes,
  }) async {
    if (center == null) return;
    await center.removePending(const [identifier]);
    if (!settings.reminder || bedtimeMinutes == null) return;
    if (await center.permission(requestIfNeeded: true) != NotificationPermission.allowed) return;
    final reminder = ((bedtimeMinutes - 30) % 1440 + 1440) % 1440;
    await center.add(
      LocalNotification(
        id: identifier,
        title: 'Bald Schlafenszeit',
        body: 'Um ${SleepCoach.clock(bedtimeMinutes)} ins Bett – dann reicht der Schlaf für morgen.',
        day: CalendarDay.today(),
        hour: reminder ~/ 60,
        minute: reminder % 60,
        repeatsDaily: true,
      ),
    );
  }
}

/// Schlaf-Coach: Bedarf für heute Nacht, Schlafenszeit, Verlauf der letzten zwei Wochen, Hinweise und Einstellungen
/// (Port von `SleepCoachView`).
class SleepCoachScreen extends ConsumerStatefulWidget {
  const SleepCoachScreen({super.key});

  @override
  ConsumerState<SleepCoachScreen> createState() => _SleepCoachScreenState();
}

class _SleepCoachScreenState extends ConsumerState<SleepCoachScreen> {
  List<DailyMetrics> _days = const [];
  String? _scheduled;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final today = CalendarDay.today();
    final days = await ref.read(metricsRepositoryProvider).range(from: today.adding(-60), to: today);
    if (mounted) setState(() => _days = days);
  }

  void _change(CoachSettings settings, void Function(SleepSettings sleep) update) {
    final sleep = settings.sleep;
    update(sleep);
    settings.sleep = sleep;
  }

  Future<void> _pickTime(CoachSettings settings, {required bool free}) async {
    final sleep = settings.sleep;
    final picked = await showTimePicker(
      context: context,
      initialTime: free
          ? TimeOfDay(hour: sleep.freeWakeHour, minute: sleep.freeWakeMinute)
          : TimeOfDay(hour: sleep.wakeHour, minute: sleep.wakeMinute),
    );
    if (picked == null) return;
    _change(settings, (sleep) {
      if (free) {
        sleep
          ..freeWakeHour = picked.hour
          ..freeWakeMinute = picked.minute;
      } else {
        sleep
          ..wakeHour = picked.hour
          ..wakeMinute = picked.minute;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(coachSettingsProvider);
    final sleep = settings.sleep;
    final today = CalendarDay.today();
    final report = SleepCoach.report(days: _days, settings: sleep, goal: settings.profile.goal, today: today);
    // Erinnerung neu planen, wenn sich Einstellungen oder Schlafenszeit ändern.
    final key = '${sleep.toJson()}-${report?.bedtimeMinutes}';
    if (key != _scheduled) {
      _scheduled = key;
      unawaited(
        BedtimeReminder.schedule(
          ref.read(notificationCenterProvider),
          settings: sleep,
          bedtimeMinutes: report?.bedtimeMinutes,
        ),
      );
    }
    final theme = Theme.of(context);
    final secondary = TextStyle(color: theme.colorScheme.onSurfaceVariant);
    String clock(int hour, int minute) => '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
    final recent = [
      for (final night in _days)
        if (night.day >= today.adding(-13) && (night.sleepSeconds ?? 0) > 0) night,
    ]..sort((a, b) => a.day.compareTo(b.day));
    return Scaffold(
      appBar: AppBar(title: const Text('Schlaf-Coach')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          if (report != null) ...[
            FormSection(
              header: 'Heute Nacht',
              children: [
                ListTile(
                  title: Text(
                    'Heute um ${SleepCoach.clock(report.bedtimeMinutes)} ins Bett',
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  subtitle: Text(
                    'Für ${GermanFormat.decimal(report.tonightMinutes / 60)} Stunden Schlaf bis '
                    '${SleepCoach.clock(report.nextWakeMinutes)}, inklusive etwa ${SleepCoach.latencyMinutes} Minuten '
                    'zum Einschlafen.',
                  ),
                ),
                LabeledRow(
                  label: 'Schnitt ${report.nights} Nächte',
                  value: '${GermanFormat.decimal(report.averageHours)} h',
                ),
                if (report.debtHours > 0)
                  LabeledRow(label: 'Unter deinem Ziel', value: '${GermanFormat.decimal(report.debtHours)} h'),
                if (report.bedtimeSpreadMinutes case final spread?)
                  LabeledRow(label: 'Schwankung Einschlafzeit', value: '± ${spread.toInt()} min'),
              ],
            ),
            FormSection(
              header: 'Hinweise',
              children: [
                for (final tip in report.tips)
                  ListTile(
                    leading: Icon(tip.id == 'good' ? Icons.check_circle : Icons.bedtime_outlined),
                    title: Text(tip.text),
                  ),
                EvidenceDisclosure(ruleIDs: [for (final tip in report.tips) ...tip.evidenceIDs]),
              ],
            ),
          ] else
            FormSection(
              children: [
                ListTile(
                  title: Text(
                    'Für den Schlaf-Coach braucht die App Schlafdaten von mindestens drei Nächten aus Garmin.',
                    style: secondary,
                  ),
                ),
              ],
            ),
          if (recent.isNotEmpty)
            FormSection(
              header: 'Letzte 14 Nächte',
              children: [
                Semantics(
                  label: 'Schlafdauer der letzten 14 Nächte',
                  excludeSemantics: true,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(8, 16, 16, 8),
                    child: SizedBox(
                      height: 160,
                      child: BarChart(
                        BarChartData(
                          maxY: math.max(
                            sleep.targetHours + 1,
                            recent.map((night) => (night.sleepSeconds ?? 0) / 3600).reduce(math.max) + 0.5,
                          ),
                          barGroups: [
                            for (final (index, night) in recent.indexed)
                              BarChartGroupData(
                                x: index,
                                barRods: [
                                  BarChartRodData(
                                    toY: (night.sleepSeconds ?? 0) / 3600,
                                    width: 12,
                                    color: (night.sleepSeconds ?? 0) / 3600 >= 7 ? Colors.indigo : Colors.orange,
                                    borderRadius: BorderRadius.circular(3),
                                  ),
                                ],
                              ),
                          ],
                          extraLinesData: ExtraLinesData(
                            horizontalLines: [
                              HorizontalLine(
                                y: sleep.targetHours,
                                color: theme.colorScheme.onSurfaceVariant,
                                strokeWidth: 1,
                                dashArray: const [4, 4],
                              ),
                            ],
                          ),
                          titlesData: FlTitlesData(
                            topTitles: const AxisTitles(),
                            rightTitles: const AxisTitles(),
                            leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 28)),
                            bottomTitles: AxisTitles(
                              sideTitles: SideTitles(
                                showTitles: true,
                                getTitlesWidget: (value, meta) => SideTitleWidget(
                                  meta: meta,
                                  child: Text('${recent[value.toInt()].day.day}', style: const TextStyle(fontSize: 10)),
                                ),
                              ),
                            ),
                          ),
                          borderData: FlBorderData(show: false),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          FormSection(
            header: 'Einstellungen',
            footer: 'Erwachsene brauchen regelmäßig 7–9 Stunden. Gleichmäßige Zeiten helfen am meisten.',
            children: [
              ListTile(
                title: Text('Ziel: ${GermanFormat.decimal(sleep.targetHours)} Stunden'),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: 'Ziel verringern',
                      icon: const Icon(Icons.remove),
                      onPressed: sleep.targetHours > 7
                          ? () => _change(settings, (sleep) => sleep.targetHours -= 0.25)
                          : null,
                    ),
                    IconButton(
                      tooltip: 'Ziel erhöhen',
                      icon: const Icon(Icons.add),
                      onPressed: sleep.targetHours < 9
                          ? () => _change(settings, (sleep) => sleep.targetHours += 0.25)
                          : null,
                    ),
                  ],
                ),
              ),
              ListTile(
                title: const Text('Aufstehen'),
                trailing: Text(clock(sleep.wakeHour, sleep.wakeMinute)),
                onTap: () => _pickTime(settings, free: false),
              ),
              SwitchListTile(
                title: const Text('Erinnerung 30 min vorher'),
                value: sleep.reminder,
                onChanged: (value) => _change(settings, (sleep) => sleep.reminder = value),
              ),
              SwitchListTile(
                title: const Text('An freien Tagen später aufstehen'),
                value: sleep.usesFreeDayTime,
                onChanged: (value) => _change(settings, (sleep) => sleep.usesFreeDayTime = value),
              ),
              if (sleep.usesFreeDayTime) ...[
                ListTile(
                  title: const Text('Aufstehen (frei)'),
                  trailing: Text(clock(sleep.freeWakeHour, sleep.freeWakeMinute)),
                  onTap: () => _pickTime(settings, free: true),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: DropdownButtonFormField<GermanState?>(
                    initialValue: sleep.state,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Bundesland'),
                    items: [
                      const DropdownMenuItem(child: Text('Nicht festgelegt')),
                      for (final state in GermanState.values) DropdownMenuItem(value: state, child: Text(state.label)),
                    ],
                    onChanged: (state) => _change(settings, (sleep) => sleep.state = state),
                  ),
                ),
                if (sleep.state == null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                    child: Text(
                      'Ohne Bundesland zählen nur Wochenenden als frei.',
                      style: secondary.copyWith(fontSize: 13),
                    ),
                  ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
