part of 'gym_screen.dart';

class SessionRow extends StatelessWidget {
  const SessionRow({super.key, required this.record, required this.onTap});

  final StoredGymSession record;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final session = record.session;
    return ListTile(
      title: Text(session.title, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(
        '${_day(session.day)} · ${session.doneSetCount} Sätze · '
        '${GermanFormat.number((session.volumeKg / 100).roundToDouble() / 10)} t',
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (record.savedToHealth)
            const Icon(Icons.favorite, size: 14, color: AppPalette.pink, semanticLabel: 'In Health'),
          const DisclosureChevron(),
        ],
      ),
      onTap: onTap,
    );
  }
}

/// Eine gespeicherte Einheit: Daten, Health, Garmin-Abgleich und die Sätze.
class SessionDetailScreen extends ConsumerStatefulWidget {
  const SessionDetailScreen({super.key, required this.record});

  final StoredGymSession record;

  @override
  ConsumerState<SessionDetailScreen> createState() => _SessionDetailScreenState();
}

class _SessionDetailScreenState extends ConsumerState<SessionDetailScreen> {
  late StoredGymSession _record = widget.record;
  String? _message;
  bool _working = false;

  GymRepository get _repository => ref.read(gymRepositoryProvider);

  /// Nach einer Aktion den gespeicherten Datensatz neu lesen, damit der Status sofort stimmt.
  Future<void> _run(Future<String> Function() action) async {
    setState(() => _working = true);
    final text = await action();
    final fresh = await _repository.byID(_record.session.id);
    if (!mounted) return;
    setState(() {
      _working = false;
      _message = text;
      if (fresh != null) _record = fresh;
    });
  }

  @override
  Widget build(BuildContext context) {
    final session = _record.session;
    final connect = ref.watch(garminConnectProvider);
    return Scaffold(
      appBar: AppBar(
        title: Text(session.title),
        actions: [GymShareButton(onShare: (context) => shareSession(context, ref, session))],
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          FormSection(
            children: [
              LabeledRow(label: 'Datum', value: _day(session.day)),
              if (session.end case final end?)
                LabeledRow(label: 'Dauer', value: _duration(end.difference(session.start))),
              LabeledRow(label: 'Bewegte Last', value: '${GermanFormat.number(session.volumeKg)} kg'),
              if (_record.savedToHealth)
                ListTile(
                  leading: const Icon(Icons.favorite, color: AppPalette.pink),
                  title: Text('In $healthStoreName gespeichert', style: const TextStyle(color: AppPalette.pink)),
                )
              else
                ListTile(
                  title: Text('In $healthStoreName speichern'),
                  enabled: !_working,
                  onTap: () => _run(
                    () => GymController.saveToHealth(
                      session,
                      repository: _repository,
                      writer: ref.read(workoutWriterProvider),
                    ),
                  ),
                ),
              if (_message case final message?) ListTile(title: Text(message, style: AppText.footnote(context))),
            ],
          ),
          if (connect.isLoggedIn) _garminSection(connect),
          for (final exercise in session.exercises)
            FormSection(
              header: exercise.name,
              children: [
                for (final (index, set) in exercise.sets.indexed)
                  LabeledRow(
                    label: 'Satz ${index + 1}',
                    value: set.weightKg > 0
                        ? '${GermanFormat.number(set.weightKg)} kg × ${set.reps}'
                        : '${set.reps} Wdh.',
                  ),
              ],
            ),
        ],
      ),
    );
  }

  /// Abgleich mit Garmin: Status, Sätze in die Uhr-Aufzeichnung schreiben, als eigene Aktivität hochladen,
  /// ursprüngliche Sätze der Uhr wiederherstellen.
  Widget _garminSection(GarminConnectSession connect) {
    final session = _record.session;
    final link = session.garmin;
    final strength = ref.read(garminStrengthServiceProvider);
    final gym = ref.read(coachSettingsProvider).gym;
    final Widget status = switch (link?.status) {
      GarminLinkStatus.enriched => ListTile(
        leading: Icon(Icons.check_circle, color: AppColors.of(context).info),
        title: Text('Sätze in der Aufzeichnung der Uhr'),
      ),
      GarminLinkStatus.uploaded => ListTile(
        leading: Icon(Icons.check_circle, color: AppColors.of(context).info),
        title: Text('Als eigene Aktivität hochgeladen'),
      ),
      GarminLinkStatus.pending => const ListTile(
        leading: Icon(Icons.hourglass_empty),
        title: Text('Wartet auf die Aufzeichnung der Uhr'),
      ),
      GarminLinkStatus.failed => ListTile(
        leading: Icon(Icons.warning_amber, color: AppColors.of(context).caution),
        title: Text(link?.note ?? 'Abgleich fehlgeschlagen', style: TextStyle(color: AppColors.of(context).caution)),
      ),
      null when _record.uploadedToGarmin => ListTile(
        leading: Icon(Icons.check_circle, color: AppColors.of(context).info),
        title: Text('Als eigene Aktivität hochgeladen'),
      ),
      null => const ListTile(leading: Icon(Icons.circle_outlined), title: Text('Noch nicht in Garmin Connect')),
    };
    return FormSection(
      header: 'Garmin Connect',
      footer:
          'Abgleichen schreibt die Sätze in die Krafttraining-Aufzeichnung der Uhr (Start höchstens 2 Stunden '
          'entfernt) – Kalorien und Puls der Uhr bleiben, es entsteht keine zweite Aktivität. Hochladen legt eine '
          'eigene Aktivität an; nur, wenn die Uhr nicht dabei war.',
      children: [
        status,
        if (_working) const LinearProgressIndicator(),
        ...switch (link?.status) {
          GarminLinkStatus.enriched => [
            if (link?.activityID case final id?) ...[
              // Z. B. nach besserer Übungszuordnung: neu aus der gesicherten Uhr-Aufzeichnung schreiben.
              ListTile(
                leading: const Icon(Icons.refresh),
                title: const Text('Sätze erneut übertragen'),
                enabled: !_working,
                onTap: () => _run(
                  () => strength.enrich(session, activityID: id, garmin: connect, gym: gym, now: DateTime.now()),
                ),
              ),
              if (strength.hasBackup(id))
                ListTile(
                  title: Text(
                    'Ursprüngliche Sätze der Uhr wiederherstellen',
                    style: TextStyle(color: AppColors.of(context).alert),
                  ),
                  enabled: !_working,
                  onTap: () => _run(() => strength.restore(session, activityID: id, garmin: connect)),
                ),
            ],
          ],
          GarminLinkStatus.uploaded => const <Widget>[],
          _ when _record.uploadedToGarmin => const <Widget>[],
          _ => [
            ListTile(
              leading: const Icon(Icons.sync),
              title: const Text('Mit Aufzeichnung der Uhr abgleichen'),
              enabled: !_working,
              onTap: () => _run(() async {
                await _repository.setGarmin(
                  session.id,
                  GarminLink(status: GarminLinkStatus.pending, updatedAt: DateTime.now()),
                );
                return await strength.reconcile(garmin: connect, gym: gym) ?? 'Nichts zu tun.';
              }),
            ),
            ListTile(
              leading: const Icon(Icons.upload),
              title: const Text('Als eigene Aktivität hochladen'),
              enabled: !_working,
              onTap: () => _run(() async {
                final text = await GymController.uploadToGarmin(session, repository: _repository, garmin: connect);
                if ((await _repository.byID(session.id))?.uploadedToGarmin ?? false) {
                  await _repository.setGarmin(
                    session.id,
                    GarminLink(status: GarminLinkStatus.uploaded, note: text, updatedAt: DateTime.now()),
                  );
                }
                return text;
              }),
            ),
          ],
        },
      ],
    );
  }
}

/// Alle Einheiten; Löschen erst nach Rückfrage – eine Einheit ist Verlauf und Grundlage der Progression.
class GymHistoryScreen extends ConsumerStatefulWidget {
  const GymHistoryScreen({super.key});

  @override
  ConsumerState<GymHistoryScreen> createState() => _GymHistoryScreenState();
}

class _GymHistoryScreenState extends ConsumerState<GymHistoryScreen> {
  List<StoredGymSession> _records = const [];

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final records = await ref.read(gymRepositoryProvider).all();
    if (!mounted) return;
    setState(() => _records = [...records]..sort((a, b) => b.session.start.compareTo(a.session.start)));
  }

  Future<bool> _confirmDelete() async =>
      await showDialog<bool>(
        context: context,
        builder: (dialog) => AlertDialog(
          title: const Text('Einheit löschen?'),
          content: const Text('Sätze, Bestleistungen und die Progression dieser Einheit gehen verloren.'),
          actions: [
            TextButton(onPressed: () => Navigator.of(dialog).pop(false), child: const Text('Abbrechen')),
            TextButton(
              onPressed: () => Navigator.of(dialog).pop(true),
              child: Text('Löschen', style: TextStyle(color: AppColors.of(context).alert)),
            ),
          ],
        ),
      ) ??
      false;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Verlauf')),
    body: ListView(
      children: [
        for (final record in _records)
          Dismissible(
            key: ValueKey(record.session.id),
            direction: DismissDirection.endToStart,
            background: Container(
              color: AppColors.of(context).alert,
              alignment: Alignment.centerRight,
              padding: const EdgeInsets.only(right: 16),
              child: const Icon(Icons.delete, color: AppPalette.onColor),
            ),
            confirmDismiss: (_) => _confirmDelete(),
            onDismissed: (_) async {
              setState(() => _records = [..._records]..remove(record));
              await ref.read(gymRepositoryProvider).delete(record.session.id);
            },
            child: SessionRow(
              record: record,
              onTap: () async {
                await Navigator.of(context)
                    .push(MaterialPageRoute<void>(builder: (_) => SessionDetailScreen(record: record)));
                await _load();
              },
            ),
          ),
      ],
    ),
  );
}

/// Auswertung: Kalender, Hinweise, Muskeln, Fortschritt je Übung, Sätze je Muskel.
class GymAnalysisScreen extends ConsumerWidget {
  const GymAnalysisScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gym = ref.watch(gymControllerProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Auswertung')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          _CalendarSection(gym: gym),
          GymHintsSection(gym: gym),
          MuscleOverviewSection(sessions: gym.sessions),
          _ProgressSection(gym: gym),
          _VolumeSection(gym: gym),
        ],
      ),
    );
  }
}

/// Einheiten je Woche (8 Wochen) und Serie.
class _CalendarSection extends StatelessWidget {
  const _CalendarSection({required this.gym});

  final GymController gym;

  @override
  Widget build(BuildContext context) {
    final weeks = GymCalendar.weeks(sessions: gym.sessions, today: gym.today);
    final streak = GymCalendar.streak(sessions: gym.sessions, today: gym.today);
    final color = Theme.of(context).colorScheme.primary;
    final maxY = weeks.fold<int>(1, (top, week) => week.sessions > top ? week.sessions : top).toDouble();
    return FormSection(
      header: 'Kalender',
      children: [
        Semantics(
          label: 'Einheiten je Woche, letzte 8 Wochen',
          excludeSemantics: true,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 16, 16, 8),
            child: SizedBox(
              height: 140,
              child: BarChart(
                BarChartData(
                  maxY: maxY,
                  barGroups: [
                    for (final (index, week) in weeks.indexed)
                      BarChartGroupData(
                        x: index,
                        barRods: [
                          BarChartRodData(
                            toY: week.sessions.toDouble(),
                            width: 16,
                            color: color,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ],
                      ),
                  ],
                  titlesData: FlTitlesData(
                    topTitles: const AxisTitles(),
                    rightTitles: const AxisTitles(),
                    leftTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: true, reservedSize: 24, interval: 1),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (value, meta) => SideTitleWidget(
                          meta: meta,
                          child: Text(
                            DateFormat('d.M.', 'de_DE').format(weeks[value.toInt()].monday.referenceDate),
                            style: AppText.caption(context),
                          ),
                        ),
                      ),
                    ),
                  ),
                  gridData: const FlGridData(drawVerticalLine: false, horizontalInterval: 1),
                  borderData: FlBorderData(show: false),
                ),
              ),
            ),
          ),
        ),
        ListTile(
          leading: Icon(
            streak > 0 ? Icons.local_fire_department : Icons.local_fire_department_outlined,
            color: streak > 0 ? AppColors.of(context).caution : null,
          ),
          title: Text(streak == 1 ? '1 Woche in Folge trainiert' : '$streak Wochen in Folge trainiert'),
        ),
      ],
    );
  }
}

/// Tipps für die nächste Einheit: KI-Hinweise oder Regeln.
class GymHintsSection extends ConsumerWidget {
  const GymHintsSection({super.key, required this.gym});

  final GymController gym;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (gym.progress.isEmpty) return const SizedBox.shrink();
    final ai = ref.watch(aiClientProvider);
    return FormSection(
      header: 'Tipps für die nächste Einheit',
      footer: 'Quelle: ${gym.hintSource}. Die Gewichte bestimmen die Regeln; die KI formuliert nur.',
      children: [
        if (ai.allows('gym_hints'))
          Align(
            alignment: Alignment.centerRight,
            child: IconButton(
              tooltip: 'Neue Tipps',
              icon: const Icon(Icons.auto_awesome),
              onPressed: gym.isLoadingHints
                  ? null
                  : () => gym.loadHints(ai, goal: ref.read(coachSettingsProvider).coachingProfile.goal),
            ),
          ),
        for (final hint in gym.hints) ListTile(dense: true, leading: const Icon(Icons.north_east), title: Text(hint)),
        if (gym.isLoadingHints) const LinearProgressIndicator(),
      ],
    );
  }
}

class _ProgressSection extends StatefulWidget {
  const _ProgressSection({required this.gym});

  final GymController gym;

  @override
  State<_ProgressSection> createState() => _ProgressSectionState();
}

class _ProgressSectionState extends State<_ProgressSection> {
  static const _urgent = {ProgressStatus.increase, ProgressStatus.restart, ProgressStatus.check};

  @override
  Widget build(BuildContext context) {
    final progress = widget.gym.progress;
    final active = progress.where((item) => _urgent.contains(item.status)).toList();
    final rest = progress.where((item) => !_urgent.contains(item.status)).toList();
    final secondary = AppText.footnote(context).copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant);
    return FormSection(
      header: 'Gewichts-Progression',
      footer:
          'Regel: alle Arbeitssätze an der Obergrenze → +2,5–5 % und wieder unten im Bereich anfangen. '
          'Bleiben in allen Sätzen 4 oder mehr Wiederholungen in Reserve, sofort steigern. Die Tagesampel verschiebt '
          'nur den Zeitpunkt.',
      children: [
        if (progress.isEmpty)
          ListTile(title: Text('Noch keine Einheiten mit Gewicht im Verlauf.', style: secondary))
        else if (active.isEmpty)
          ListTile(
            title: Text(
              'Gerade keine Übung an der Obergrenze – Gewichte halten, Wiederholungen steigern.',
              style: secondary,
            ),
          ),
        for (final item in active) _ProgressRow(item: item, gym: widget.gym),
        if (rest.isNotEmpty)
          ExpansionTile(
            title: Text('${rest.length} weitere Übungen'),
            children: [for (final item in rest) _ProgressRow(item: item, gym: widget.gym)],
          ),
      ],
    );
  }
}

class _ProgressRow extends StatelessWidget {
  const _ProgressRow({required this.item, required this.gym});

  final ExerciseProgress item;
  final GymController gym;

  @override
  Widget build(BuildContext context) {
    final tag = switch (item.status) {
      ProgressStatus.increase => (
        item.nextWeightKg == null ? '↑' : '↑ ${GermanFormat.number(item.nextWeightKg!)} kg',
        AppColors.of(context).good,
      ),
      ProgressStatus.check => ('prüfen', AppColors.of(context).alert),
      ProgressStatus.restart => ('Wiedereinstieg', AppColors.of(context).caution),
      _ => null,
    };
    return ListTile(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ExerciseDetailScreen(exerciseID: item.exerciseID, gym: gym),
        ),
      ),
      title: Text(item.name, style: AppText.callout(context).copyWith(fontWeight: FontWeight.bold)),
      subtitle: Text(
        '${item.weightKg > 0 ? '${GermanFormat.number(item.weightKg)} kg' : 'Körpergewicht'} × '
        '${item.reps.join('/')} · Ziel ${item.target.lower}–${item.target.upper}',
      ),
      trailing: tag == null
          ? null
          : Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(color: tag.$2.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(12)),
              child: Text(tag.$1, style: AppText.caption(context).copyWith(fontWeight: FontWeight.bold)),
            ),
    );
  }
}

class _VolumeSection extends StatelessWidget {
  const _VolumeSection({required this.gym});

  final GymController gym;

  @override
  Widget build(BuildContext context) => FormSection(
    header: 'Sätze je Muskel · 7 Tage',
    footer:
        'Grün ab 5 Sätzen pro Woche: solider Kraftaufbau neben dem Ausdauertraining. Mehr Sätze bringen mehr, aber mit '
        'abnehmendem Ertrag. Für Lauf- und Radökonomie zählt Beintraining am meisten.',
    children: [
      if ((gym.daysSinceLegs ?? 99) > 10)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: _Warning(
            gym.daysSinceLegs == null ? 'Beine bisher nicht erfasst.' : 'Beine zuletzt vor ${gym.daysSinceLegs} Tagen.',
          ),
        ),
      for (final group in MuscleVolume.groups)
        () {
          final count = gym.volume[group] ?? 0;
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Row(
              children: [
                SizedBox(width: 90, child: Text(group.rawValue)),
                Expanded(
                  child: LiquidProgressBar(
                    value: (count > 14 ? 14 : count) / 14,
                    color: count == 0
                        ? AppColors.of(context).alert
                        : (count >= MuscleVolume.goodLower
                              ? AppColors.of(context).good
                              : AppColors.of(context).caution),
                  ),
                ),
                SizedBox(
                  width: 28,
                  child: Text(
                    '$count',
                    textAlign: TextAlign.right,
                    style: const TextStyle(fontFeatures: [FontFeature.tabularFigures()]),
                  ),
                ),
              ],
            ),
          );
        }(),
    ],
  );
}
