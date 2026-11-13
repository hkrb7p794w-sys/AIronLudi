import '../garmin/garmin_activity.dart';

/// Aerobe Entkopplung (Port von `AerobicDecoupling`). Hier zunächst der Zonenanteil, den die Einordnung der Einheiten
/// braucht; die Auswertung selbst folgt mit dem Analyse-Modul.
abstract final class AerobicDecoupling {
  /// Anteil der Zeit in Zone 4–5; `null` ohne Zonen.
  static double? highZoneShare(GarminActivity activity) {
    final zones = activity.secondsInZones;
    if (zones == null || zones.length != 5) return null;
    final total = zones.fold<double>(0, (sum, value) => sum + value);
    return total > 0 ? (zones[3] + zones[4]) / total : null;
  }
}
