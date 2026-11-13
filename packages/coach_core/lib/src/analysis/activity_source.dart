import '../garmin/garmin_activity.dart';
import '../util/enum_codec.dart';

/// Herkunft einer Aktivität im Verlauf. Das übrige `ActivityFeed`-Modul folgt mit der Analyse.
enum ActivitySource implements RawEnum {
  garmin('Garmin'),
  health('Apple Health'),
  manual('nachgetragen'),
  app('Gym-App');

  const ActivitySource(this.label);

  final String label;

  @override
  String get rawValue => name;

  /// Garmin-IDs sind positiv, Apple Health negativ, nachgetragene liegen darunter (`ManualActivity`).
  static ActivitySource of(int id) {
    if (id >= 0) return garmin;
    return id < -manualIdOffset ? manual : health;
  }

  /// Wie `ManualActivity.idOffset` in Swift (2^62).
  static const manualIdOffset = 1 << 62;
}

/// Startzeit einer Aktivität aus `yyyy-MM-dd HH:mm:ss` in der Ortszeit des Geräts (`ActivityFeed.start`).
DateTime? activityStart(GarminActivity activity) {
  final text = activity.startLocal;
  if (text == null || text.length < 19) return null;
  final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2}) (\d{2}):(\d{2}):(\d{2})$').firstMatch(text.substring(0, 19));
  if (match == null) return null;
  final parts = [for (var group = 1; group <= 6; group++) int.parse(match.group(group)!)];
  return DateTime(parts[0], parts[1], parts[2], parts[3], parts[4], parts[5]);
}
