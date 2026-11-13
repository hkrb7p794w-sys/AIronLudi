import '../calendar/calendar_day.dart';
import '../json/json_value.dart';
import '../util/enum_codec.dart';

/// Körperdaten aus den Garmin-Profileinstellungen (für Ernährungsziele).
final class GarminProfile {
  GarminProfile();

  /// `/userprofile-service/userprofile/settings` (Werte unter `userData`; Gewicht in Gramm).
  factory GarminProfile.fromSettings(JsonValue json) {
    final data = json['userData'] ?? json;
    final profile = GarminProfile();
    final grams = data.firstValue(['weight'])?.doubleValue;
    if (grams != null && grams > 0) {
      profile.weightKilograms = grams > 500 ? (grams / 100).roundToDouble() / 10 : grams;
    }
    final birthDate = data.firstValue(['birthDate'])?.stringValue;
    profile
      ..heightCentimeters = data.firstValue(['height'])?.doubleValue
      ..birthDate = birthDate == null ? null : CalendarDay.tryParse(birthDate)
      ..gender = data.firstValue(['gender'])?.stringValue?.toUpperCase()
      ..vo2MaxRunning = data.firstValue(['vo2MaxRunning'])?.doubleValue
      ..vo2MaxCycling = data.firstValue(['vo2MaxCycling'])?.doubleValue
      ..lactateThresholdHeartRate = data.firstValue(['lactateThresholdHeartRate'])?.doubleValue;
    return profile;
  }

  double? weightKilograms;
  double? heightCentimeters;
  CalendarDay? birthDate;

  /// `MALE` oder `FEMALE`.
  String? gender;
  double? vo2MaxRunning;
  double? vo2MaxCycling;
  double? lactateThresholdHeartRate;

  int? ageOn(CalendarDay day) {
    final birthDate = this.birthDate;
    if (birthDate == null) return null;
    var age = day.year - birthDate.year;
    if (day.month < birthDate.month || (day.month == birthDate.month && day.day < birthDate.day)) age -= 1;
    return age;
  }

  Map<String, Object?> toJson() => {
    'weightKilograms': ?weightKilograms,
    'heightCentimeters': ?heightCentimeters,
    'birthDate': ?birthDate?.toJson(),
    'gender': ?gender,
    'vo2MaxRunning': ?vo2MaxRunning,
    'vo2MaxCycling': ?vo2MaxCycling,
    'lactateThresholdHeartRate': ?lactateThresholdHeartRate,
  };

  static GarminProfile fromJson(Object? json) {
    final profile = GarminProfile();
    if (json is! Map) return profile;
    final birth = json['birthDate'];
    return profile
      ..weightKilograms = jsonDouble(json['weightKilograms'])
      ..heightCentimeters = jsonDouble(json['heightCentimeters'])
      ..birthDate = birth is Map ? CalendarDay.fromJson(birth.cast<String, Object?>()) : null
      ..gender = json['gender'] as String?
      ..vo2MaxRunning = jsonDouble(json['vo2MaxRunning'])
      ..vo2MaxCycling = jsonDouble(json['vo2MaxCycling'])
      ..lactateThresholdHeartRate = jsonDouble(json['lactateThresholdHeartRate']);
  }
}
