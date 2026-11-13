import 'package:collection/collection.dart';

import '../garmin/garmin_activity.dart';
import '../util/enum_codec.dart';
import 'aerobic_decoupling.dart';

/// Einordnung einer Einheit wie im Altbestand (`tagesform.py`: `_is_hard`, `_kind`).
///
/// Harte Einheiten werden nur mit gleichartigen verglichen: Der Schnitt eines 4×4-Laufs mit Trabpausen ist nicht mit
/// einem Schwellenlauf vergleichbar.
enum SessionKind implements RawEnum {
  easy,
  test,
  vo2,
  threshold,
  hard,
  gym;

  @override
  String get rawValue => name;

  static const hardNameKeywords = [
    'intervall', 'interval', 'schwelle', 'threshold', 'tempo', 'vo2', 'sprint', 'test', 'css', 'ftp', 'rennen', //
    'race', 'sweet', 'over-under', 'overunder', 'ramp',
  ];

  /// Reihenfolge = Priorität.
  static const hardKinds = <(SessionKind, List<String>)>[
    (SessionKind.test, ['test', 'ramp', 'ftp']),
    (SessionKind.vo2, ['vo2', '4x4', 'sprint', 'intervall', 'interval']),
    (SessionKind.threshold, ['schwelle', 'threshold', 'tempo', 'sweet', 'over-under', 'overunder', 'css']),
  ];

  /// Ab 15 % der Zeit in Zone 4–5 gilt eine Einheit als hart.
  static const hardHighZoneShare = 0.15;

  /// Rad: auch ab 35 % in Zone 3–5 (Sweet Spot). Beim Laufen nicht, Z3 kommt auch locker vor.
  static const hardMidZoneShare = 0.35;

  static bool isHard(GarminActivity activity) {
    final sport = activity.sport;
    if (sport == ActivitySport.strength) return true;
    final name = activity.name?.toLowerCase() ?? '';
    if (hardNameKeywords.any(name.contains)) return true;
    if (sport == ActivitySport.swim) return false; // Handgelenk-HF im Wasser ist zu unzuverlässig
    final share = AerobicDecoupling.highZoneShare(activity);
    if (share != null && share >= hardHighZoneShare) return true;
    final zones = activity.secondsInZones;
    if (sport != ActivitySport.bike || zones == null) return false;
    return (zones[2] + zones[3] + zones[4]) / zones.sum >= hardMidZoneShare;
  }

  static SessionKind of(GarminActivity activity) {
    if (!isHard(activity)) return easy;
    if (activity.sport == ActivitySport.strength) return gym;
    final name = activity.name?.toLowerCase() ?? '';
    return hardKinds.firstWhereOrNull((entry) => entry.$2.any(name.contains))?.$1 ?? hard;
  }
}
