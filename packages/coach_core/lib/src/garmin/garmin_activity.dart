import 'package:collection/collection.dart';

import '../calendar/calendar_day.dart';
import '../integration/data_provider.dart';
import '../json/json_value.dart';
import '../util/enum_codec.dart';

/// Grobe Sportart für Wochen-Soll/Ist und Ernährungsziele.
enum ActivitySport implements RawEnum {
  run,
  bike,
  swim,
  strength,
  other;

  @override
  String get rawValue => name;

  /// Gleiche Reihenfolge und Schlüsselwörter wie der Altbestand (`app.py`, Wochenvolumen).
  static ActivitySport fromTypeKey(String? typeKey) {
    final key = typeKey?.toLowerCase() ?? '';
    if (key.contains('swim')) return swim;
    if (key.contains('bik') || key.contains('cycl') || key.contains('ride')) return bike;
    if (key.contains('run')) return run;
    if (key.contains('strength') || key.contains('weight') || key.contains('gym')) return strength;
    return other;
  }
}

/// Zusammenfassung einer Aktivität. Trotz des Namens das allgemeine Aktivitätsmodell für alle Anbieter (Garmin,
/// Apple Health / Health Connect, später WHOOP/Polar); die Herkunft steht in [provider] und [externalID].
///
/// JSON-Schlüssel wie das synthetisierte `Codable` in Swift (Sicherungen, gespeicherte Aktivitäten).
final class GarminActivity {
  GarminActivity(this.id);

  final int id;
  String? name;
  String? typeKey;
  String? startLocal;
  double? durationSeconds;
  double? distanceMeters;
  double? averageHeartRate;
  double? maxHeartRate;
  double? calories;
  double? trainingLoad;
  double? aerobicTrainingEffect;
  double? anaerobicTrainingEffect;
  double? averagePower;
  double? normalizedPower;
  double? elevationGain;
  double? vo2Max;
  List<double>? secondsInZones;
  double? movingSeconds;
  double? elapsedSeconds;
  double? averageSpeed;
  double? maxSpeed;
  double? elevationLoss;
  double? minElevation;
  double? maxElevation;
  double? averageCadence;
  double? maxCadence;
  double? strideLength;
  double? groundContactTime;
  double? verticalOscillation;
  double? verticalRatio;
  double? maxPower;
  double? steps;
  double? poolLength;
  double? lengths;
  double? strokes;
  double? swolf;
  double? strokeRate;
  double? minTemperature;
  double? maxTemperature;
  double? lapCount;
  String? trainingEffectLabel;
  String? locationName;
  double? activeKilocalories;
  DataProvider? provider;
  String? externalID;

  CalendarDay? get day => startLocal == null ? null : CalendarDay.tryParse(startLocal!);

  ActivitySport get sport => ActivitySport.fromTypeKey(typeKey);

  GarminActivity copy() => GarminActivity(id)
    ..name = name
    ..typeKey = typeKey
    ..startLocal = startLocal
    ..durationSeconds = durationSeconds
    ..distanceMeters = distanceMeters
    ..averageHeartRate = averageHeartRate
    ..maxHeartRate = maxHeartRate
    ..calories = calories
    ..trainingLoad = trainingLoad
    ..aerobicTrainingEffect = aerobicTrainingEffect
    ..anaerobicTrainingEffect = anaerobicTrainingEffect
    ..averagePower = averagePower
    ..normalizedPower = normalizedPower
    ..elevationGain = elevationGain
    ..vo2Max = vo2Max
    ..secondsInZones = secondsInZones
    ..movingSeconds = movingSeconds
    ..elapsedSeconds = elapsedSeconds
    ..averageSpeed = averageSpeed
    ..maxSpeed = maxSpeed
    ..elevationLoss = elevationLoss
    ..minElevation = minElevation
    ..maxElevation = maxElevation
    ..averageCadence = averageCadence
    ..maxCadence = maxCadence
    ..strideLength = strideLength
    ..groundContactTime = groundContactTime
    ..verticalOscillation = verticalOscillation
    ..verticalRatio = verticalRatio
    ..maxPower = maxPower
    ..steps = steps
    ..poolLength = poolLength
    ..lengths = lengths
    ..strokes = strokes
    ..swolf = swolf
    ..strokeRate = strokeRate
    ..minTemperature = minTemperature
    ..maxTemperature = maxTemperature
    ..lapCount = lapCount
    ..trainingEffectLabel = trainingEffectLabel
    ..locationName = locationName
    ..activeKilocalories = activeKilocalories
    ..provider = provider
    ..externalID = externalID;

  Map<String, Object?> toJson() => {
    'id': id,
    'name': ?name,
    'typeKey': ?typeKey,
    'startLocal': ?startLocal,
    'durationSeconds': ?durationSeconds,
    'distanceMeters': ?distanceMeters,
    'averageHeartRate': ?averageHeartRate,
    'maxHeartRate': ?maxHeartRate,
    'calories': ?calories,
    'trainingLoad': ?trainingLoad,
    'aerobicTrainingEffect': ?aerobicTrainingEffect,
    'anaerobicTrainingEffect': ?anaerobicTrainingEffect,
    'averagePower': ?averagePower,
    'normalizedPower': ?normalizedPower,
    'elevationGain': ?elevationGain,
    'vo2Max': ?vo2Max,
    'secondsInZones': ?secondsInZones,
    'movingSeconds': ?movingSeconds,
    'elapsedSeconds': ?elapsedSeconds,
    'averageSpeed': ?averageSpeed,
    'maxSpeed': ?maxSpeed,
    'elevationLoss': ?elevationLoss,
    'minElevation': ?minElevation,
    'maxElevation': ?maxElevation,
    'averageCadence': ?averageCadence,
    'maxCadence': ?maxCadence,
    'strideLength': ?strideLength,
    'groundContactTime': ?groundContactTime,
    'verticalOscillation': ?verticalOscillation,
    'verticalRatio': ?verticalRatio,
    'maxPower': ?maxPower,
    'steps': ?steps,
    'poolLength': ?poolLength,
    'lengths': ?lengths,
    'strokes': ?strokes,
    'swolf': ?swolf,
    'strokeRate': ?strokeRate,
    'minTemperature': ?minTemperature,
    'maxTemperature': ?maxTemperature,
    'lapCount': ?lapCount,
    'trainingEffectLabel': ?trainingEffectLabel,
    'locationName': ?locationName,
    'activeKilocalories': ?activeKilocalories,
    'provider': ?provider?.rawValue,
    'externalID': ?externalID,
  };

  static GarminActivity? fromJson(Object? json) {
    if (json is! Map) return null;
    final id = jsonInt(json['id']);
    if (id == null) return null;
    return GarminActivity(id)
      ..name = json['name'] is String ? json['name'] as String : null
      ..typeKey = json['typeKey'] is String ? json['typeKey'] as String : null
      ..startLocal = json['startLocal'] is String ? json['startLocal'] as String : null
      ..durationSeconds = jsonDouble(json['durationSeconds'])
      ..distanceMeters = jsonDouble(json['distanceMeters'])
      ..averageHeartRate = jsonDouble(json['averageHeartRate'])
      ..maxHeartRate = jsonDouble(json['maxHeartRate'])
      ..calories = jsonDouble(json['calories'])
      ..trainingLoad = jsonDouble(json['trainingLoad'])
      ..aerobicTrainingEffect = jsonDouble(json['aerobicTrainingEffect'])
      ..anaerobicTrainingEffect = jsonDouble(json['anaerobicTrainingEffect'])
      ..averagePower = jsonDouble(json['averagePower'])
      ..normalizedPower = jsonDouble(json['normalizedPower'])
      ..elevationGain = jsonDouble(json['elevationGain'])
      ..vo2Max = jsonDouble(json['vo2Max'])
      ..secondsInZones = json['secondsInZones'] is List
          ? (json['secondsInZones'] as List).map(jsonDouble).nonNulls.toList()
          : null
      ..movingSeconds = jsonDouble(json['movingSeconds'])
      ..elapsedSeconds = jsonDouble(json['elapsedSeconds'])
      ..averageSpeed = jsonDouble(json['averageSpeed'])
      ..maxSpeed = jsonDouble(json['maxSpeed'])
      ..elevationLoss = jsonDouble(json['elevationLoss'])
      ..minElevation = jsonDouble(json['minElevation'])
      ..maxElevation = jsonDouble(json['maxElevation'])
      ..averageCadence = jsonDouble(json['averageCadence'])
      ..maxCadence = jsonDouble(json['maxCadence'])
      ..strideLength = jsonDouble(json['strideLength'])
      ..groundContactTime = jsonDouble(json['groundContactTime'])
      ..verticalOscillation = jsonDouble(json['verticalOscillation'])
      ..verticalRatio = jsonDouble(json['verticalRatio'])
      ..maxPower = jsonDouble(json['maxPower'])
      ..steps = jsonDouble(json['steps'])
      ..poolLength = jsonDouble(json['poolLength'])
      ..lengths = jsonDouble(json['lengths'])
      ..strokes = jsonDouble(json['strokes'])
      ..swolf = jsonDouble(json['swolf'])
      ..strokeRate = jsonDouble(json['strokeRate'])
      ..minTemperature = jsonDouble(json['minTemperature'])
      ..maxTemperature = jsonDouble(json['maxTemperature'])
      ..lapCount = jsonDouble(json['lapCount'])
      ..trainingEffectLabel = json['trainingEffectLabel'] is String ? json['trainingEffectLabel'] as String : null
      ..locationName = json['locationName'] is String ? json['locationName'] as String : null
      ..activeKilocalories = jsonDouble(json['activeKilocalories'])
      ..provider = enumFromRaw(DataProvider.values, json['provider'])
      ..externalID = json['externalID'] is String ? json['externalID'] as String : null;
  }

  @override
  bool operator ==(Object other) =>
      other is GarminActivity && const DeepCollectionEquality().equals(other.toJson(), toJson());

  @override
  int get hashCode => const DeepCollectionEquality().hash(toJson());

  @override
  String toString() => 'GarminActivity($id, $typeKey, $startLocal)';
}

/// Allgemeiner Name wie in Swift (`TrainingActivity`).
typedef TrainingActivity = GarminActivity;

abstract final class GarminActivityParser {
  /// `/activity-service/activity/{id}`: Werte stehen unter `summaryDTO`, die Art unter `activityTypeDTO`. Ergänzt
  /// fehlende Werte von [base]; vorhandene Werte bleiben.
  static GarminActivity detail(JsonValue json, GarminActivity base) {
    final top = json.objectValue;
    if (top == null) return base;
    final record = Map<String, JsonValue>.of(top);
    final summary = top['summaryDTO']?.objectValue;
    if (summary != null) record.addAll(summary);
    final type = top['activityTypeDTO']?['typeKey'];
    if (type != null) record['activityType'] = JsonValue({'typeKey': type.raw});
    record['activityId'] = JsonValue(base.id);
    final parsed = activity(record);
    return parsed == null ? base : merged(base, parsed);
  }

  /// Fehlende Felder von [base] aus [other] (über die JSON-Darstellung, damit kein Feld vergessen wird).
  static GarminActivity merged(GarminActivity base, GarminActivity other) {
    final baseObject = base.toJson();
    for (final entry in other.toJson().entries) {
      if (baseObject[entry.key] == null) baseObject[entry.key] = entry.value;
    }
    return GarminActivity.fromJson(baseObject) ?? base;
  }

  /// `/activitylist-service/activities/search/activities` – Liste (oder Objekt mit Liste) von Aktivitäten mit
  /// `activityId`.
  static List<GarminActivity> activities(JsonValue json) => json.objects('activityId').map(activity).nonNulls.toList();

  static GarminActivity? activity(Map<String, JsonValue> record) {
    final rawID = record['activityId']?.doubleValue;
    if (rawID == null || rawID <= 0 || rawID >= 9e15) return null;
    double? number(List<String> keys) {
      for (final key in keys) {
        final value = record[key];
        if (value != null) return value.doubleValue;
      }
      return null;
    }

    final result = GarminActivity(rawID.truncate())
      ..name = record['activityName']?.stringValue
      ..typeKey = record['activityType']?['typeKey']?.stringValue ?? record['activityType']?.stringValue
      ..startLocal = record['startTimeLocal']?.stringValue
      ..durationSeconds = record['duration']?.doubleValue ?? record['elapsedDuration']?.doubleValue
      ..distanceMeters = record['distance']?.doubleValue
      ..averageHeartRate = record['averageHR']?.doubleValue
      ..maxHeartRate = record['maxHR']?.doubleValue
      ..calories = record['calories']?.doubleValue
      ..trainingLoad = record['activityTrainingLoad']?.doubleValue
      ..aerobicTrainingEffect = number(['aerobicTrainingEffect', 'trainingEffect'])
      ..anaerobicTrainingEffect = record['anaerobicTrainingEffect']?.doubleValue
      ..averagePower = record['avgPower']?.doubleValue
      ..normalizedPower = number(['normPower', 'normalizedPower'])
      ..elevationGain = record['elevationGain']?.doubleValue
      ..vo2Max = record['vO2MaxValue']?.doubleValue
      ..movingSeconds = record['movingDuration']?.doubleValue
      ..elapsedSeconds = record['elapsedDuration']?.doubleValue
      ..averageSpeed = record['averageSpeed']?.doubleValue
      ..maxSpeed = record['maxSpeed']?.doubleValue
      ..elevationLoss = record['elevationLoss']?.doubleValue
      ..minElevation = record['minElevation']?.doubleValue
      ..maxElevation = record['maxElevation']?.doubleValue
      ..averageCadence = number([
        'averageRunningCadenceInStepsPerMinute',
        'averageRunCadence',
        'averageBikingCadenceInRevPerMinute',
        'averageBikeCadence',
      ])
      ..maxCadence = number([
        'maxRunningCadenceInStepsPerMinute',
        'maxRunCadence',
        'maxBikingCadenceInRevPerMinute',
        'maxBikeCadence',
      ])
      ..strideLength = number(['avgStrideLength', 'strideLength'])
      ..groundContactTime = number(['avgGroundContactTime', 'groundContactTime'])
      ..verticalOscillation = number(['avgVerticalOscillation', 'verticalOscillation'])
      ..verticalRatio = number(['avgVerticalRatio', 'verticalRatio'])
      ..maxPower = record['maxPower']?.doubleValue
      ..steps = record['steps']?.doubleValue
      ..poolLength = record['poolLength']?.doubleValue
      ..lengths = record['activeLengths']?.doubleValue
      ..strokes = record['totalNumberOfStrokes']?.doubleValue ?? record['strokes']?.doubleValue
      ..swolf = record['averageSwolf']?.doubleValue
      ..strokeRate = record['averageSwimCadenceInStrokesPerMinute']?.doubleValue
      ..minTemperature = record['minTemperature']?.doubleValue
      ..maxTemperature = record['maxTemperature']?.doubleValue
      ..lapCount = record['lapCount']?.doubleValue
      ..trainingEffectLabel = record['trainingEffectLabel']?.stringValue
      ..locationName = record['locationName']?.stringValue
      ..activeKilocalories = record['activeKilocalories']?.doubleValue;
    final zones = [for (var zone = 1; zone <= 5; zone++) record['hrTimeInZone_$zone']?.doubleValue].nonNulls.toList();
    if (zones.length == 5 && zones.sum > 0) result.secondsInZones = zones;
    return result;
  }
}
