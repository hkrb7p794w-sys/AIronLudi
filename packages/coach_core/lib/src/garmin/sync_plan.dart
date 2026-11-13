import '../calendar/calendar_day.dart';
import 'garmin_activity.dart';

/// Plant, welchen Zeitraum ein Garmin-Abruf holt.
///
/// Beim ersten Abruf 60 Tage (die HRV-Baseline des Altbestands nutzt einen 60-Tage-Korridor), danach ab dem zuletzt
/// gespeicherten Tag mit zwei Tagen Überlappung: Garmin trägt Schlaf und HRV oft erst Stunden später nach.
abstract final class SyncPlan {
  static const initialDays = 60;
  static const overlapDays = 2;

  /// Aktivitätsverlauf für Wochenbalken (12 Wochen) und HFmax.
  static const activityHistoryDays = 91;

  /// Abrufe kürzer hintereinander als dieser Abstand werden beim App-Start übersprungen.
  static const minimumInterval = Duration(minutes: 15);

  static DateRange range({required CalendarDay? latestStored, required CalendarDay today}) {
    if (latestStored == null || latestStored > today) return DateRange.last(initialDays, endingOn: today);
    final overlap = latestStored.adding(-overlapDays);
    final earliest = today.adding(-(initialDays - 1));
    return DateRange(overlap > earliest ? overlap : earliest, today);
  }

  static bool isDue({required DateTime? lastSync, required DateTime now}) {
    if (lastSync == null) return true;
    return now.difference(lastSync) >= minimumInterval || now.isBefore(lastSync);
  }

  /// Weiterblättern in der Aktivitätsliste (neueste zuerst), bis eine Seite unvollständig ist, eine schon bekannte
  /// Aktivität auftaucht oder die Aktivitäten vor dem Zeitraum liegen.
  static bool shouldLoadNextPage({
    required List<GarminActivity> page,
    required int pageSize,
    required Set<int> knownIDs,
    required CalendarDay rangeStart,
    required int pagesLoaded,
    int maxPages = 6,
  }) {
    if (page.length < pageSize || pagesLoaded >= maxPages) return false;
    if (page.any((activity) => knownIDs.contains(activity.id))) return false;
    final days = page.map((activity) => activity.day).nonNulls;
    if (days.isNotEmpty && days.reduce((a, b) => a < b ? a : b) < rangeStart) return false;
    return true;
  }
}
