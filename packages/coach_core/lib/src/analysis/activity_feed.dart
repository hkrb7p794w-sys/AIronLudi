import 'package:collection/collection.dart';

import '../calendar/calendar_day.dart';
import '../garmin/garmin_activity.dart';
import '../garmin/strength_duplicates.dart';
import '../profile/session_match.dart';
import '../profile/user_profile.dart';
import '../util/german_format.dart';
import 'activity_details.dart';
import 'activity_source.dart';
import 'session_kind.dart';

extension SessionKindLabel on SessionKind {
  String get label => switch (this) {
    SessionKind.easy => 'locker',
    SessionKind.test => 'Test',
    SessionKind.vo2 => 'Intervalle',
    SessionKind.threshold => 'Schwelle',
    SessionKind.hard => 'intensiv',
    SessionKind.gym => 'Kraft',
  };
}

/// Gym-Einheit aus der App, ohne Datenbank. (`fromSession` folgt mit dem Gym-Modul.)
final class GymItem {
  const GymItem({
    required this.id,
    required this.title,
    required this.start,
    required this.minutes,
    required this.sets,
    required this.volumeKg,
  });

  final String id;
  final String title;
  final DateTime start;
  final int? minutes;
  final int sets;
  final double volumeKg;

  @override
  bool operator ==(Object other) => other is GymItem && other.id == id && other.start == start;

  @override
  int get hashCode => Object.hash(id, start);
}

final class FeedEntry {
  const FeedEntry({
    required this.id,
    required this.day,
    required this.sortKey,
    required this.title,
    required this.sport,
    required this.sources,
    required this.activity,
    required this.gym,
    required this.values,
    required this.intensity,
    required this.planned,
  });

  final String id;
  final CalendarDay day;

  /// `yyyy-MM-dd HH:mm:ss` zum Sortieren.
  final String sortKey;
  final String title;
  final ActivitySport sport;
  final List<ActivitySource> sources;
  final GarminActivity? activity;
  final GymItem? gym;
  final List<String> values;
  final SessionKind? intensity;
  final SessionResult? planned;
}

enum FeedPeriod {
  weeks4('4 Wochen', 28),
  months3('3 Monate', 91),
  year('Jahr', 365),
  all('Alles', null);

  const FeedPeriod(this.label, this.days);

  final String label;
  final int? days;
}

/// Filter und Suche für den Verlauf: Sportart, nur Plan-Einheiten, nur harte Einheiten, Zeitraum, Text.
final class FeedFilter {
  const FeedFilter({
    this.sport,
    this.onlyPlanned = false,
    this.onlyHard = false,
    this.period = FeedPeriod.all,
    this.search = '',
  });

  final TrainingSport? sport;
  final bool onlyPlanned;

  /// Harte Ausdauereinheiten (Intervalle, Schwelle, Test); Kraft zählt nicht.
  final bool onlyHard;
  final FeedPeriod period;
  final String search;

  /// Mehr als der Zeitraum ist eingestellt (für das Symbol im Menü).
  bool get narrows => sport != null || onlyPlanned || onlyHard;

  List<FeedEntry> apply(List<FeedEntry> entries, {required CalendarDay today}) {
    final query = search.trim().toLowerCase();
    final days = period.days;
    final start = days == null ? null : today.adding(-(days - 1));
    return entries.where((entry) {
      if (start != null && entry.day < start) return false;
      if (sport != null && SessionMatcher.sport(entry.sport) != sport) return false;
      if (onlyPlanned && entry.planned == null) return false;
      if (onlyHard &&
          (entry.intensity == null || entry.intensity == SessionKind.easy || entry.intensity == SessionKind.gym)) {
        return false;
      }
      if (query.isEmpty) return true;
      final haystack = [entry.title, SessionMatcher.sport(entry.sport).label, ...entry.values].join(' ');
      return haystack.toLowerCase().contains(query);
    }).toList();
  }
}

/// Ein gemeinsamer Verlauf für Garmin, Apple Health / Health Connect, Nachgetragenes und die Gym-Einheiten der App:
/// eine Zeile je Training, mit Kernwerten, Intensität und Bezug zum Plan.
abstract final class ActivityFeed {
  /// Garmin-Kraft und App-Einheit gelten als dieselbe Einheit, wenn sie am selben Tag höchstens so weit auseinander
  /// beginnen (Upload der App nach Garmin oder parallel auf der Uhr aufgezeichnet).
  static const mergeWindow = Duration(hours: 2);

  static List<FeedEntry> entries({
    required List<GarminActivity> activities,
    required List<GymItem> gym,
    List<SessionResult> results = const [],
  }) {
    final gymLeft = [...gym];
    // Export der App plus Aufzeichnung der Uhr: nur die Aufzeichnung (mit Herzfrequenz und Kalorien) zeigen.
    final remaining = StrengthDuplicates.removing(activities);
    final byActivity = <int, SessionResult>{};
    for (final result in results) {
      final id = result.activityID;
      if (id != null) byActivity.putIfAbsent(id, () => result);
    }
    final entries = <FeedEntry>[];
    for (final activity in remaining) {
      final day = activity.day;
      if (day == null) continue;
      final sources = [ActivitySource.of(activity.id)];
      GymItem? item;
      final start = activityStart(activity);
      if (activity.sport == ActivitySport.strength && start != null) {
        final index = gymLeft.indexWhere(
          (candidate) =>
              CalendarDay.fromDate(candidate.start.toLocal()) == day &&
              candidate.start.difference(start).abs() <= mergeWindow,
        );
        if (index >= 0) {
          item = gymLeft.removeAt(index);
          sources.insert(0, ActivitySource.app);
        }
      }
      entries.add(
        FeedEntry(
          id: 'a${activity.id}',
          day: day,
          sortKey: activity.startLocal ?? day.iso,
          title: item?.title ?? activity.name ?? activity.typeKey ?? 'Aktivität',
          sport: activity.sport,
          sources: sources,
          activity: activity,
          gym: item,
          values: values(activity, gym: item),
          intensity: SessionKind.of(activity),
          planned: byActivity[activity.id],
        ),
      );
    }
    final gymDayResults = results
        .where((result) => result.activityID == null && result.planned.slot.sport == TrainingSport.strength)
        .toList();
    for (final item in gymLeft) {
      final local = item.start.toLocal();
      final day = CalendarDay.fromDate(local);
      entries.add(
        FeedEntry(
          id: 'g${item.id}',
          day: day,
          sortKey: _localKey(local),
          title: item.title,
          sport: ActivitySport.strength,
          sources: const [ActivitySource.app],
          activity: null,
          gym: item,
          values: gymValues(item),
          intensity: SessionKind.gym,
          planned: gymDayResults.firstWhereOrNull((result) => result.planned.day == day && result.status.counts),
        ),
      );
    }
    mergeSort(entries, compare: (a, b) => b.sortKey.compareTo(a.sortKey));
    return entries;
  }

  /// Bis zu vier Kernwerte für die Zeile: Dauer, Strecke, Tempo, Herzfrequenz oder Belastung.
  static List<String> values(GarminActivity activity, {GymItem? gym}) {
    final result = <String>[];
    final seconds = activity.durationSeconds;
    if (seconds != null) result.add(ActivityDetails.duration(seconds));
    final meters = activity.distanceMeters;
    if (meters != null && meters > 0) result.add(ActivityDetails.distance(meters, activity.sport));
    if (gym != null) result.addAll(gymValues(gym).skip(gym.minutes == null ? 0 : 1));
    final paceText = pace(activity);
    if (paceText != null) result.add(paceText);
    final heartRate = activity.averageHeartRate;
    if (heartRate != null) result.add('Ø ${heartRate.round()} bpm');
    final load = activity.trainingLoad;
    if (load != null && result.length < 4) result.add('Belastung ${load.round()}');
    return result.take(4).toList();
  }

  static List<String> gymValues(GymItem gym) => [
    if (gym.minutes != null) '${gym.minutes} min',
    '${gym.sets} Sätze',
    if (gym.volumeKg > 0) '${GermanFormat.number((gym.volumeKg / 10).roundToDouble() * 10)} kg',
  ];

  /// Laufen min/km, Schwimmen min/100 m, Rad km/h.
  static String? pace(GarminActivity activity) {
    final meters = activity.distanceMeters;
    final seconds = activity.movingSeconds ?? activity.durationSeconds;
    if (meters == null || meters <= 0 || seconds == null || seconds <= 0) return null;
    return switch (activity.sport) {
      ActivitySport.run => '${GermanFormat.minutesSeconds((seconds / (meters / 1000)).round())} /km',
      ActivitySport.swim => '${GermanFormat.minutesSeconds((seconds / (meters / 100)).round())} /100 m',
      ActivitySport.bike => '${GermanFormat.decimal(meters / seconds * 3.6)} km/h',
      _ => null,
    };
  }

  /// Anteile der fünf Herzfrequenzzonen (Summe 1), wenn die Uhr sie liefert.
  static List<double>? zoneShares(GarminActivity activity) {
    final zones = activity.secondsInZones;
    if (zones == null || zones.length != 5) return null;
    final total = zones.sum;
    return total > 0 ? [for (final zone in zones) zone / total] : null;
  }

  /// Was fehlt und was das für die Auswertung heißt – statt leerer Felder.
  static List<String> missing(GarminActivity activity) {
    final notes = <String>[];
    final source = ActivitySource.of(activity.id);
    if (source == ActivitySource.manual) {
      return ['Nachgetragen: Belastung aus Dauer × Anstrengung, keine Herzfrequenz oder Strecke.'];
    }
    if (activity.averageHeartRate == null) {
      notes.add('Keine Herzfrequenz – Intensität nur aus dem Namen der Einheit geschätzt.');
    } else if (activity.secondsInZones == null && activity.sport != ActivitySport.strength) {
      notes.add('Keine Zeit in Zonen – die Intensitätsverteilung zählt diese Einheit nicht mit.');
    }
    if (activity.trainingLoad == null && activity.sport != ActivitySport.strength) {
      notes.add(
        source == ActivitySource.health
            ? 'Apple Health liefert keine Trainingsbelastung – Fitness & Form schätzen sie nicht.'
            : 'Keine Trainingsbelastung von der Uhr – zählt nicht für Fitness & Form.',
      );
    }
    if (activity.sport == ActivitySport.swim && activity.averageHeartRate != null) {
      notes.add('Herzfrequenz am Handgelenk ist im Wasser ungenau – Schwimmen gilt nie automatisch als hart.');
    }
    if ((activity.sport == ActivitySport.run || activity.sport == ActivitySport.bike) &&
        (activity.distanceMeters ?? 0) == 0) {
      notes.add('Keine Strecke (Laufband, Rolle ohne Sensor?) – kein Tempo und keine Kilometer.');
    }
    return notes;
  }

  static String _localKey(DateTime local) {
    String two(int value) => value.toString().padLeft(2, '0');
    return '${local.year.toString().padLeft(4, '0')}-${two(local.month)}-${two(local.day)} '
        '${two(local.hour)}:${two(local.minute)}:${two(local.second)}';
  }
}
