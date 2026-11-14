import 'dart:async';

import 'package:coach_core/coach_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../data/settings/coach_settings.dart';
import '../../data/storage.dart';
import '../../services/providers.dart';
import '../../ui/components.dart';
import '../today/today_controller.dart';
import '../training/sleep_coach_screen.dart';
import 'wake_alarm_section.dart';

/// Baut den Morning Report aus den Tageswerten, dem Schlaf-Coach und den Einheiten von heute (Port von
/// `MorningReportBuilder`).
abstract final class MorningReportBuilder {
  static MorningReport make({
    required CoachSettings settings,
    required List<DailyMetrics> days,
    required List<GarminActivity> activities,
    required TodayFocus? focus,
    DateTime? now,
  }) {
    final today = CalendarDay.fromDate(now ?? DateTime.now());
    final sessions = [
      for (final item in focus?.items ?? const <TodayFocusItem>[])
        if (item.sport != null && item.status != SessionStatus.done)
          MorningSession(id: item.id, title: item.title, target: item.target, demanding: item.demanding),
    ];
    final form = FitnessForm.seriesUntil(activities, today: today);
    return MorningReport.make(
      days: days,
      today: today,
      sleep: settings.sleep,
      goal: settings.profile.goal,
      sessions: sessions,
      form: FitnessForm.isReliable(form) ? form.lastOrNull : null,
      formSeries: form,
    );
  }
}

extension MorningStatusStyle on MorningStatus {
  Color get color => switch (this) {
    MorningStatus.good => Colors.green,
    MorningStatus.normal => Colors.blue,
    MorningStatus.attention => Colors.orange,
    MorningStatus.missing => Colors.grey,
  };

  IconData get icon => switch (this) {
    MorningStatus.good => Icons.check_circle,
    MorningStatus.normal => Icons.circle,
    MorningStatus.attention => Icons.warning_amber_rounded,
    MorningStatus.missing => Icons.help_outline,
  };

  String get label => switch (this) {
    MorningStatus.good => 'gut',
    MorningStatus.normal => 'üblich',
    MorningStatus.attention => 'auffällig',
    MorningStatus.missing => 'fehlt',
  };
}

extension MorningReportStyle on MorningReport {
  Color get levelColor => switch (level) {
    RecoveryLevel.normal => Colors.green,
    RecoveryLevel.locker => Colors.orange,
    RecoveryLevel.pause => Colors.red,
    null => Colors.grey,
  };

  IconData get levelIcon => switch (level) {
    RecoveryLevel.normal => Icons.wb_sunny,
    RecoveryLevel.locker => Icons.slow_motion_video,
    RecoveryLevel.pause => Icons.bed,
    null => Icons.question_mark,
  };
}

class MorningReportHeader extends StatelessWidget {
  const MorningReportHeader({super.key, required this.report});

  final MorningReport report;

  @override
  Widget build(BuildContext context) => Row(
    spacing: 12,
    children: [
      ExcludeSemantics(
        child: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(color: report.levelColor, borderRadius: BorderRadius.circular(14)),
          child: Icon(report.levelIcon, color: Colors.white, size: 28),
        ),
      ),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: 2,
          children: [
            Text(report.headline, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
            Text(
              DateFormat('EEEE, d. MMMM', 'de_DE').format(report.day.referenceDate),
              style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    ],
  );
}

class MorningReportRow extends StatelessWidget {
  const MorningReportRow({super.key, required this.item});

  final MorningItem item;

  @override
  Widget build(BuildContext context) {
    final secondary = Theme.of(context).colorScheme.onSurfaceVariant;
    return ListTile(
      leading: Icon(item.status.icon, color: item.status.color, semanticLabel: item.status.label),
      title: Row(
        children: [
          Expanded(
            child: Text(item.title, style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              item.value ?? '–',
              textAlign: TextAlign.end,
              style: TextStyle(color: item.value == null ? secondary : null),
            ),
          ),
        ],
      ),
      subtitle: Text(item.note),
    );
  }
}

/// Kompakte Karte im Reiter „Heute“ (bis 12 Uhr): Kopf, vier Kernwerte, Auffälligkeiten (Port von `MorningReportCard`).
class MorningReportCard extends StatelessWidget {
  const MorningReportCard({super.key, required this.report, required this.focus});

  final MorningReport report;
  final TodayFocus? focus;

  static const keyMetrics = [
    MorningMetric.sleepDuration,
    MorningMetric.hrv,
    MorningMetric.restingHeartRate,
    MorningMetric.bodyBattery,
  ];

  @override
  Widget build(BuildContext context) {
    final items = [
      for (final item in report.items)
        if (keyMetrics.contains(item.metric) && item.status != MorningStatus.missing) item,
    ];
    final first = report.findings.firstOrNull;
    final secondary = Theme.of(context).colorScheme.onSurfaceVariant;
    return FormSection(
      header: 'Morning Report',
      children: [
        InkWell(
          onTap: () =>
              Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => MorningReportScreen(focus: focus))),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 10,
              children: [
                MorningReportHeader(report: report),
                if (items.isNotEmpty)
                  Row(
                    spacing: 8,
                    children: [
                      for (final item in items)
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            spacing: 2,
                            children: [
                              FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: Alignment.centerLeft,
                                child: Text(item.value ?? '–', style: const TextStyle(fontWeight: FontWeight.w600)),
                              ),
                              Row(
                                spacing: 4,
                                children: [
                                  Icon(item.status.icon, size: 12, color: item.status.color),
                                  Flexible(
                                    child: Text(
                                      item.title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontSize: 11),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                if (first != null)
                  Text(
                    report.findings.length > 1 ? '$first (+${report.findings.length - 1})' : first,
                    style: TextStyle(fontSize: 13, color: secondary),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Vollständiger Morning Report (Port von `MorningReportView`).
class MorningReportScreen extends ConsumerStatefulWidget {
  const MorningReportScreen({super.key, this.focus});

  /// Aus „Heute“ übergeben; sonst hier berechnet (z. B. aus dem Gesundheitsbereich).
  final TodayFocus? focus;

  @override
  ConsumerState<MorningReportScreen> createState() => _MorningReportScreenState();
}

class _MorningReportScreenState extends ConsumerState<MorningReportScreen> {
  List<DailyMetrics> _days = const [];
  List<GarminActivity> _activities = const [];
  TodayFocus? _computedFocus;

  @override
  void initState() {
    super.initState();
    unawaited(_reload());
  }

  Future<void> _reload() async {
    final today = CalendarDay.today();
    final results = await (
      ref.read(metricsRepositoryProvider).range(from: today.adding(-400), to: today),
      ref.read(activityRepositoryProvider).all(),
      ref.read(gymRepositoryProvider).all(),
    ).wait;
    if (!mounted) return;
    TodayFocus? focus;
    if (widget.focus == null) {
      final controller = TodayController(
        store: ref.read(settingsStoreProvider),
        schedule: ref.read(seasonScheduleProvider),
      );
      final sessions = [for (final record in results.$3) record.session];
      controller.update(
        days: results.$1,
        activities: results.$2,
        settings: ref.read(coachSettingsProvider),
        gymDays: [for (final session in sessions) session.day],
        gym: [for (final session in sessions) GymItem.fromSession(session)],
      );
      focus = controller.snapshot?.focus;
      controller.dispose();
    }
    setState(() {
      _days = results.$1;
      _activities = results.$2;
      _computedFocus = focus;
    });
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(appModelProvider.select((model) => model.lastSync), (_, _) => unawaited(_reload()));
    final settings = ref.watch(coachSettingsProvider);
    final report = MorningReportBuilder.make(
      settings: settings,
      days: _days,
      activities: _activities,
      focus: widget.focus ?? _computedFocus,
    );
    final secondary = Theme.of(context).colorScheme.onSurfaceVariant;
    return Scaffold(
      appBar: AppBar(title: const Text('Morning Report')),
      body: RefreshIndicator(
        onRefresh: () async {
          await ref.read(appModelProvider).syncNow();
          await _reload();
        },
        child: ListView(
          padding: const EdgeInsets.only(bottom: 32),
          children: [
            FormSection(
              footer: report.isFromYesterday
                  ? 'Für heute liegen noch keine Werte vor – gezeigt wird die letzte Nacht davor. Ziehe zum Abrufen '
                        'nach unten.'
                  : null,
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    spacing: 10,
                    children: [
                      MorningReportHeader(report: report),
                      for (final finding in report.findings)
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          spacing: 6,
                          children: [
                            const Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 18),
                            Expanded(child: Text(finding)),
                          ],
                        ),
                      Text(report.recommendation, style: const TextStyle(fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
              ],
            ),
            FormSection(
              header: 'Werte der Nacht',
              footer:
                  'Eingeordnet gegen deinen üblichen Bereich der letzten 30 Tage (ab 7 Tagen mit Werten), HRV gegen '
                  'Garmins Baseline. Stress vom Vortag.',
              children: [for (final item in report.items) MorningReportRow(item: item)],
            ),
            FormSection(
              header: 'Heute geplant',
              children: [
                if (report.sessions.isEmpty)
                  ListTile(
                    title: Text('Keine Einheit geplant.', style: TextStyle(color: secondary)),
                  ),
                for (final session in report.sessions)
                  ListTile(
                    title: Text(session.title, style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text(session.target),
                  ),
              ],
            ),
            FormSection(
              header: 'Schlafempfehlung',
              children: [
                ListTile(
                  title: Text(
                    report.sleepAdvice ??
                        'Ab 3 Nächten mit Schlafdaten berechnet der Schlaf-Coach deine Schlafenszeit.',
                    style: TextStyle(color: report.sleepAdvice == null ? secondary : null),
                  ),
                ),
                ListTile(
                  title: const Text('Schlaf-Coach'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () =>
                      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const SleepCoachScreen())),
                ),
              ],
            ),
            WakeAlarmSection(
              wake: WakeTime.fromMinutes(settings.sleep.wakeMinutes),
              tonightMinutes:
                  SleepCoach.report(
                    days: _days,
                    settings: settings.sleep,
                    goal: settings.profile.goal,
                    today: report.day,
                  )?.tonightMinutes ??
                  (settings.sleep.targetHours * 60).round(),
            ),
            if (report.missing.isNotEmpty)
              FormSection(
                header: 'Fehlt heute',
                footer:
                    'Fehlende Werte werden nicht geschätzt. Body Battery, Stress und Readiness gibt es nur von Garmin.',
                children: [
                  ListTile(
                    title: Text(report.missing.join(', '), style: TextStyle(color: secondary)),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
