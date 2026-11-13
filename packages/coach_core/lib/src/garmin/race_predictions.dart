import '../calendar/calendar_day.dart';
import '../json/json_value.dart';
import '../util/enum_codec.dart';

/// Wettkampfprognosen der Uhr (`metrics-service/metrics/racepredictions`), Zeiten in Sekunden.
final class RacePredictions {
  RacePredictions({this.fiveK, this.tenK, this.halfMarathon, this.marathon, this.day});

  double? fiveK;
  double? tenK;
  double? halfMarathon;
  double? marathon;
  CalendarDay? day;

  /// Aus der Antwort von Garmin (letzter Eintrag einer Liste); `null` ohne eine einzige Prognose.
  static RacePredictions? fromGarmin(JsonValue json) {
    final record = json.arrayValue?.lastOrNull ?? json;
    double? time(String key) {
      final value = record[key]?.doubleValue;
      return value != null && value > 0 ? value : null;
    }

    final date = record['calendarDate']?.stringValue;
    final result = RacePredictions(
      fiveK: time('time5K'),
      tenK: time('time10K'),
      halfMarathon: time('timeHalfMarathon'),
      marathon: time('timeMarathon'),
      day: date == null ? null : CalendarDay.tryParse(String.fromCharCodes(date.runes.take(10))),
    );
    if (result.fiveK == null && result.tenK == null && result.halfMarathon == null && result.marathon == null) {
      return null;
    }
    return result;
  }

  Map<String, Object?> toJson() => {
    'fiveK': ?fiveK,
    'tenK': ?tenK,
    'halfMarathon': ?halfMarathon,
    'marathon': ?marathon,
    'day': ?day?.toJson(),
  };

  static RacePredictions? fromJson(Object? json) {
    if (json is! Map) return null;
    final rawDay = json['day'];
    CalendarDay? day;
    if (rawDay is Map<String, Object?>) {
      try {
        day = CalendarDay.fromJson(rawDay);
      } on Object {
        return null;
      }
    } else if (rawDay != null) {
      return null;
    }
    return RacePredictions(
      fiveK: jsonDouble(json['fiveK']),
      tenK: jsonDouble(json['tenK']),
      halfMarathon: jsonDouble(json['halfMarathon']),
      marathon: jsonDouble(json['marathon']),
      day: day,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is RacePredictions &&
      other.fiveK == fiveK &&
      other.tenK == tenK &&
      other.halfMarathon == halfMarathon &&
      other.marathon == marathon &&
      other.day == day;

  @override
  int get hashCode => Object.hash(fiveK, tenK, halfMarathon, marathon, day);
}
