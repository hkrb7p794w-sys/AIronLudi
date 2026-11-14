import 'package:coach_core/coach_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/providers.dart';
import '../../ui/components.dart';
import '../../ui/sport_style.dart';
import '../../ui/symbols.dart';
import '../activities/activities_screen.dart';
import '../activities/activity_detail_screen.dart';
import '../activities/activity_parts.dart';
import '../evidence/evidence_views.dart';
import 'now_views.dart';
import 'today_controller.dart';

/// Eine Zeile des Saisonplans: Sportart, Titel, Hinweis, erledigt; Antippen zeigt den Ablauf.
class TodayItemRow extends StatefulWidget {
  const TodayItemRow({super.key, required this.item});

  final TodayPlanItem item;

  @override
  State<TodayItemRow> createState() => _TodayItemRowState();
}

class _TodayItemRowState extends State<TodayItemRow> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final secondary = TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant);
    final color = switch (item.sport) {
      TodayPlanSport.swim => TrainingSport.swim.color,
      TodayPlanSport.bike => TrainingSport.bike.color,
      TodayPlanSport.run => TrainingSport.run.color,
      TodayPlanSport.strength => TrainingSport.strength.color,
      TodayPlanSport.rest => Colors.teal.shade300,
    };
    return Semantics(
      hint: item.detail.isEmpty ? null : 'Doppeltippen zeigt den Ablauf',
      child: InkWell(
        onTap: item.detail.isEmpty ? null : () => setState(() => _expanded = !_expanded),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 6,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 12,
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(8)),
                    child: Icon(todayPlanIcon(item.sport), color: Colors.white, size: 18),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      spacing: 2,
                      children: [
                        Text.rich(
                          TextSpan(
                            children: [
                              if (item.day case final day?)
                                TextSpan(
                                  text: '$day  ',
                                  style: secondary.copyWith(fontSize: 12, fontWeight: FontWeight.bold),
                                ),
                              TextSpan(
                                text: item.title,
                                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
                              ),
                            ],
                          ),
                        ),
                        if (item.caption.isNotEmpty) Text(item.caption, style: secondary),
                        if (item.chip.isNotEmpty)
                          CoachChip(
                            text: item.chip,
                            color: item.chip == 'nur locker bewegen' ? Colors.red : Colors.orange,
                          ),
                      ],
                    ),
                  ),
                  if (item.done) const Icon(Icons.check_circle, color: Colors.green, semanticLabel: 'erledigt'),
                ],
              ),
              if (_expanded && item.detail.isNotEmpty) Text(item.detail, style: secondary.copyWith(fontSize: 13)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Saisonplan: offene Läufe ohne festen Tag und Ausfälle (die heutigen Einheiten stehen in „Jetzt dran“).
class SeasonOpenSections extends StatelessWidget {
  const SeasonOpenSections({super.key, required this.today});

  final TodayPlan today;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      if (today.open.isNotEmpty)
        FormSection(
          header: 'Noch offen · ohne festen Tag',
          footer: today.hint.isEmpty ? null : today.hint,
          children: [for (final item in today.open) TodayItemRow(item: item)],
        ),
      if (today.skipped.isNotEmpty)
        FormSection(
          header: 'Fällt diese Woche aus',
          children: [for (final item in today.skipped) TodayItemRow(item: item)],
        ),
    ],
  );
}

/// Alles, was nicht nur heute zählt: Rest der Woche, Wochenziele, eigene Ziele, Import-Hinweise
/// (Port von `WeekOverviewView`).
class WeekOverviewScreen extends ConsumerWidget {
  const WeekOverviewScreen({super.key, required this.snapshot, required this.activities, required this.gymDays});

  final TodaySnapshot snapshot;
  final List<GarminActivity> activities;
  final Set<CalendarDay> gymDays;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(coachSettingsProvider);
    final imported = settings.importedNotes;
    return Scaffold(
      appBar: AppBar(title: const Text('Diese Woche')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          if (settings.profile.mode == ProfileMode.season) ...[
            if (snapshot.today case final today? when today.rest.isNotEmpty)
              FormSection(
                header: 'Rest der Woche',
                children: [for (final item in today.rest) TodayItemRow(item: item)],
              ),
            _WeekSection(plan: snapshot.plan),
          ] else ...[
            _PersonalWeekStrip(
              schedule: settings.schedule(snapshot.plan.today),
              sessions: snapshot.sessions,
              activityDays: {
                for (final activity in activities)
                  if ((activity.durationSeconds ?? 0) >= 600) ?activity.day,
                ...gymDays,
              },
            ),
            _PersonalGoalSection(snapshot: snapshot, activities: activities),
          ],
          if (imported != null)
            FormSection(
              header: 'Vom KI-Coach (Import vom ${shortDate(imported.day)})',
              children: [
                for (final text in imported.texts) ListTile(leading: const Icon(Icons.auto_awesome), title: Text(text)),
                ListTile(
                  title: const Text('Hinweise entfernen', style: TextStyle(color: Colors.red)),
                  onTap: () => settings.importedNotes = null,
                ),
              ],
            ),
          if (activities.isNotEmpty)
            FormSection(
              header: 'Letzte Aktivitäten',
              children: [
                for (final activity in ([
                  ...activities,
                ]..sort((a, b) => (b.startLocal ?? '').compareTo(a.startLocal ?? ''))).take(5))
                  ActivitySummaryRow(
                    activity: activity,
                    onTap: () =>
                        Navigator.of(context)
                            .push(MaterialPageRoute<void>(builder: (_) => ActivityDetailScreen(activity: activity))),
                  ),
                ListTile(
                  title: const Text('Alle Aktivitäten'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(builder: (_) => const ActivitiesScreen(initialScope: ActivitiesScope.mine)),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _WeekSection extends StatelessWidget {
  const _WeekSection({required this.plan});

  final PlanState plan;

  @override
  Widget build(BuildContext context) {
    final secondary = TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant);
    return FormSection(
      header: 'Woche (${plan.weekday}, noch ${plan.daysLeftInWeek} Tage)',
      footer: plan.weekOpen.isEmpty ? null : 'Noch offen: ${plan.weekOpen.join(', ')}',
      children: [
        for (final item in plan.targets)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 4,
              children: [
                Row(
                  children: [
                    Expanded(child: Text(item.target.label)),
                    Text(
                      '${item.done} / ${item.target.minimum == item.target.maximum ? '${item.target.minimum}' : '${item.target.minimum}–${item.target.maximum}'}',
                      style: secondary.copyWith(fontSize: 14),
                    ),
                  ],
                ),
                LinearProgressIndicator(
                  value: item.percent / 100,
                  color: item.done >= item.target.minimum ? Colors.green : null,
                ),
                if (item.target.detail.isNotEmpty) Text(item.target.detail, style: secondary),
              ],
            ),
          ),
        if (plan.todayFixed.isNotEmpty) ...[
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Text('Heute laut Wochenrahmen', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
          for (final item in plan.todayFixed)
            ListTile(
              dense: true,
              leading: Icon(item.done ? Icons.check_circle : Icons.circle_outlined),
              title: Text(item.text, style: item.done ? secondary.copyWith(fontSize: 14) : null),
            ),
        ],
      ],
    );
  }
}

enum _DayState { done, partial, today, planned, missed, rest, extra }

/// Die sieben Tage der Woche: geplant, erledigt (Soll/Ist je Einheit), frei.
class _PersonalWeekStrip extends StatelessWidget {
  const _PersonalWeekStrip({required this.schedule, required this.sessions, required this.activityDays});

  final WeekSchedule schedule;
  final SessionWeek? sessions;

  /// Tage mit Training (ab 10 Minuten) – an freien Tagen als Extra markiert.
  final Set<CalendarDay> activityDays;

  _DayState _state({required bool planned, required CalendarDay day, required CalendarDay today}) {
    final results = sessions?.resultsOn(day) ?? const <SessionResult>[];
    if (!planned || results.isEmpty) return activityDays.contains(day) ? _DayState.extra : _DayState.rest;
    if (results.every((result) => result.status == SessionStatus.done)) return _DayState.done;
    if (results.every((result) => result.status.counts)) return _DayState.partial;
    if (results.any((result) => result.status == SessionStatus.missed)) {
      return results.any((result) => result.status.counts) ? _DayState.partial : _DayState.missed;
    }
    return day == today ? _DayState.today : _DayState.planned;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final today = CalendarDay.today();
    final monday = today.adding(-today.weekdayIndex);
    final secondary = theme.colorScheme.onSurfaceVariant;
    return FormSection(
      header: 'Diese Woche',
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
          child: Row(
            children: [
              for (final weekday in Weekday.values)
                Expanded(
                  child: () {
                    final day = monday.adding(weekday.index);
                    final slots = schedule.slots(weekday);
                    final state = _state(planned: slots.isNotEmpty, day: day, today: today);
                    final fill = switch (state) {
                      _DayState.done => Colors.green,
                      _DayState.partial => Colors.orange,
                      _DayState.extra => Colors.green.withValues(alpha: 0.25),
                      _DayState.today => theme.colorScheme.primary.withValues(alpha: 0.15),
                      _DayState.planned => secondary.withValues(alpha: 0.15),
                      _DayState.missed => Colors.red.withValues(alpha: 0.12),
                      _DayState.rest => Colors.transparent,
                    };
                    final Widget icon = switch (state) {
                      _DayState.done => const Icon(Icons.check, size: 16, color: Colors.white),
                      _DayState.partial => const Icon(Icons.contrast, size: 16, color: Colors.white),
                      _DayState.extra => const Icon(Icons.add, size: 16, color: Colors.green),
                      _DayState.missed => const Icon(Icons.close, size: 16, color: Colors.red),
                      _DayState.rest => Text('–', style: TextStyle(color: secondary)),
                      _ => Icon(
                        AppSymbols.of(slots.firstOrNull?.sport.symbol ?? 'circle'),
                        size: 16,
                        color: slots.firstOrNull?.sport.color ?? secondary,
                      ),
                    };
                    final label = switch (state) {
                      _DayState.done => 'erledigt',
                      _DayState.partial => 'teilweise oder anders gemacht',
                      _DayState.extra => 'frei, außerplanmäßig trainiert',
                      _DayState.rest => 'frei',
                      _DayState.missed => 'verpasst',
                      _ => slots.map((slot) => slot.title).join(', '),
                    };
                    return Semantics(
                      label: '${weekday.long}: $label',
                      excludeSemantics: true,
                      child: Column(
                        spacing: 6,
                        children: [
                          Text(
                            weekday.short,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: day == today ? theme.colorScheme.primary : secondary,
                            ),
                          ),
                          Container(
                            width: 36,
                            height: 36,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: fill,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: state == _DayState.today ? theme.colorScheme.primary : Colors.transparent,
                                width: 2,
                              ),
                            ),
                            child: icon,
                          ),
                        ],
                      ),
                    );
                  }(),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Fortschritt zu den eigenen Zielen: Wettkampf, Ruhepuls, Laufstrecke.
class _PersonalGoalSection extends ConsumerWidget {
  const _PersonalGoalSection({required this.snapshot, required this.activities});

  final TodaySnapshot snapshot;
  final List<GarminActivity> activities;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(coachSettingsProvider).profile;
    final today = CalendarDay.today();
    final targets = profile.targets;
    final distances = [
      for (final activity in activities)
        if (activity.sport == ActivitySport.run && (activity.day ?? today.adding(-999)) >= today.adding(-28))
          ?activity.distanceMeters,
    ];
    final longestRun = distances.isEmpty ? null : distances.reduce((a, b) => a > b ? a : b) / 1000;
    final event = profile.event;
    if (event == null && targets.restingHeartRate == null && targets.runDistanceKilometers == null) {
      return const SizedBox.shrink();
    }
    Widget row(IconData icon, String title, String value) => ListTile(
      leading: Icon(icon, color: Theme.of(context).colorScheme.primary),
      title: Text(title),
      trailing: Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
    );
    return FormSection(
      header: 'Deine Ziele',
      children: [
        if (event != null)
          () {
            final days = today.daysUntil(event.date);
            return row(Icons.sports_score, event.name, days > 0 ? 'noch $days Tage' : (days == 0 ? 'heute' : 'vorbei'));
          }(),
        if (targets.restingHeartRate case final target?) ...[
          row(
            Icons.favorite,
            'Ruhepuls',
            '${snapshot.metrics?.restingHeartRate == null ? '–' : '${snapshot.metrics!.restingHeartRate!.round()} bpm'} → $target bpm',
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              GoalRules.restingHeartRateOutlook(current: snapshot.metrics?.restingHeartRate, target: target),
              style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
          ),
          const EvidenceDisclosure(ruleIDs: ['rhr.endurance']),
        ],
        if (targets.runDistanceKilometers case final target?)
          row(
            Icons.directions_run,
            'Längster Lauf (4 Wochen)',
            '${longestRun == null ? '–' : GermanFormat.decimal(longestRun)} von ${GermanFormat.decimal(target)} km',
          ),
      ],
    );
  }
}
