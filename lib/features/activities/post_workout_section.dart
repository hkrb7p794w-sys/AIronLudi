import 'package:coach_core/coach_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/providers.dart';
import '../../ui/components.dart';
import '../evidence/evidence_views.dart';
import '../plan/my_week_screen.dart';
import '../today/now_views.dart';

/// „Nach dem Training“ auf Heute: Anstrengung 1–10 abfragen, gegen den Plan auswerten, morgen ggf. entschärfen
/// (Port von `PostWorkoutSection`).
class PostWorkoutSection extends ConsumerStatefulWidget {
  const PostWorkoutSection({super.key, required this.activities, required this.sessions});

  /// Heutige Aktivitäten.
  final List<GarminActivity> activities;
  final SessionWeek? sessions;

  @override
  ConsumerState<PostWorkoutSection> createState() => _PostWorkoutSectionState();
}

class _PostWorkoutSectionState extends ConsumerState<PostWorkoutSection> {
  ({CalendarDay day, PlanAdjustments previous})? _applied;

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(coachSettingsProvider);
    final candidates = [
      for (final activity in widget.activities)
        if ((activity.durationSeconds ?? 0) >= SessionMatcher.minimumSeconds) activity,
    ]..sort((a, b) => (b.startLocal ?? '').compareTo(a.startLocal ?? ''));
    final activity = candidates.where((activity) => !settings.closedReviews.contains('${activity.id}')).firstOrNull;
    if (activity == null) return const SizedBox.shrink();
    final key = '${activity.id}';
    final effort = settings.efforts[key];
    return FormSection(
      header: 'Nach dem Training',
      footer: effort == null
          ? '1 = sehr leicht, 10 = maximal. Daraus und aus der Dauer schätzt die App die Belastung (session RPE).'
          : null,
      children: [
        ListTile(
          title: Text(
            activity.name ?? activity.typeKey ?? 'Training',
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 17),
          ),
        ),
        if (effort != null)
          ..._review(activity, effort)
        else
          _EffortPicker(pick: (value) => settings.efforts = {...settings.efforts, key: value}),
        ListTile(
          title: Text(effort == null ? 'Ohne Angabe schließen' : 'Fertig'),
          textColor: Theme.of(context).colorScheme.primary,
          onTap: () {
            final closed = [...settings.closedReviews, key];
            settings.closedReviews = closed.length > 60 ? closed.sublist(closed.length - 60) : closed;
          },
        ),
      ],
    );
  }

  List<Widget> _review(GarminActivity activity, int effort) {
    final settings = ref.read(coachSettingsProvider);
    final tomorrow = CalendarDay.today().adding(1);
    final personal = settings.profile.mode == ProfileMode.personal;
    final sessions = widget.sessions;
    final result = PostWorkout.review(
      activity: activity,
      effort: effort,
      planned: sessions?.results.where((result) => result.activityID == activity.id).firstOrNull,
      planKnown: sessions != null,
      tomorrow: tomorrow,
      tomorrowSchedule: personal ? settings.schedule(tomorrow) : null,
    );
    final suggestion = result.tomorrow;
    final plan = suggestion == null
        ? null
        : PlanSuggestion.postWorkout(
            suggestion,
            activityID: activity.id,
            profile: settings.profile,
            adjustments: settings.planAdjustments,
          );
    final applied = _applied;
    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: 6,
          children: [
            Row(
              spacing: 6,
              children: [
                const Icon(Icons.verified, color: Colors.green, size: 18),
                Expanded(
                  child: Text(
                    result.headline,
                    style: const TextStyle(fontWeight: FontWeight.w600, color: Colors.green),
                  ),
                ),
              ],
            ),
            for (final point in result.points) Text(point),
          ],
        ),
      ),
      if (applied != null && applied.day == tomorrow) ...[
        const ListTile(leading: Icon(Icons.check), title: Text('Morgen ist jetzt locker geplant.')),
        ListTile(
          leading: const Icon(Icons.undo),
          title: const Text('Rückgängig'),
          onTap: () => setState(() {
            settings.planAdjustments = applied.previous;
            _applied = null;
          }),
        ),
      ] else if (suggestion != null && plan != null && !settings.dismissedSuggestions.contains(plan.id))
        // Gleiche Karte wie in der Vorschlagsliste: Diff, Regelprüfung, Übernehmen/Anpassen/Verwerfen.
        SuggestionCard(
          suggestion: plan,
          apply: () => setState(() {
            _applied = (
              day: suggestion.day,
              previous: PlanAdjustments.fromJson(settings.planAdjustments.toJson()) ?? PlanAdjustments(),
            );
            settings.planAdjustments = plan.adjustments;
          }),
          adjust: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              fullscreenDialog: true,
              builder: (_) => NextWeekPlanScreen(monday: plan.week, initial: plan.schedule),
            ),
          ),
          dismiss: () {
            final dismissed = [...settings.dismissedSuggestions, plan.id];
            settings.dismissedSuggestions = dismissed.length > 60
                ? dismissed.sublist(dismissed.length - 60)
                : dismissed;
          },
        ),
      ListTile(
        dense: true,
        title: Text('Anstrengung ändern ($effort/10)'),
        textColor: Theme.of(context).colorScheme.primary,
        onTap: () => settings.efforts = {
          for (final entry in settings.efforts.entries)
            if (entry.key != '${activity.id}') entry.key: entry.value,
        },
      ),
      if (result.evidenceIDs.isNotEmpty) EvidenceDisclosure(ruleIDs: result.evidenceIDs),
    ];
  }
}

/// Zehn Tasten statt Schieberegler: ein Tipp, mit einer Hand.
class _EffortPicker extends StatelessWidget {
  const _EffortPicker({required this.pick});

  final ValueChanged<int> pick;

  static Color color(int value) =>
      value <= PostWorkout.easyEffort ? Colors.green : (value < PostWorkout.hardEffort ? Colors.orange : Colors.red);

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 6,
      children: [
        const Text('Wie anstrengend war es?'),
        Row(
          spacing: 4,
          children: [
            for (var value = 1; value <= 10; value++)
              Expanded(
                child: Semantics(
                  label: 'Anstrengung $value von 10',
                  button: true,
                  excludeSemantics: true,
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      padding: EdgeInsets.zero,
                      minimumSize: const Size(0, 36),
                      foregroundColor: color(value),
                      side: BorderSide(color: color(value).withValues(alpha: 0.5)),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    onPressed: () => pick(value),
                    child: Text('$value'),
                  ),
                ),
              ),
          ],
        ),
      ],
    ),
  );
}
