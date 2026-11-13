import 'dart:math' as math;

import 'package:collection/collection.dart';

import '../analysis/activity_feed.dart';
import '../analysis/activity_source.dart';
import 'social.dart';

/// Ein Eintrag der gemeinsamen Liste.
final class TimelineItem {
  const TimelineItem({required this.id, required this.date, this.entry, this.post});

  final String id;
  final DateTime date;

  /// Eigenes Training vom Gerät.
  final FeedEntry? entry;

  /// Beitrag aus dem Feed; bei `entry != null` der dazugehörige eigene Beitrag.
  final SocialPost? post;
}

/// Reiter „Aktivitäten“: eigene Trainings (vom Gerät, mit allen Details) und Beiträge der Freunde in einer Liste,
/// neueste oben. Ein eigenes Training, das geteilt wurde, erscheint einmal – mit den Reaktionen seines Beitrags.
/// Zeiten in der Zeitzone des Geräts (wie `ActivityFeed`; Swift nimmt eine `TimeZone`).
abstract final class SocialTimeline {
  static final _distantPast = DateTime.utc(1, 1, 1);

  /// Schlüssel, unter denen ein geteiltes Training gemerkt wird. Eine Gym-Einheit behält ihren Schlüssel, auch wenn
  /// sie später mit der Aufzeichnung der Uhr zu einer Zeile verschmilzt – sonst würde sie doppelt geteilt.
  static List<String> keys(FeedEntry entry) {
    final keys = [entry.id];
    if (entry.gym case final gym?) {
      final key = 'g${gym.id}';
      if (!keys.contains(key)) keys.add(key);
    }
    return keys;
  }

  static DateTime date(FeedEntry entry) {
    final activity = entry.activity;
    final gym = entry.gym;
    if (activity == null && gym != null) return gym.start;
    if (activity != null) {
      final start = activityStart(activity);
      if (start != null) return start;
    }
    if (gym != null) return gym.start;
    return DateTime(entry.day.year, entry.day.month, entry.day.day, 12);
  }

  /// [shared]: Schlüssel eines eigenen Trainings → ID des Beitrags dazu. [oldest]: Solange der Feed noch ältere
  /// Seiten hat, enden die eigenen Trainings am ältesten geladenen Beitrag; sonst stünden sie vor Beiträgen, die erst
  /// nachgeladen werden.
  static List<TimelineItem> merge({
    required List<FeedEntry> entries,
    required List<SocialPost> posts,
    required Map<String, String> shared,
    DateTime? oldest,
  }) {
    final byID = <String, SocialPost>{};
    for (final post in posts) {
      byID.putIfAbsent(post.id, () => post);
    }
    final used = <String>{};
    final items = <TimelineItem>[];
    for (final entry in entries) {
      final when = date(entry);
      if (oldest != null && when.isBefore(oldest)) continue;
      final post = keys(entry).map((key) => shared[key]).nonNulls.map((id) => byID[id]).nonNulls.firstOrNull;
      if (post != null) used.add(post.id);
      items.add(TimelineItem(id: entry.id, date: when, entry: entry, post: post));
    }
    for (final post in posts) {
      if (used.contains(post.id)) continue;
      items.add(TimelineItem(id: 'p${post.id}', date: post.date ?? _distantPast, post: post));
    }
    return items..sort((a, b) {
      if (a.date.isAtSameMomentAs(b.date)) return b.id.compareTo(a.id);
      return b.date.compareTo(a.date);
    });
  }

  /// Trainings, die „automatisch teilen“ jetzt teilt: nach dem Einschalten begonnen, höchstens drei Tage alt, noch
  /// nicht geteilt. Älteste zuerst, damit der Feed die richtige Reihenfolge behält; begrenzt je Durchlauf.
  static List<FeedEntry> autoShareCandidates({
    required List<FeedEntry> entries,
    required Map<String, String> shared,
    required DateTime since,
    DateTime? now,
    int limit = 3,
  }) {
    final current = now ?? DateTime.now();
    final threeDays = current.subtract(const Duration(days: 3));
    final earliest = since.isAfter(threeDays) ? since : threeDays;
    final fresh = entries.where((entry) {
      final when = date(entry);
      return !when.isBefore(earliest) && !when.isAfter(current) && !keys(entry).any((key) => shared[key] != null);
    }).toList();
    mergeSort(fresh, compare: (a, b) => date(a).compareTo(date(b)));
    return fresh.take(math.max(limit, 0)).toList();
  }
}
