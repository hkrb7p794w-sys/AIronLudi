import 'dart:async';

import 'package:coach_core/coach_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/storage.dart';
import '../../services/garmin/garmin_workout_service.dart';
import '../../services/providers.dart';
import '../../ui/components.dart';
import '../../ui/sport_style.dart';
import '../evidence/evidence_views.dart';
import 'plan_controller.dart';

/// Farbe und Symbol je Einheit (wie `SportStyle.swift`).
extension PlannedUnitKindStyle on PlannedUnitKind {
  Color get color => switch (this) {
    PlannedUnitKind.bike || PlannedUnitKind.bikeOptional => Colors.orange,
    PlannedUnitKind.swim => Colors.blue,
    PlannedUnitKind.quality || PlannedUnitKind.easyRun || PlannedUnitKind.longRun => Colors.green,
    PlannedUnitKind.gym => Colors.purple,
  };

  String get symbol => switch (this) {
    PlannedUnitKind.bike || PlannedUnitKind.bikeOptional => 'figure.outdoor.cycle',
    PlannedUnitKind.swim => 'figure.pool.swim',
    PlannedUnitKind.quality => 'speedometer',
    PlannedUnitKind.easyRun => 'figure.run',
    PlannedUnitKind.longRun => 'road.lanes',
    PlannedUnitKind.gym => 'dumbbell.fill',
  };
}

String _short(CalendarDay day) => '${day.day.toString().padLeft(2, '0')}.${day.month.toString().padLeft(2, '0')}.';

/// Plan im Saisonmodus: alle Einheiten einer Woche mit Inhalt, Woche für Woche durch die Saison (Port von `PlanView`).
class PlanScreen extends ConsumerStatefulWidget {
  const PlanScreen({super.key});

  @override
  ConsumerState<PlanScreen> createState() => _PlanScreenState();
}

class _PlanScreenState extends ConsumerState<PlanScreen> {
  late final PlanController _controller = PlanController(schedule: ref.read(seasonScheduleProvider))
    ..addListener(_changed);

  @override
  void initState() {
    super.initState();
    unawaited(_reload());
  }

  @override
  void dispose() {
    _controller
      ..removeListener(_changed)
      ..dispose();
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  Future<void> _reload() async {
    final results = await (ref.read(activityRepositoryProvider).all(), ref.read(gymRepositoryProvider).all()).wait;
    if (!mounted) return;
    final settings = ref.read(coachSettingsProvider);
    _controller.update(
      activities: results.$1,
      gymDays: [for (final record in results.$2) record.session.day],
      config: settings.season,
      decisions: settings.competitionDecisions,
    );
  }

  @override
  Widget build(BuildContext context) {
    // Saisonwerte oder Wettkampf-Entscheidungen geändert: Einheiten neu aufbauen.
    ref.listen(coachSettingsProvider, (_, _) => unawaited(_reload()));
    ref.listen(appModelProvider.select((model) => model.lastSync), (_, _) => unawaited(_reload()));
    final controller = _controller;
    final week = controller.week;
    final info = controller.phaseInfo;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Plan'),
        actions: [
          if (!controller.isCurrentWeek)
            TextButton(onPressed: () => controller.show(controller.currentWeekIndex), child: const Text('Heute')),
          IconButton(
            tooltip: 'Saison',
            icon: const Icon(Icons.calendar_month),
            onPressed: () => showModalBottomSheet<void>(
              context: context,
              isScrollControlled: true,
              showDragHandle: true,
              builder: (_) => SeasonOverviewSheet(controller: controller),
            ),
          ),
        ],
      ),
      body: controller.schedule == null
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text('Kein Plan\nDer Saisonplan konnte nicht geladen werden.', textAlign: TextAlign.center),
              ),
            )
          : week == null
          ? const SizedBox.shrink()
          : ListView(
              padding: const EdgeInsets.only(bottom: 32),
              children: [
                _WeekHeader(controller: controller, week: week),
                FormSection(
                  header: 'Einheiten',
                  footer:
                      'Erledigt-Haken kommen aus Garmin und den Krafteinheiten der App. Testwerte unter Einstellungen.',
                  children: [
                    for (final unit in controller.units)
                      _PlanUnitRow(
                        unit: unit,
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => PlanUnitDetailScreen(unit: unit, week: week),
                          ),
                        ),
                      ),
                  ],
                ),
                if (info != null) ...[
                  FormSection(
                    header: 'Musterwoche · ${week.ph}',
                    children: [ListTile(title: Text(info.mw))],
                  ),
                  FormSection(
                    header: 'Wenn die Zeit knapp ist',
                    children: [ListTile(title: Text(info.prio))],
                  ),
                ],
              ],
            ),
    );
  }
}

class _WeekHeader extends StatelessWidget {
  const _WeekHeader({required this.controller, required this.week});

  final PlanController controller;
  final PlanWeek week;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final secondary = theme.colorScheme.onSurfaceVariant;
    return FormSection(
      children: [
        Row(
          children: [
            IconButton(
              tooltip: 'Vorherige Woche',
              icon: const Icon(Icons.chevron_left),
              onPressed: controller.canGoBack ? () => controller.step(-1) : null,
            ),
            Expanded(
              child: Column(
                spacing: 2,
                children: [
                  Text(controller.weekTitle, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
                  Text(controller.weekRange, style: TextStyle(color: secondary)),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(week.ph, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Nächste Woche',
              icon: const Icon(Icons.chevron_right),
              onPressed: controller.canGoForward ? () => controller.step(1) : null,
            ),
          ],
        ),
        if (controller.requiredCount > 0)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Column(
              spacing: 6,
              children: [
                Row(
                  children: [
                    const Text('Erledigt'),
                    const Spacer(),
                    Text('${controller.doneCount} von ${controller.requiredCount}', style: TextStyle(color: secondary)),
                  ],
                ),
                LinearProgressIndicator(value: controller.doneCount / controller.requiredCount),
              ],
            ),
          ),
        if (week.f.isNotEmpty)
          ListTile(
            dense: true,
            leading: const Icon(Icons.flag_outlined),
            title: Text(week.f, style: TextStyle(color: secondary)),
          ),
      ],
    );
  }
}

class _PlanUnitRow extends StatelessWidget {
  const _PlanUnitRow({required this.unit, required this.onTap});

  final PlannedUnit unit;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Opacity(
    opacity: unit.kind == PlannedUnitKind.bikeOptional ? 0.7 : 1,
    child: ListTile(
      onTap: onTap,
      leading: SportIcon(symbol: unit.kind.symbol, color: unit.kind.color),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            unit.kind.label,
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: unit.kind.color),
          ),
          Text(unit.title, style: const TextStyle(fontWeight: FontWeight.w600)),
        ],
      ),
      subtitle: Text(unit.detail, maxLines: 2, overflow: TextOverflow.ellipsis),
      trailing: unit.done
          ? const Icon(Icons.check_circle, color: Colors.green, semanticLabel: 'erledigt')
          : unit.decision == PlannedUnitDecision.open
          ? const Icon(Icons.help_outline, color: Colors.orange, semanticLabel: 'Entscheidung offen')
          : const Icon(Icons.chevron_right),
    ),
  );
}

/// Alle Wochen der Saison nach Phasen; Tippen springt zur Woche.
class SeasonOverviewSheet extends StatefulWidget {
  const SeasonOverviewSheet({super.key, required this.controller});

  final PlanController controller;

  @override
  State<SeasonOverviewSheet> createState() => _SeasonOverviewSheetState();
}

class _SeasonOverviewSheetState extends State<SeasonOverviewSheet> {
  final _current = GlobalKey();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_current.currentContext case final context?) {
        unawaited(Scrollable.ensureVisible(context, alignment: 0.5));
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final weeks = controller.schedule?.weeks ?? const <PlanWeek>[];
    final phases = <String>[];
    for (final week in weeks) {
      if (phases.lastOrNull != week.ph) phases.add(week.ph);
    }
    final primary = Theme.of(context).colorScheme.primary;
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      maxChildSize: 0.95,
      builder: (context, scroll) => Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 8, 0),
            child: Row(
              children: [
                Text('Saison', style: Theme.of(context).textTheme.titleMedium),
                const Spacer(),
                TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Fertig')),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              controller: scroll,
              padding: const EdgeInsets.only(bottom: 32),
              children: [
                for (final phase in phases)
                  FormSection(
                    header: phase,
                    children: [
                      for (final (index, week) in weeks.indexed)
                        if (week.ph == phase)
                          ListTile(
                            key: index == controller.weekIndex ? _current : null,
                            title: Text(
                              week.monday == null ? week.w : 'ab ${_short(week.monday!)}',
                              style: TextStyle(
                                fontWeight: index == controller.currentWeekIndex ? FontWeight.bold : null,
                              ),
                            ),
                            subtitle: Text(
                              [
                                week.qc,
                                if (week.lr > 0) 'Longrun ${GermanFormat.decimal(week.lr)} km',
                                if (week.f.isNotEmpty) week.f,
                              ].where((part) => part.isNotEmpty).join(' · '),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            trailing: index == controller.currentWeekIndex
                                ? Text(
                                    'jetzt',
                                    style: TextStyle(fontWeight: FontWeight.bold, color: primary),
                                  )
                                : null,
                            onTap: () {
                              controller.show(index);
                              Navigator.of(context).pop();
                            },
                          ),
                    ],
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Eine Einheit im Detail: Ablauf mit Paces/Watt, Ausrüstung, Wettkampf-Entscheidung, Grundlage (Port von
/// `PlanUnitDetailView`).
class PlanUnitDetailScreen extends ConsumerWidget {
  const PlanUnitDetailScreen({super.key, required this.unit, required this.week});

  final PlannedUnit unit;
  final PlanWeek week;

  /// Lauf- und Radeinheiten lassen sich an die Uhr senden; Schwimmen legt das Add-on wöchentlich an.
  static WorkoutSport? watchSport(PlannedUnitKind kind) => switch (kind) {
    PlannedUnitKind.quality || PlannedUnitKind.easyRun || PlannedUnitKind.longRun => WorkoutSport.run,
    PlannedUnitKind.bike || PlannedUnitKind.bikeOptional => WorkoutSport.bike,
    PlannedUnitKind.swim || PlannedUnitKind.gym => null,
  };

  /// Heute, wenn die Woche läuft oder vorbei ist; bei künftigen Wochen ihr Montag.
  static CalendarDay defaultDay(PlanWeek week, {CalendarDay? today}) {
    final now = today ?? CalendarDay.today();
    final monday = CalendarDay.tryParse(week.w);
    if (monday == null) return now;
    return monday > now ? monday : now;
  }

  static String gymTarget(PlannedExercise exercise) {
    final reps = exercise.reps == null ? '${exercise.sets} Sätze' : '${exercise.sets} × ${exercise.reps}';
    final weight = exercise.weightKg == null ? '' : ' · ${GermanFormat.number(exercise.weightKg!)} kg';
    return reps + weight;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(coachSettingsProvider);
    final tokens = PlanTokens(settings.season);
    final theme = Theme.of(context);
    final secondary = theme.colorScheme.onSurfaceVariant;
    final workout = unit.gymWorkout;
    final sport = watchSport(unit.kind);
    final loggedIn = ref.watch(garminConnectProvider).isLoggedIn;
    final equipment = SwimStepText.equipment(unit.swimSteps);
    return Scaffold(
      appBar: AppBar(title: Text(unit.kind.label)),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          FormSection(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  spacing: 14,
                  children: [
                    SportIcon(symbol: unit.kind.symbol, color: unit.kind.color, size: 48),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        spacing: 2,
                        children: [
                          Text(
                            unit.kind.label,
                            style: TextStyle(fontWeight: FontWeight.w600, color: unit.kind.color),
                          ),
                          Text(unit.title, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
                          if (unit.done)
                            const Row(
                              spacing: 4,
                              children: [
                                Icon(Icons.check_circle, color: Colors.green, size: 16),
                                Text('Erledigt', style: TextStyle(color: Colors.green, fontSize: 13)),
                              ],
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (unit.kind == PlannedUnitKind.swim && unit.swimSteps.isNotEmpty) ...[
            FormSection(
              header: 'Ablauf',
              footer: unit.swimMeters == null
                  ? null
                  : 'Gesamt ${unit.swimMeters} m · CSS ${PlanTokens.mmss(settings.season.cssSecondsPer100m)} /100 m',
              children: [
                for (final line in SwimStepText.lines(unit.swimSteps, tokens: tokens))
                  Padding(
                    padding: EdgeInsets.fromLTRB(16 + (line.length - line.trimLeft().length) * 8.0, 6, 16, 6),
                    child: Text(line.trim()),
                  ),
              ],
            ),
            if (equipment.isNotEmpty)
              FormSection(
                header: 'Mitnehmen',
                children: [
                  for (final item in equipment)
                    ListTile(dense: true, leading: const Icon(Icons.shopping_bag_outlined), title: Text(item)),
                ],
              ),
          ] else if (workout != null) ...[
            FormSection(
              header: 'Übungen',
              children: [
                for (final exercise in workout.exercises) LabeledRow(label: exercise.name, value: gymTarget(exercise)),
              ],
            ),
            if (workout.note.isNotEmpty)
              FormSection(
                children: [
                  ListTile(
                    title: Text(workout.note, style: TextStyle(fontSize: 13, color: secondary)),
                  ),
                ],
              ),
          ] else
            FormSection(
              header: 'Ablauf',
              children: [ListTile(title: Text(unit.detail))],
            ),
          if (unit.zwiftCode case final code?)
            FormSection(
              footer: 'Watt-Angaben aus der FTP unter Einstellungen › Saison & Ziele.',
              children: [
                LabeledRow(label: 'Zwift-Workout', value: code == 'RAMP' ? 'FTP Ramp Test Lite' : 'GAC $code'),
                LabeledRow(label: 'FTP', value: '${settings.season.ftpWatts} W'),
              ],
            ),
          if (unit.isCompetition) _CompetitionSection(unit: unit, week: week),
          if (sport != null && loggedIn && !unit.done)
            FormSection(
              footer: 'Tag im nächsten Schritt wählen. Nur diese Einheit, nichts wird automatisch gesendet.',
              children: [
                SendToWatchButton(
                  plan: GarminWorkout.plan(
                    name: unit.title,
                    sport: sport,
                    text: unit.detail.isEmpty ? unit.title : unit.detail,
                  ),
                  day: defaultDay(week),
                ),
              ],
            ),
          ...unitGuideSections(UnitGuides.guide(unit)),
          FormSection(children: [EvidenceDisclosure(ruleIDs: unit.evidenceIDs)]),
        ],
      ),
    );
  }
}

class _CompetitionSection extends ConsumerWidget {
  const _CompetitionSection({required this.unit, required this.week});

  final PlannedUnit unit;
  final PlanWeek week;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(coachSettingsProvider);
    final key = SeasonSchedule.decisionKey(week, unit.kind);
    final decision = settings.competitionDecisions[key] ?? PlannedUnitDecision.open;
    final alternative = unit.alternative;
    return FormSection(
      header: 'Wettkampf-Einheit 🏁',
      footer: 'Renntempo-Einheiten sind ein Angebot: Ablehnen ersetzt sie durch die Alternative, ohne mehr Umfang.',
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: SegmentedButton<PlannedUnitDecision>(
            segments: const [
              ButtonSegment(value: PlannedUnitDecision.open, label: Text('Offen')),
              ButtonSegment(value: PlannedUnitDecision.accepted, label: Text('Annehmen')),
              ButtonSegment(value: PlannedUnitDecision.rejected, label: Text('Ablehnen')),
            ],
            selected: {decision},
            onSelectionChanged: (selection) {
              final value = selection.first;
              settings.competitionDecisions = {
                for (final entry in settings.competitionDecisions.entries)
                  if (entry.key != key) entry.key: entry.value,
                if (value != PlannedUnitDecision.open) key: value,
              };
            },
          ),
        ),
        if (alternative != null && decision != PlannedUnitDecision.rejected)
          ListTile(
            title: Text(
              'Alternative bei Ablehnen',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            subtitle: Text(alternative),
          ),
      ],
    );
  }
}

/// Ausführliche Erklärung einer Einheit: wozu, Schritt für Schritt, Gefühl, typische Fehler, Begriffe (Port von
/// `UnitGuideSections`).
List<Widget> unitGuideSections(UnitGuide guide) => [
  FormSection(
    header: 'Worum es geht',
    children: [ListTile(title: Text(guide.purpose))],
  ),
  if (guide.steps.isNotEmpty)
    FormSection(
      header: 'So gehst du vor',
      children: [
        for (final (index, step) in guide.steps.indexed)
          ListTile(
            leading: CircleAvatar(radius: 11, child: Text('${index + 1}', style: const TextStyle(fontSize: 12))),
            title: Text(step),
          ),
      ],
    ),
  FormSection(
    header: 'So soll es sich anfühlen',
    children: [ListTile(leading: const Icon(Icons.monitor_heart_outlined), title: Text(guide.feel))],
  ),
  if (guide.mistakes.isNotEmpty)
    FormSection(
      header: 'Typische Fehler',
      children: [
        for (final mistake in guide.mistakes)
          ListTile(leading: const Icon(Icons.warning_amber_rounded), title: Text(mistake)),
      ],
    ),
  if (guide.terms.isNotEmpty)
    FormSection(
      header: 'Begriffe',
      children: [
        for (final term in guide.terms)
          ExpansionTile(
            title: Text(term.name),
            expandedAlignment: Alignment.centerLeft,
            childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            children: [Text(term.explanation)],
          ),
      ],
    ),
];

/// Eine Einheit des eigenen Wochenplans im Detail (Port von `SessionGuideView`).
class SessionGuideScreen extends StatelessWidget {
  const SessionGuideScreen({super.key, required this.slot});

  final SessionSlot slot;

  @override
  Widget build(BuildContext context) {
    final isIntervals = slot.intensity == SessionIntensity.hard && slot.sport == TrainingSport.run;
    return Scaffold(
      appBar: AppBar(title: Text(slot.sport.label)),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          FormSection(
            children: [
              ListTile(
                leading: SportIcon(symbol: slot.sport.symbol, color: slot.sport.color, size: 48),
                title: Text(
                  slot.intensity.label,
                  style: TextStyle(fontWeight: FontWeight.w600, color: slot.sport.color),
                ),
                subtitle: Text(
                  slot.title,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Text(
                  slot.guide,
                  style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
              ),
            ],
          ),
          ...unitGuideSections(UnitGuides.guideForSlot(slot)),
          FormSection(
            children: [
              EvidenceDisclosure(
                ruleIDs: isIntervals ? const ['run.4x4', 'intensity.distribution'] : const ['intensity.distribution'],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Knopf „An die Uhr senden“: Tag wählen, Schritte prüfen, senden. Nur auf Wunsch je Einheit.
class SendToWatchButton extends StatelessWidget {
  const SendToWatchButton({super.key, required this.plan, required this.day});

  final WorkoutPlan plan;
  final CalendarDay day;

  @override
  Widget build(BuildContext context) => ListTile(
    leading: const Icon(Icons.watch),
    title: const Text('An die Uhr senden'),
    onTap: () => Navigator.of(context).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => SendToWatchScreen(plan: plan, initialDay: day),
      ),
    ),
  );
}

/// Tag wählen, Schritte prüfen, senden (Port von `SendToWatchSheet`).
class SendToWatchScreen extends ConsumerStatefulWidget {
  const SendToWatchScreen({super.key, required this.plan, required this.initialDay});

  final WorkoutPlan plan;
  final CalendarDay initialDay;

  @override
  ConsumerState<SendToWatchScreen> createState() => _SendToWatchScreenState();
}

class _SendToWatchScreenState extends ConsumerState<SendToWatchScreen> {
  late CalendarDay _day = widget.initialDay;
  bool _sending = false;
  String? _message;

  Future<void> _pickDay() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _day.referenceDate,
      firstDate: now.subtract(const Duration(days: 1)),
      lastDate: now.add(const Duration(days: 366)),
      locale: const Locale('de', 'DE'),
    );
    if (picked != null) setState(() => _day = CalendarDay.fromDate(picked));
  }

  Future<void> _send() async {
    setState(() => _sending = true);
    final message = await GarminWorkoutService.send(
      widget.plan,
      day: _day,
      connect: ref.read(garminConnectProvider),
      settings: ref.read(coachSettingsProvider),
    );
    if (!mounted) return;
    setState(() {
      _message = message;
      _sending = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(coachSettingsProvider);
    final sentBefore = settings.sentWorkouts.ids[SentWorkouts.key(name: widget.plan.name, day: _day)] != null;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.plan.name),
        automaticallyImplyLeading: false,
        actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Fertig'))],
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          FormSection(
            footer: sentBefore ? 'Für diesen Tag schon gesendet – erneutes Senden ersetzt das Workout.' : null,
            children: [ListTile(title: const Text('Tag'), trailing: Text(GermanFormat.date(_day)), onTap: _pickDay)],
          ),
          FormSection(
            header: 'Schritte auf der Uhr',
            children: [
              for (final line in GarminWorkout.summary(widget.plan.steps)) ListTile(dense: true, title: Text(line)),
            ],
          ),
          if (_message case final message?) FormSection(children: [ListTile(title: Text(message))]),
          FormSection(
            footer:
                'Das Workout landet im Garmin-Connect-Kalender und beim nächsten Synchronisieren auf der Uhr. Ziele '
                '(Pace, Puls) stehen als Notiz am Schritt. Garmin kann diese inoffizielle Schnittstelle jederzeit '
                'ändern.',
            children: [
              ListTile(
                enabled: !_sending,
                title: Text(_sending ? 'Wird gesendet …' : 'Senden'),
                textColor: Theme.of(context).colorScheme.primary,
                onTap: _send,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
