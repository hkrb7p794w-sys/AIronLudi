import '../analysis/activity_source.dart';
import 'garmin_activity.dart';

/// Ein Krafttraining, das als Export (ohne Puls) und als Aufzeichnung der Uhr vorliegt, zählt nur einmal.
abstract final class StrengthDuplicates {
  /// Zeitfenster, in dem zwei Krafteinheiten als dieselbe gelten (`GarminStrengthSync.matchWindow`).
  static const matchWindow = Duration(hours: 2);

  /// IDs der überzähligen Aktivitäten.
  static Set<int> redundant(List<GarminActivity> activities) {
    final strength = activities
        .where(
          (activity) =>
              activity.sport == ActivitySport.strength && ActivitySource.of(activity.id) == ActivitySource.garmin,
        )
        .toList();
    final recorded = strength.where((activity) => activity.averageHeartRate != null).toList();
    final result = <int>{};
    for (final activity in strength.where((activity) => activity.averageHeartRate == null)) {
      final start = activityStart(activity);
      if (start == null) continue;
      final twin = recorded.any((other) {
        final otherStart = activityStart(other);
        if (other.day != activity.day || otherStart == null) return false;
        return otherStart.difference(start).abs() <= matchWindow;
      });
      if (twin) result.add(activity.id);
    }
    return result;
  }

  /// Aktivitäten ohne die überzähligen.
  static List<GarminActivity> removing(List<GarminActivity> activities) {
    final redundant = StrengthDuplicates.redundant(activities);
    return redundant.isEmpty ? activities : activities.where((activity) => !redundant.contains(activity.id)).toList();
  }
}
