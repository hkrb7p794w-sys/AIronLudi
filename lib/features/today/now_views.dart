import 'package:coach_core/coach_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/providers.dart';
import '../../ui/components.dart';
import '../../ui/sport_style.dart';
import '../../ui/symbols.dart';
import '../evidence/evidence_views.dart';
import '../health/mobility_screen.dart';
import '../plan/my_week_screen.dart';
import '../plan/plan_screen.dart';
import 'plan_day_actions.dart';
import 'today_controller.dart';

/// Kleine farbige Kapsel für Phase, Countdown und Hinweise.
class CoachChip extends StatelessWidget {
  const CoachChip({super.key, required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(20)),
    child: Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color),
    ),
  );
}

/// „26.10.“
String shortDate(CalendarDay day) => '${day.day.toString().padLeft(2, '0')}.${day.month.toString().padLeft(2, '0')}.';

/// „Jetzt dran“: immer die erste Karte auf „Heute“, in beiden Modi gleich. Heutige Einheiten mit Soll, Ampel, eine
/// Zeile „warum“ und – wenn Regel und Plan sich widersprechen – beides mit der Entscheidung (Port von `NowSection`).
class NowSection extends ConsumerWidget {
  const NowSection({super.key, required this.snapshot, required this.focus});

  final TodaySnapshot snapshot;
  final TodayFocus focus;

  static WorkoutPlan? watchPlan(TodayFocusItem item, {required bool season}) {
    final sport = item.sport == null ? null : WorkoutSport.of(item.sport!);
    if (sport == null || (season && sport == WorkoutSport.swim)) return null;
    final text = [item.detail, item.target].where((part) => part.isNotEmpty).join(' · ');
    return GarminWorkout.plan(name: item.title, sport: sport, text: text.isEmpty ? item.title : text);
  }

  Color get _color => switch (focus.level) {
    RecoveryLevel.normal => Colors.green,
    RecoveryLevel.locker => Colors.orange,
    RecoveryLevel.pause => Colors.red,
    null => Colors.grey,
  };

  IconData get _icon {
    if (snapshot.advice?.mode == ScheduleAdviceMode.done) return Icons.verified;
    if (snapshot.advice?.mode == ScheduleAdviceMode.rest) return Icons.eco;
    return switch (focus.level) {
      RecoveryLevel.normal => Icons.check_circle,
      RecoveryLevel.locker => Icons.slow_motion_video,
      RecoveryLevel.pause => Icons.bed,
      null => Icons.help,
    };
  }

  static String countdown(int days) => switch (days) {
    0 => 'heute',
    1 => 'morgen',
    _ => 'in $days T.',
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(coachSettingsProvider);
    final plan = snapshot.plan;
    final today = plan.today;
    final theme = Theme.of(context);
    final secondary = TextStyle(fontSize: 13, color: theme.colorScheme.onSurfaceVariant);
    final season = settings.profile.mode == ProfileMode.season;
    final loggedIn = ref.watch(garminConnectProvider).isLoggedIn;
    final pause = settings.activeBreak(today);
    final advice = snapshot.advice;
    final note = settings.planAdjustments.note(Weekday.of(today), inWeekOf: today);
    final slots = settings.schedule(today).slots(Weekday.of(today));
    return FormSection(
      header: 'Jetzt dran · ${plan.weekday}, ${shortDate(today)}',
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 10,
            children: [
              Row(
                spacing: 12,
                children: [
                  ExcludeSemantics(
                    child: Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(color: _color, borderRadius: BorderRadius.circular(14)),
                      child: Icon(_icon, color: Colors.white, size: 30),
                    ),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(focus.headline, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
                        Text(
                          focus.level == null
                              ? 'Noch keine Erholungswerte für heute'
                              : 'Erholung: ${focus.level!.label}',
                          style: secondary,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (focus.detail.isNotEmpty) Text(focus.detail),
              if (focus.why case final why?) _IconLine(Icons.info_outline, why, secondary),
              if (focus.conflict case final conflict?)
                _IconLine(
                  Icons.sync_problem,
                  conflict,
                  const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: Colors.orange),
                ),
              if (snapshot.isFromYesterday)
                _IconLine(
                  Icons.schedule,
                  'Noch keine Garmin-Werte für heute – Einordnung mit den Werten von gestern.',
                  const TextStyle(fontSize: 13, color: Colors.orange),
                ),
              if (season)
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    CoachChip(text: plan.phase.rawValue, color: theme.colorScheme.primary),
                    if (plan.daysToMarathon >= 0)
                      CoachChip(text: 'Marathon ${countdown(plan.daysToMarathon)}', color: Colors.pink),
                    if (plan.daysToRace >= 0)
                      CoachChip(
                        text: '${settings.season.mainRaceName} ${countdown(plan.daysToRace)}',
                        color: Colors.teal,
                      ),
                  ],
                ),
            ],
          ),
        ),
        if (pause != null && pause.contains(today))
          ListTile(
            leading: const Icon(Icons.luggage_outlined),
            title: Text(
              'Pause bis ${GermanFormat.date(pause.end)} – keine Erinnerungen, nichts gilt als verpasst.',
              style: secondary,
            ),
          ),
        if (focus.items.isEmpty)
          ListTile(title: Text(season ? 'Heute nichts Festes.' : 'Heute nichts geplant.', style: secondary)),
        for (final item in focus.items) ...[
          FocusItemRow(item: item),
          // Auf Wunsch an die Uhr; die Schwimmeinheiten des Saisonplans legt weiterhin das Add-on an.
          if (watchPlan(item, season: season) case final plan? when loggedIn && item.status != SessionStatus.done)
            SendToWatchButton(plan: plan, day: snapshot.plan.today),
        ],
        if (MobilityPlanner.suggestToday(
          hasTraining: focus.items.any((item) => item.sport != null),
          recovery: focus.level,
          doneToday: settings.mobility.log.any((entry) => entry.day == snapshot.plan.today),
        ))
          ListTile(
            leading: const Icon(Icons.self_improvement),
            title: Text('Mobility für heute · ${settings.mobility.minutes} min'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const MobilityScreen())),
          ),
        // Wochenfokus gehört zum Saisonplan und nicht in ein eigenes Profil.
        if (season && (snapshot.today?.focus ?? '').isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(snapshot.today!.focus, style: secondary),
          ),
        if (advice != null) ...[
          if (note != null)
            ListTile(
              dense: true,
              leading: const Icon(Icons.event_note),
              title: Text('Heute: $note', style: secondary),
            ),
          if (advice.mode != ScheduleAdviceMode.done && (slots.isNotEmpty || note != null))
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: PlanDayActions(day: today, suggested: advice.move),
            ),
        ],
        if (focus.evidenceIDs.isNotEmpty) EvidenceDisclosure(ruleIDs: focus.evidenceIDs),
      ],
    );
  }
}

class _IconLine extends StatelessWidget {
  const _IconLine(this.icon, this.text, this.style);

  final IconData icon;
  final String text;
  final TextStyle style;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    spacing: 6,
    children: [
      Padding(
        padding: const EdgeInsets.only(top: 1),
        child: Icon(icon, size: 16, color: style.color),
      ),
      Expanded(child: Text(text, style: style)),
    ],
  );
}

/// Eine heutige Einheit: Sportart, Titel, Soll bzw. Soll/Ist, Status; Antippen zeigt den Ablauf.
class FocusItemRow extends StatefulWidget {
  const FocusItemRow({super.key, required this.item});

  final TodayFocusItem item;

  @override
  State<FocusItemRow> createState() => _FocusItemRowState();
}

class _FocusItemRowState extends State<FocusItemRow> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final secondary = TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant);
    final status = item.status;
    return InkWell(
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
                SportIcon(symbol: item.sport?.symbol ?? 'leaf.fill', color: item.sport?.color ?? Colors.teal.shade300),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    spacing: 2,
                    children: [
                      Text(item.title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
                      if (item.target.isNotEmpty) Text(item.target, style: secondary),
                      if (item.chip.isNotEmpty)
                        CoachChip(
                          text: item.chip,
                          color: item.chip == 'nur locker bewegen' ? Colors.red : Colors.orange,
                        ),
                    ],
                  ),
                ),
                if (status != null && status != SessionStatus.open && status != SessionStatus.planned)
                  SessionStatusBadge(status: status),
              ],
            ),
            if (_expanded && item.detail.isNotEmpty) Text(item.detail, style: secondary.copyWith(fontSize: 13)),
          ],
        ),
      ),
    );
  }
}

/// Status einer Einheit als kleine Kapsel.
class SessionStatusBadge extends StatelessWidget {
  const SessionStatusBadge({super.key, required this.status});

  final SessionStatus status;

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      SessionStatus.done => Colors.green,
      SessionStatus.partial || SessionStatus.substituted => Colors.orange,
      SessionStatus.missed => Colors.red,
      _ => Theme.of(context).colorScheme.onSurfaceVariant,
    };
    return CoachChip(text: status.label, color: color);
  }
}

/// Gemeinsame Vorschlagsliste: jeder Vorschlag mit Änderungen je Tag, Regelprüfung, Übernehmen und Verwerfen.
/// Übernommene bleiben mit Rückgängig stehen, solange die Seite offen ist (Port von `SuggestionsSection`).
class SuggestionsSection extends ConsumerStatefulWidget {
  const SuggestionsSection({super.key, required this.suggestions, this.title = 'Vorschläge'});

  final List<PlanSuggestion> suggestions;
  final String title;

  @override
  ConsumerState<SuggestionsSection> createState() => _SuggestionsSectionState();
}

class _SuggestionsSectionState extends ConsumerState<SuggestionsSection> {
  final List<({String id, String title, PlanAdjustments previous})> _applied = [];

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(coachSettingsProvider);
    final visible = [
      for (final suggestion in widget.suggestions)
        if (!settings.dismissedSuggestions.contains(suggestion.id) &&
            !_applied.any((entry) => entry.id == suggestion.id))
          suggestion,
    ];
    if (visible.isEmpty && _applied.isEmpty) return const SizedBox.shrink();
    return FormSection(
      header: widget.title,
      children: [
        for (final entry in _applied)
          ListTile(
            leading: const Icon(Icons.check),
            title: Text('Übernommen: ${entry.title}'),
            trailing: TextButton(
              onPressed: () => setState(() {
                settings.planAdjustments = entry.previous;
                _applied.remove(entry);
              }),
              child: const Text('Rückgängig'),
            ),
          ),
        for (final suggestion in visible)
          SuggestionCard(
            suggestion: suggestion,
            apply: () => setState(() {
              _applied.add((
                id: suggestion.id,
                title: suggestion.title,
                previous: PlanAdjustments.fromJson(settings.planAdjustments.toJson()) ?? PlanAdjustments(),
              ));
              settings.planAdjustments = suggestion.adjustments;
            }),
            adjust: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                fullscreenDialog: true,
                builder: (_) => NextWeekPlanScreen(monday: suggestion.week, initial: suggestion.schedule),
              ),
            ),
            dismiss: () {
              final dismissed = [...settings.dismissedSuggestions, suggestion.id];
              settings.dismissedSuggestions = dismissed.length > 60
                  ? dismissed.sublist(dismissed.length - 60)
                  : dismissed;
            },
          ),
      ],
    );
  }
}

/// Ein Vorschlag als Karte: Quelle, Titel, Begründung, Änderungen je Tag, was bleibt, neue Regelkonflikte.
class SuggestionCard extends StatelessWidget {
  const SuggestionCard({super.key, required this.suggestion, required this.apply, required this.dismiss, this.adjust});

  final PlanSuggestion suggestion;
  final VoidCallback apply;
  final VoidCallback dismiss;

  /// „Anpassen“: Vorschlag als Vorbelegung im Wochenplan-Editor.
  final VoidCallback? adjust;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final secondary = TextStyle(fontSize: 12, color: theme.colorScheme.onSurfaceVariant);
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 8,
        children: [
          Text(
            suggestion.source.label.toUpperCase(),
            style: secondary.copyWith(fontSize: 11, fontWeight: FontWeight.w600),
          ),
          Text(suggestion.title, style: const TextStyle(fontWeight: FontWeight.w600)),
          if (suggestion.reason.isNotEmpty) Text(suggestion.reason, style: secondary.copyWith(fontSize: 13)),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 4,
              children: [
                for (final change in suggestion.changes)
                  Semantics(
                    label:
                        '${change.weekday.long}: ${PlanSuggestion.text(change.before)} wird '
                        '${PlanSuggestion.text(change.after)}',
                    excludeSemantics: true,
                    child: Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: '${change.weekday.short}  ',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          TextSpan(
                            text: PlanSuggestion.text(change.before),
                            style: secondary.copyWith(decoration: TextDecoration.lineThrough),
                          ),
                          const TextSpan(text: '  →  '),
                          TextSpan(text: PlanSuggestion.text(change.after)),
                        ],
                      ),
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
              ],
            ),
          ),
          if (suggestion.unchanged.isNotEmpty) Text(suggestion.unchanged.join(' · '), style: secondary),
          if (suggestion.conflicts.isEmpty)
            const _IconLine(
              Icons.verified_user_outlined,
              'Planregeln geprüft: kein neuer Konflikt',
              TextStyle(fontSize: 12, color: Colors.green),
            ),
          for (final hint in suggestion.conflicts)
            _IconLine(Icons.warning, hint.message, const TextStyle(fontSize: 12, color: Colors.orange)),
          Wrap(
            spacing: 8,
            children: [
              FilledButton(onPressed: apply, child: const Text('Übernehmen')),
              if (adjust case final adjust?) OutlinedButton(onPressed: adjust, child: const Text('Anpassen')),
              TextButton(
                onPressed: dismiss,
                child: const Text('Verwerfen', style: TextStyle(color: Colors.red)),
              ),
            ],
          ),
          if (suggestion.evidenceIDs.isNotEmpty) EvidenceDisclosure(ruleIDs: suggestion.evidenceIDs),
        ],
      ),
    );
  }
}

/// Sonntags: Soll/Ist der Woche, Belastung, Höhepunkte.
class WeeklyReviewSection extends StatelessWidget {
  const WeeklyReviewSection({super.key, required this.review});

  final WeeklyReview review;

  String get _loadText {
    final load = review.load;
    final increase = load.increase;
    if (increase == null) return 'Belastung der letzten 7 Tage: ${load.last.toInt()}';
    final percent = (increase * 100).round();
    return 'Belastung ${load.last.toInt()} (${percent >= 0 ? '+' : ''}$percent % zum Schnitt)';
  }

  @override
  Widget build(BuildContext context) {
    final progress = review.progress;
    final secondary = TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant);
    return FormSection(
      header: 'Wochenrückblick',
      footer:
          'Belastung: Wert der Uhr, sonst aus Dauer × Intensität geschätzt; Vergleich mit dem Schnitt der drei Wochen '
          'davor.',
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 6,
            children: [
              Text(progress.text, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
              LinearProgressIndicator(
                value: progress.fraction.clamp(0, 1),
                color: progress.fraction >= 1 ? Colors.green : null,
              ),
            ],
          ),
        ),
        if (review.missed.isNotEmpty)
          ListTile(
            leading: const Icon(Icons.cancel_outlined),
            title: Text('Verpasst: ${review.missed.join(', ')}', style: secondary),
          ),
        ListTile(leading: const Icon(Icons.speed), title: Text(_loadText)),
        for (final line in review.highlights)
          ListTile(
            leading: const Icon(Icons.star, color: Colors.amber),
            title: Text(line),
          ),
        ListTile(
          leading: const Icon(Icons.edit_calendar),
          title: const Text('Nächste Woche planen'),
          textColor: Theme.of(context).colorScheme.primary,
          onTap: () =>
              Navigator.of(context)
                  .push(MaterialPageRoute<void>(fullscreenDialog: true, builder: (_) => const NextWeekPlanScreen())),
        ),
      ],
    );
  }
}

/// Hinweise, die heute zählen, als kleine Chips; Antippen öffnet die Einzelheiten.
class TodayHintsSection extends ConsumerWidget {
  const TodayHintsSection({super.key, required this.snapshot, required this.activities, required this.days});

  final TodaySnapshot snapshot;
  final List<GarminActivity> activities;
  final List<DailyMetrics> days;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(coachSettingsProvider);
    final today = snapshot.plan.today;
    final run = LoadCheck.running(activities, today: today);
    final sleep = DateTime.now().hour >= 17
        ? SleepCoach.report(days: days, settings: settings.sleep, goal: settings.profile.goal, today: today)
        : null;
    final load = snapshot.load;
    final loadWarning = load?.warning;
    if (run.warning == null && loadWarning == null && sleep == null) return const SizedBox.shrink();
    void open(Widget page) => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));
    return FormSection(
      header: 'Hinweise',
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            spacing: 8,
            children: [
              if (sleep != null)
                _HintChip(
                  text: 'Ins Bett um ${SleepCoach.clock(sleep.bedtimeMinutes)}',
                  icon: Icons.bedtime,
                  color: Colors.indigo,
                ),
              if (run.warning case final warning?)
                _HintChip(
                  text: 'Laufumfang +${((run.increase ?? 0) * 100).round()} %',
                  icon: Icons.warning,
                  color: Colors.orange,
                  onTap: () => open(HintPage(title: 'Laufumfang', text: warning, ruleIDs: const ['run.progression'])),
                ),
              if (loadWarning != null && load != null)
                _HintChip(
                  text: 'Belastung +${((load.increase ?? 0) * 100).round()} %',
                  icon: Icons.speed,
                  color: Colors.orange,
                  onTap: () => open(
                    HintPage(
                      title: 'Wochenbelastung',
                      text: loadWarning,
                      ruleIDs: load.evidenceIDs,
                      bySport: load.bySport,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _HintChip extends StatelessWidget {
  const _HintChip({required this.text, required this.icon, required this.color, this.onTap});

  final String text;
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: color.withValues(alpha: 0.15),
    shape: const StadiumBorder(),
    child: InkWell(
      customBorder: const StadiumBorder(),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          spacing: 6,
          children: [
            Icon(icon, size: 16, color: color),
            Text(
              text,
              style: TextStyle(fontWeight: FontWeight.w500, color: color),
            ),
          ],
        ),
      ),
    ),
  );
}

/// Einzelheiten eines Hinweises mit Grundlage.
class HintPage extends StatelessWidget {
  const HintPage({super.key, required this.title, required this.text, required this.ruleIDs, this.bySport = const {}});

  final String title;
  final String text;
  final List<String> ruleIDs;
  final Map<TrainingSport, double> bySport;

  @override
  Widget build(BuildContext context) {
    final sorted = bySport.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: ListView(
        children: [
          FormSection(children: [ListTile(title: Text(text))]),
          if (sorted.isNotEmpty)
            FormSection(
              header: 'Letzte 7 Tage je Sportart',
              children: [
                for (final entry in sorted) LabeledRow(label: entry.key.label, value: '${entry.value.toInt()}'),
              ],
            ),
          FormSection(children: [EvidenceDisclosure(ruleIDs: ruleIDs)]),
        ],
      ),
    );
  }
}

/// Symbol für eine Sportart des Tagesplans (Saisonplan).
IconData todayPlanIcon(TodayPlanSport sport) => switch (sport) {
  TodayPlanSport.swim => AppSymbols.of('figure.pool.swim'),
  TodayPlanSport.bike => AppSymbols.of('figure.outdoor.cycle'),
  TodayPlanSport.run => AppSymbols.of('figure.run'),
  TodayPlanSport.strength => AppSymbols.of('dumbbell.fill'),
  TodayPlanSport.rest => Icons.eco,
};
