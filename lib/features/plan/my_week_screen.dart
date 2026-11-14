import 'dart:async';

import 'package:coach_core/coach_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/settings/coach_settings.dart';
import '../../data/storage.dart';
import '../../services/providers.dart';
import '../../ui/components.dart';
import '../../ui/sport_style.dart';
import '../../ui/symbols.dart';
import '../activities/activity_detail_screen.dart';
import '../activities/activity_parts.dart';
import '../onboarding/onboarding_screen.dart';
import '../onboarding/schedule_editor.dart';
import '../today/now_views.dart';
import '../today/today_controller.dart';
import 'plan_screen.dart';

/// Plan für Profile ohne Saisonplan: die eigene Woche, Ziel und Hinweise zum Plan (Port von `MyWeekView`).
class MyWeekScreen extends ConsumerStatefulWidget {
  const MyWeekScreen({super.key});

  @override
  ConsumerState<MyWeekScreen> createState() => _MyWeekScreenState();
}

class _MyWeekScreenState extends ConsumerState<MyWeekScreen> {
  List<GarminActivity> _activities = const [];
  List<CalendarDay> _gymDays = const [];

  @override
  void initState() {
    super.initState();
    unawaited(_reload());
  }

  Future<void> _reload() async {
    final results = await (ref.read(activityRepositoryProvider).all(), ref.read(gymRepositoryProvider).all()).wait;
    if (!mounted) return;
    setState(() {
      _activities = results.$1;
      _gymDays = [for (final record in results.$2) record.session.day];
    });
  }

  Future<void> _present(Widget screen) async {
    await Navigator.of(context).push(MaterialPageRoute<void>(fullscreenDialog: true, builder: (_) => screen));
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(appModelProvider.select((model) => model.lastSync), (_, _) => unawaited(_reload()));
    final settings = ref.watch(coachSettingsProvider);
    final reminders = ref.read(reminderServiceProvider);
    final profile = settings.profile;
    final day = CalendarDay.today();
    final today = Weekday.of(day);
    final thisWeek = settings.schedule(day);
    final adjustments = settings.planAdjustments;
    final monday = PlanAdjustments.monday(day);
    final runWeek = RunPlanner.week(profile: profile, schedule: thisWeek, monday: monday, activities: _activities);
    final sessions = TodayController.sessionWeek(
      settings: settings,
      activities: _activities,
      gymDays: _gymDays,
      today: day,
    );
    final extras = [
      for (final activity in _activities)
        if (sessions.extraIDs.contains(activity.id) ||
            (ManualActivity.isManual(activity.id) && _onOrAfter(activity.day, monday)))
          activity,
    ];
    return Scaffold(
      appBar: AppBar(
        title: const Text('Plan'),
        actions: [
          IconButton(
            tooltip: 'Nächste Woche',
            icon: const Icon(Icons.edit_calendar),
            onPressed: () => _present(const NextWeekPlanScreen()),
          ),
          IconButton(
            tooltip: 'Training nachtragen',
            icon: const Icon(Icons.add),
            onPressed: () => _present(const ManualActivityScreen()),
          ),
          TextButton(onPressed: () => _present(const ScheduleEditorScreen()), child: const Text('Bearbeiten')),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          _GoalHeader(profile: profile),
          MissedSessionSection(week: sessions, onSaved: _reload),
          FormSection(
            header: runWeek == null
                ? 'Diese Woche'
                : 'Diese Woche · ${runWeek.phase.label} · ${runWeek.totalMinutes} min Laufen',
            footer: profile.schedule.isEmpty
                ? 'Noch kein Wochenplan. Tippe oben auf „Bearbeiten“.'
                : adjustments.changesInWeekOf(day).isNotEmpty
                ? 'Änderungen gelten nur für diese Woche; danach gilt wieder dein Wochenplan.'
                : runWeek == null
                ? null
                : 'Laufminuten aus deinem Schnitt der letzten vier Wochen (${runWeek.baselineMinutes} min): höchstens '
                      '10 % mehr, jede vierte Woche leichter, vor einem Wettkampf weniger.',
            children: [
              for (final weekday in Weekday.values)
                () {
                  final date = monday.adding(weekday.index);
                  final future = weekday.index >= today.index;
                  final canAdjust = future && thisWeek.slots(weekday).isNotEmpty && !sessions.allCounted(date);
                  final target = canAdjust
                      ? PlanMoveAdvisor.options(
                          weekday,
                          schedule: thisWeek,
                          profile: profile,
                          today: day,
                          limit: 1,
                        ).firstOrNull
                      : null;
                  final row = _WeekDayRow(
                    weekday: weekday,
                    slots: thisWeek.slots(weekday),
                    isToday: weekday == today,
                    note: adjustments.note(weekday, inWeekOf: day),
                    runs: [
                      for (final run in runWeek?.sessions ?? const <RunSession>[])
                        if (run.weekday == weekday) run,
                    ],
                    results: sessions.resultsOn(date),
                    select: (slot) =>
                        Navigator.of(context)
                            .push(MaterialPageRoute<void>(builder: (_) => SessionGuideScreen(slot: slot))),
                    actions: future ? _PlanDayMenu(day: date) : null,
                  );
                  if (!canAdjust) return row;
                  // Wischen wie in Swift: nach links auslassen, nach rechts auf den besten Tag verschieben.
                  return Dismissible(
                    key: ValueKey('day-${date.iso}'),
                    direction: target == null ? DismissDirection.endToStart : DismissDirection.horizontal,
                    background: target == null
                        ? const SizedBox.shrink()
                        : Container(
                            color: Colors.blue,
                            alignment: Alignment.centerLeft,
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: Text('Auf ${target.short}', style: const TextStyle(color: Colors.white)),
                          ),
                    secondaryBackground: Container(
                      color: Colors.red,
                      alignment: Alignment.centerRight,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: const Text('Auslassen', style: TextStyle(color: Colors.white)),
                    ),
                    confirmDismiss: (direction) async {
                      if (direction == DismissDirection.endToStart) {
                        reminders.skip(date);
                      } else if (target != null) {
                        reminders.move(date, to: target);
                      }
                      return false;
                    },
                    child: row,
                  );
                }(),
            ],
          ),
          _WeekTotalsSection(
            totals: SessionMatcher.totals(
              planned: [for (final result in sessions.results) result.planned],
              activities: _activities,
              monday: monday,
            ),
            counts: sessions.results,
          ),
          if (extras.isNotEmpty)
            FormSection(
              header: 'Außerplanmäßig und nachgetragen',
              children: [
                for (final activity in extras)
                  ActivitySummaryRow(
                    activity: activity,
                    onTap: () async {
                      await Navigator.of(context)
                          .push(MaterialPageRoute<void>(builder: (_) => ActivityDetailScreen(activity: activity)));
                      await _reload();
                    },
                    trailing: ManualActivity.isManual(activity.id)
                        ? IconButton(
                            tooltip: 'Löschen',
                            icon: const Icon(Icons.delete_outline),
                            onPressed: () async {
                              await ref.read(activityRepositoryProvider).delete([activity.id]);
                              await _reload();
                            },
                          )
                        : null,
                  ),
              ],
            ),
          ScheduleHintsSection(hints: ScheduleCheck.hints(profile.schedule, profile)),
        ],
      ),
    );
  }
}

class _GoalHeader extends StatelessWidget {
  const _GoalHeader({required this.profile});

  final UserProfile profile;

  @override
  Widget build(BuildContext context) {
    final event = profile.event;
    final String subtitle;
    if (event != null) {
      final days = CalendarDay.today().daysUntil(event.date);
      subtitle = '${event.name} · ${days > 0 ? 'in $days Tagen' : (days == 0 ? 'heute' : 'vorbei')}';
    } else {
      subtitle = profile.sports.map((sport) => sport.shortLabel).join(' · ');
    }
    return FormSection(
      children: [
        ListTile(
          leading: SportIcon(symbol: profile.goal.symbol, color: Theme.of(context).colorScheme.primary, size: 40),
          title: Text(profile.goal.label, style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: Text(subtitle),
        ),
      ],
    );
  }
}

class _WeekDayRow extends StatelessWidget {
  const _WeekDayRow({
    required this.weekday,
    required this.slots,
    required this.isToday,
    required this.note,
    required this.runs,
    required this.results,
    required this.select,
    this.actions,
  });

  final Weekday weekday;
  final List<SessionSlot> slots;
  final bool isToday;
  final String? note;
  final List<RunSession> runs;
  final List<SessionResult> results;
  final ValueChanged<SessionSlot> select;
  final Widget? actions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final secondary = theme.colorScheme.onSurfaceVariant;
    final primary = theme.colorScheme.primary;
    final note = this.note;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 4, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 12,
        children: [
          SizedBox(
            width: 28,
            child: Text(
              weekday.short,
              style: TextStyle(
                fontWeight: isToday ? FontWeight.bold : FontWeight.w600,
                color: isToday ? primary : secondary,
              ),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 10,
              children: [
                if (note != null) Text(note, style: const TextStyle(fontSize: 12, color: Colors.orange)),
                if (slots.isEmpty) Text('Frei', style: TextStyle(color: secondary)),
                for (final (index, slot) in slots.indexed)
                  () {
                    final result = results.where((result) => result.planned.index == index).firstOrNull;
                    final run = runs.where((run) => run.slot == slot).firstOrNull;
                    return InkWell(
                      onTap: () => select(slot),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        spacing: 10,
                        children: [
                          SportIcon(symbol: slot.sport.symbol, color: slot.sport.color, size: 28),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              spacing: 2,
                              children: [
                                Text(
                                  run == null ? slot.title : '${slot.title} · ${run.minutes} min',
                                  style: const TextStyle(fontWeight: FontWeight.w500),
                                ),
                                Text(run?.detail ?? slot.guide, style: TextStyle(fontSize: 12, color: secondary)),
                                if (result != null) ...[
                                  Wrap(
                                    spacing: 8,
                                    crossAxisAlignment: WrapCrossAlignment.center,
                                    children: [
                                      SessionStatusBadge(status: result.status),
                                      if (result.actualMinutes != null || result.status != SessionStatus.planned)
                                        Text(result.compareText, style: TextStyle(fontSize: 12, color: secondary)),
                                    ],
                                  ),
                                  if (result.intensityNote case final intensity?)
                                    Text(intensity, style: const TextStyle(fontSize: 12, color: Colors.orange)),
                                ],
                                Row(
                                  spacing: 4,
                                  children: [
                                    Icon(Icons.info_outline, size: 14, color: primary),
                                    Text('Ausführlich', style: TextStyle(fontSize: 12, color: primary)),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  }(),
              ],
            ),
          ),
          ?actions,
        ],
      ),
    );
  }
}

/// Soll gegen Ist je Sportart und wie viele Einheiten geschafft sind.
class _WeekTotalsSection extends StatelessWidget {
  const _WeekTotalsSection({required this.totals, required this.counts});

  final List<({TrainingSport sport, int planned, int actual})> totals;
  final List<SessionResult> counts;

  @override
  Widget build(BuildContext context) {
    if (totals.isEmpty) return const SizedBox.shrink();
    final done = counts.where((result) => result.status.counts).length;
    final secondary = Theme.of(context).colorScheme.onSurfaceVariant;
    return FormSection(
      header: 'Soll / Ist · $done von ${counts.length} Einheiten',
      footer:
          'Erledigt heißt: gleiche Sportart, mindestens ${(SessionMatcher.doneShare * 100).round()} % der geplanten '
          'Dauer. Rad statt Lauf zählt als „anders gemacht“, ein Spaziergang hakt keinen Lauf ab.',
      children: [
        for (final total in totals)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Column(
              spacing: 4,
              children: [
                Row(
                  spacing: 8,
                  children: [
                    Icon(AppSymbols.of(total.sport.symbol), size: 18, color: total.sport.color),
                    Text(total.sport.label),
                    const Spacer(),
                    Text('${total.actual} / ${total.planned} min', style: TextStyle(color: secondary)),
                  ],
                ),
                if (total.planned > 0)
                  LinearProgressIndicator(
                    value: (total.actual / total.planned).clamp(0, 1).toDouble(),
                    color: total.sport.color,
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Menü je Tag: verschieben, diese Woche auslassen, rückgängig.
class _PlanDayMenu extends ConsumerWidget {
  const _PlanDayMenu({required this.day});

  final CalendarDay day;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(coachSettingsProvider);
    final reminders = ref.read(reminderServiceProvider);
    final weekday = Weekday.of(day);
    final schedule = settings.schedule(day);
    final hasSlots = schedule.slots(weekday).isNotEmpty;
    final note = settings.planAdjustments.note(weekday, inWeekOf: day);
    final options = PlanMoveAdvisor.options(
      weekday,
      schedule: schedule,
      profile: settings.profile,
      today: CalendarDay.today(),
      limit: 6,
    );
    if (!hasSlots && note == null) return const SizedBox(width: 44);
    return PopupMenuButton<VoidCallback>(
      tooltip: '${weekday.long} anpassen',
      icon: const Icon(Icons.more_horiz),
      onSelected: (action) => action(),
      itemBuilder: (_) => [
        if (hasSlots) ...[
          for (final target in options)
            PopupMenuItem(
              value: () => reminders.move(day, to: target),
              child: Text('Verschieben auf ${target.long}'),
            ),
          PopupMenuItem(
            value: () => reminders.skip(day),
            child: const Text('Diese Woche auslassen', style: TextStyle(color: Colors.red)),
          ),
        ],
        if (note != null)
          PopupMenuItem(
            value: () => settings.planAdjustments = settings.planAdjustments..undo(weekday, inWeekOf: day),
            child: const Text('Rückgängig'),
          ),
      ],
    );
  }
}

/// Verpasste Einheit von gestern (oder früher in der Woche): nachholen, streichen oder „war krank“ (Port von
/// `MissedSessionSection`).
class MissedSessionSection extends ConsumerWidget {
  const MissedSessionSection({super.key, required this.week, this.onSaved});

  final SessionWeek? week;

  /// Nach „Doch gemacht – nachtragen“ (neue Aktivität gespeichert).
  final Future<void> Function()? onSaved;

  /// Schon nachgeholte Einheiten dieser Woche: von einem vergangenen Tag auf einen späteren verschoben.
  static int makeUps(CoachSettings settings, CalendarDay today) => settings.planAdjustments
      .changesInWeekOf(today)
      .where((change) => change.from.index < today.weekdayIndex && (change.to?.index ?? -1) > change.from.index)
      .length;

  /// Merken, worüber entschieden ist; Einträge älter als zwei Wochen fallen heraus.
  static void handle(CoachSettings settings, Iterable<String> ids, {CalendarDay? today}) {
    final cutoff = (today ?? CalendarDay.today()).adding(-14);
    final kept = settings.handledMissed.where((id) {
      final day = CalendarDay.tryParse(id.length >= 10 ? id.substring(0, 10) : id);
      return day != null && day >= cutoff;
    });
    settings.handledMissed = {...kept, ...ids}.toList()..sort();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final week = this.week;
    if (week == null) return const SizedBox.shrink();
    final settings = ref.watch(coachSettingsProvider);
    final today = CalendarDay.today();
    final missed = MissedSessions.open(
      week,
      handled: settings.handledMissed.toSet(),
      pause: settings.trainingBreak,
    ).firstOrNull;
    if (missed == null) return const SizedBox.shrink();
    final session = missed.planned;
    final makeUp = MissedSessions.makeUpDay(
      session,
      schedule: settings.schedule(today),
      profile: settings.profile,
      today: today,
      makeUpsThisWeek: makeUps(settings, today),
    );
    final reminders = ref.read(reminderServiceProvider);
    return FormSection(
      header: 'Verpasst',
      footer:
          '„War krank“: Die nächsten ${MissedSessions.illnessEasyDays} Tage empfiehlt die App höchstens locker. '
          'Höchstens ${MissedSessions.maxMakeUpsPerWeek}× pro Woche nachholen, sonst staut sich die Belastung.',
      children: [
        ListTile(
          leading: const Icon(Icons.cancel_outlined, color: Colors.red),
          title: Text(
            '${Weekday.of(session.day).long}: ${session.slot.title} nicht gemacht',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          subtitle: Text(
            makeUp == null
                ? 'Diese Woche passt kein Nachholtag mehr. Einfach streichen: Eine verpasste Einheit kostet nichts.'
                : 'Nachholen geht am ${makeUp.long} – ohne zwei harte Tage hintereinander.',
          ),
        ),
        if (makeUp != null)
          ListTile(
            leading: const Icon(Icons.subdirectory_arrow_right),
            title: Text('Am ${makeUp.long} nachholen'),
            onTap: () {
              reminders.move(session.day, to: makeUp);
              handle(settings, [missed.id]);
            },
          ),
        ListTile(
          leading: const Icon(Icons.add_circle_outline),
          title: const Text('Doch gemacht – nachtragen'),
          onTap: () async {
            final saved = await Navigator.of(context).push<bool>(
              MaterialPageRoute(
                fullscreenDialog: true,
                builder: (_) =>
                    ManualActivityScreen(sport: session.slot.sport, day: session.day, minutes: session.targetMinutes),
              ),
            );
            if (saved ?? false) {
              handle(settings, [missed.id]);
              await onSaved?.call();
            }
          },
        ),
        ListTile(
          leading: const Icon(Icons.skip_next_outlined),
          title: const Text('Streichen'),
          onTap: () => handle(settings, [missed.id]),
        ),
        ListTile(
          leading: const Icon(Icons.medical_services_outlined),
          title: const Text('War krank'),
          onTap: () {
            settings.illnessDay = today;
            handle(settings, [for (final result in MissedSessions.open(week, handled: const {})) result.id]);
          },
        ),
      ],
    );
  }
}

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
        leading: TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Abbrechen')),
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
