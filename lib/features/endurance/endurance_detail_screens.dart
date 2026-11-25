part of 'endurance_screens.dart';

class _SlotTile extends StatelessWidget {
  const _SlotTile({required this.slot, this.showDay = false});

  final PlanSlot slot;
  final bool showDay;

  @override
  Widget build(BuildContext context) {
    final workout = slot.current;
    final status = switch (slot.status) {
      SlotStatus.completed => Icon(Icons.check_circle, color: AppColors.of(context).good),
      SlotStatus.missed => const Icon(Icons.cancel, color: AppPalette.grey),
      SlotStatus.planned => slot.isAdapted ? Icon(Icons.auto_fix_high, color: AppColors.of(context).caution) : null,
    };
    return ListTile(
      leading: SportIcon(
        symbol: workout.sport.symbol,
        color: workout.isRest ? AppPalette.grey : _sportColor(workout.sport),
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
          FuelForSlotSection(slot: slot),
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
              'Uhren und Apps, die Trainings importieren. Zwift: die .zwo-Datei in den Ordner '
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
