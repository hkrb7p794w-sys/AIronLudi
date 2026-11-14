import 'package:coach_core/coach_core.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../ui/components.dart';
import '../../ui/sport_style.dart';
import '../today/now_views.dart';

/// „Sa., 14. Nov.“ wie `Formatters.day`.
String formatDay(CalendarDay day) => DateFormat('EEE, d. MMM', 'de_DE').format(day.referenceDate);

/// Kleine Etiketten: Quelle(n) und Intensität (Port von `FeedBadges`).
class FeedBadges extends StatelessWidget {
  const FeedBadges({super.key, required this.sources, required this.intensity});

  final List<ActivitySource> sources;
  final SessionKind? intensity;

  @override
  Widget build(BuildContext context) {
    final secondary = Theme.of(context).colorScheme.onSurfaceVariant;
    final intensity = this.intensity;
    return Wrap(
      spacing: 4,
      runSpacing: 4,
      children: [
        if (intensity != null && intensity != SessionKind.gym)
          _Badge(intensity.label, intensity == SessionKind.easy ? Colors.green : Colors.orange),
        for (final source in sources) _Badge(source.label, secondary),
      ],
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge(this.text, this.color);

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(10)),
    child: Text(
      text,
      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color),
    ),
  );
}

/// Zeit in den fünf Herzfrequenzzonen als ein Balken (Port von `ZoneShareBar`).
class ZoneShareBar extends StatelessWidget {
  const ZoneShareBar({super.key, required this.shares});

  final List<double> shares;
  static const _colors = [Colors.grey, Colors.blue, Colors.green, Colors.orange, Colors.red];

  @override
  Widget build(BuildContext context) {
    String percent(int index) => '${(shares[index] * 100).round()}';
    return Semantics(
      label: 'Zonen: ${[for (var i = 0; i < shares.length; i++) 'Zone ${i + 1} ${percent(i)} Prozent'].join(', ')}',
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 4,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(5),
            child: SizedBox(
              height: 10,
              child: Row(
                spacing: 1,
                children: [
                  for (final (index, share) in shares.indexed)
                    if (share > 0)
                      Expanded(
                        flex: (share * 1000).round().clamp(1, 1000),
                        child: ColoredBox(color: _colors[index % _colors.length]),
                      ),
                ],
              ),
            ),
          ),
          Wrap(
            spacing: 8,
            children: [
              for (var index = 0; index < shares.length; index++)
                Text(
                  'Z${index + 1} ${percent(index)} %',
                  style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Was fehlt und was das heißt – statt leerer Felder (Port von `MissingDataSection`).
class MissingDataSection extends StatelessWidget {
  const MissingDataSection({super.key, required this.notes});

  final List<String> notes;

  @override
  Widget build(BuildContext context) {
    if (notes.isEmpty) return const SizedBox.shrink();
    final secondary = Theme.of(context).colorScheme.onSurfaceVariant;
    return FormSection(
      header: 'Fehlende Daten',
      children: [
        for (final note in notes)
          ListTile(
            dense: true,
            leading: Icon(Icons.info_outline, color: secondary),
            title: Text(note, style: TextStyle(fontSize: 13, color: secondary)),
          ),
      ],
    );
  }
}

/// Zeile im Verlauf: Sportart, Titel, Kernwerte, Intensität, Quellen und Bezug zum Plan (Port von `FeedRow`).
class FeedRow extends StatelessWidget {
  const FeedRow({super.key, required this.entry, this.onTap});

  final FeedEntry entry;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final sport = SessionMatcher.sport(entry.sport);
    final secondary = Theme.of(context).colorScheme.onSurfaceVariant;
    final planned = entry.planned;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: 12,
          children: [
            SportIcon(symbol: sport.symbol, color: sport.color),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 3,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          entry.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(formatDay(entry.day), style: TextStyle(fontSize: 12, color: secondary)),
                    ],
                  ),
                  if (entry.values.isNotEmpty)
                    Text(entry.values.join(' · '), style: TextStyle(fontSize: 12, color: secondary)),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      FeedBadges(sources: entry.sources, intensity: entry.intensity),
                      if (planned != null) SessionStatusBadge(status: planned.status),
                    ],
                  ),
                  if (planned != null)
                    Text(
                      'Plan: ${planned.planned.slot.title}${planned.intensityNote == null ? '' : ' · ${planned.intensityNote}'}',
                      style: TextStyle(fontSize: 11, color: secondary),
                    ),
                ],
              ),
            ),
            if (onTap != null) Icon(Icons.chevron_right, color: secondary),
          ],
        ),
      ),
    );
  }
}

/// Zeile einer Aktivität: Symbol, Name, Datum und Kernwerte (Port von `ActivitySummaryRow`).
class ActivitySummaryRow extends StatelessWidget {
  const ActivitySummaryRow({super.key, required this.activity, this.onTap, this.trailing});

  final GarminActivity activity;
  final VoidCallback? onTap;
  final Widget? trailing;

  static String symbol(ActivitySport sport) => switch (sport) {
    ActivitySport.run => 'figure.run',
    ActivitySport.bike => 'figure.outdoor.cycle',
    ActivitySport.swim => 'figure.pool.swim',
    ActivitySport.strength => 'dumbbell.fill',
    ActivitySport.other => 'figure.mixed.cardio',
  };

  static Color color(ActivitySport sport) => switch (sport) {
    ActivitySport.run => Colors.green,
    ActivitySport.bike => Colors.orange,
    ActivitySport.swim => Colors.blue,
    ActivitySport.strength => Colors.purple,
    ActivitySport.other => Colors.teal,
  };

  @override
  Widget build(BuildContext context) {
    final meters = activity.distanceMeters;
    final load = activity.trainingLoad;
    return ListTile(
      onTap: onTap,
      leading: SportIcon(symbol: symbol(activity.sport), color: color(activity.sport)),
      title: Text(
        activity.name ?? activity.typeKey ?? 'Aktivität',
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      subtitle: Text(
        [
          if (activity.day case final day?) formatDay(day),
          if (activity.durationSeconds case final seconds?) ActivityDetails.duration(seconds),
          if (meters != null && meters > 0) ActivityDetails.distance(meters, activity.sport),
          if (load != null) 'Belastung ${load.round()}',
        ].join('   '),
      ),
      trailing: trailing,
    );
  }
}
