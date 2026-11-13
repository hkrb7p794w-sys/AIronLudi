import 'dart:io';

import 'package:coach_core/coach_core.dart';
import 'package:health/health.dart';

/// Zahlenwerte aus Apple Health bzw. Health Connect.
enum HealthQuantity {
  steps,
  activeEnergy,
  basalEnergy,
  restingHeartRate,
  hrvSDNN,
  respiratoryRate,
  oxygenSaturation,
  heartRate,
  bodyMass,
  distanceWalkingRunning,
  distanceCycling,
  distanceSwimming,
}

/// Eine Probe mit Zeitraum, Wert (in der Einheit der App: kcal, ms, /min, Anteil, kg, m) und Quelle.
final class HealthQuantitySample {
  const HealthQuantitySample({required this.start, required this.end, required this.value, required this.source});

  final DateTime start;
  final DateTime end;
  final double value;
  final String source;
}

/// Zugriff auf die Gesundheitsdaten; in Tests durch eine Nachbildung ersetzt.
abstract interface class HealthSource {
  Future<bool> get isAvailable;

  /// Einmal Berechtigung anfragen (iOS zeigt die Abfrage nur für neue Datentypen).
  Future<void> requestAccess();

  Future<List<HealthQuantitySample>> quantities(HealthQuantity kind, {required DateTime from, required DateTime to});

  Future<List<SleepSample>> sleep({required DateTime from, required DateTime to});

  Future<List<HealthWorkout>> workouts({required DateTime from, required DateTime to});
}

/// Keine Berechtigung erteilt.
final class HealthAccessDenied implements Exception {
  const HealthAccessDenied();

  @override
  String toString() => 'Zugriff auf die Gesundheitsdaten wurde nicht erlaubt.';
}

/// Umsetzung mit dem Paket `health` (HealthKit auf iOS, Health Connect auf Android).
final class PluginHealthSource implements HealthSource {
  PluginHealthSource({Health? health}) : _health = health ?? Health();

  final Health _health;
  bool _configured = false;

  static const _quantityTypes = {
    HealthQuantity.steps: HealthDataType.STEPS,
    HealthQuantity.activeEnergy: HealthDataType.ACTIVE_ENERGY_BURNED,
    HealthQuantity.basalEnergy: HealthDataType.BASAL_ENERGY_BURNED,
    HealthQuantity.restingHeartRate: HealthDataType.RESTING_HEART_RATE,
    HealthQuantity.hrvSDNN: HealthDataType.HEART_RATE_VARIABILITY_SDNN,
    HealthQuantity.respiratoryRate: HealthDataType.RESPIRATORY_RATE,
    HealthQuantity.oxygenSaturation: HealthDataType.BLOOD_OXYGEN,
    HealthQuantity.heartRate: HealthDataType.HEART_RATE,
    HealthQuantity.bodyMass: HealthDataType.WEIGHT,
    HealthQuantity.distanceWalkingRunning: HealthDataType.DISTANCE_WALKING_RUNNING,
    HealthQuantity.distanceCycling: HealthDataType.DISTANCE_CYCLING,
    HealthQuantity.distanceSwimming: HealthDataType.DISTANCE_SWIMMING,
  };

  static const _sleepTypes = {
    HealthDataType.SLEEP_IN_BED: SleepStage.inBed,
    HealthDataType.SLEEP_ASLEEP: SleepStage.asleep,
    HealthDataType.SLEEP_AWAKE: SleepStage.awake,
    HealthDataType.SLEEP_LIGHT: SleepStage.core,
    HealthDataType.SLEEP_DEEP: SleepStage.deep,
    HealthDataType.SLEEP_REM: SleepStage.rem,
  };

  List<HealthDataType> get _readTypes => [
    ..._quantityTypes.values,
    ..._sleepTypes.keys,
    HealthDataType.WORKOUT,
  ].where(_health.isDataTypeAvailable).toList();

  Future<void> _configure() async {
    if (_configured) return;
    await _health.configure();
    _configured = true;
  }

  @override
  Future<bool> get isAvailable async {
    if (!Platform.isIOS && !Platform.isAndroid) return false;
    try {
      await _configure();
      return await _health.isHealthConnectAvailable();
    } on Object {
      return false;
    }
  }

  @override
  Future<void> requestAccess() async {
    await _configure();
    final types = _readTypes;
    final granted = await _health.requestAuthorization(
      types,
      permissions: [for (final _ in types) HealthDataAccess.READ],
    );
    // iOS meldet aus Datenschutzgründen nicht, ob Lesen erlaubt wurde; nur Android lehnt erkennbar ab.
    if (!granted && Platform.isAndroid) throw const HealthAccessDenied();
  }

  Future<List<HealthDataPoint>> _points(List<HealthDataType> types, DateTime from, DateTime to) async {
    await _configure();
    final available = types.where(_health.isDataTypeAvailable).toList();
    if (available.isEmpty) return const [];
    return _health.getHealthDataFromTypes(types: available, startTime: from, endTime: to);
  }

  static double? _number(HealthDataPoint point) => switch (point.value) {
    NumericHealthValue(:final numericValue) => numericValue.toDouble(),
    _ => null,
  };

  @override
  Future<List<HealthQuantitySample>> quantities(
    HealthQuantity kind, {
    required DateTime from,
    required DateTime to,
  }) async {
    final type = _quantityTypes[kind]!;
    return [
      for (final point in await _points([type], from, to))
        if (_number(point) case final value?)
          HealthQuantitySample(start: point.dateFrom, end: point.dateTo, value: value, source: point.sourceId),
    ];
  }

  @override
  Future<List<SleepSample>> sleep({required DateTime from, required DateTime to}) async => [
    for (final point in await _points(_sleepTypes.keys.toList(), from, to))
      if (_sleepTypes[point.type] case final stage?)
        SleepSample(start: point.dateFrom, end: point.dateTo, stage: stage, source: point.sourceId),
  ];

  @override
  Future<List<HealthWorkout>> workouts({required DateTime from, required DateTime to}) async {
    final points = await _points([HealthDataType.WORKOUT], from, to);
    if (points.isEmpty) return const [];
    // Puls je Workout aus den Pulswerten im Zeitraum (das Paket liefert keine Workout-Statistik).
    final heart = await _points([HealthDataType.HEART_RATE], from, to);
    return [
      for (final point in points)
        if (point.value case final WorkoutHealthValue workout) _workout(point, workout, heart),
    ];
  }

  static HealthWorkout _workout(HealthDataPoint point, WorkoutHealthValue value, List<HealthDataPoint> heart) {
    final rates = [
      for (final sample in heart)
        if (!sample.dateFrom.isBefore(point.dateFrom) && !sample.dateFrom.isAfter(point.dateTo)) ?_number(sample),
    ];
    return HealthWorkout(
      uuid: uuidOf(point.uuid),
      typeKey: typeKey(value.workoutActivityType),
      start: point.dateFrom,
      end: point.dateTo,
      distanceMeters: value.totalDistance?.toDouble(),
      kilocalories: value.totalEnergyBurned?.toDouble(),
      averageHeartRate: rates.isEmpty ? null : rates.reduce((a, b) => a + b) / rates.length,
      maxHeartRate: rates.isEmpty ? null : rates.reduce((a, b) => a > b ? a : b),
      elevationGain: null,
      sourceName: point.sourceName,
      sourceBundle: point.sourceId,
    );
  }

  static final _hexUuid = RegExp(r'^[0-9a-fA-F]{8}-?[0-9a-fA-F]{4}-?[0-9a-fA-F]{4}-?[0-9a-fA-F]{4}-?[0-9a-fA-F]{12}$');

  /// Kennungen, die keine UUID sind (manche Health-Connect-Quellen), werden stabil in eine UUID-Form gebracht, damit die
  /// Aktivitäts-ID (`HealthImport.activityID`) daraus entsteht.
  static String uuidOf(String id) {
    if (_hexUuid.hasMatch(id)) return id;
    final a = fnv1a64Text(id).toRadixString(16).padLeft(16, '0');
    final b = fnv1a64Text('$id#').toRadixString(16).padLeft(16, '0');
    final hex = '$a$b';
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-'
        '${hex.substring(20, 32)}';
  }

  /// Sportart als Garmin-Schlüssel (wie `HealthImportService.typeKey` in Swift).
  static String typeKey(HealthWorkoutActivityType type) => switch (type) {
    HealthWorkoutActivityType.RUNNING || HealthWorkoutActivityType.RUNNING_TREADMILL => 'running',
    HealthWorkoutActivityType.BIKING ||
    HealthWorkoutActivityType.HAND_CYCLING ||
    HealthWorkoutActivityType.BIKING_STATIONARY => 'cycling',
    HealthWorkoutActivityType.SWIMMING_OPEN_WATER => 'open_water_swimming',
    HealthWorkoutActivityType.SWIMMING || HealthWorkoutActivityType.SWIMMING_POOL => 'lap_swimming',
    HealthWorkoutActivityType.TRADITIONAL_STRENGTH_TRAINING ||
    HealthWorkoutActivityType.FUNCTIONAL_STRENGTH_TRAINING ||
    HealthWorkoutActivityType.STRENGTH_TRAINING ||
    HealthWorkoutActivityType.CORE_TRAINING => 'strength_training',
    HealthWorkoutActivityType.WALKING || HealthWorkoutActivityType.WALKING_TREADMILL => 'walking',
    HealthWorkoutActivityType.HIKING => 'hiking',
    HealthWorkoutActivityType.HIGH_INTENSITY_INTERVAL_TRAINING ||
    HealthWorkoutActivityType.MIXED_CARDIO ||
    HealthWorkoutActivityType.CROSS_TRAINING => 'hiit',
    HealthWorkoutActivityType.YOGA ||
    HealthWorkoutActivityType.PILATES ||
    HealthWorkoutActivityType.FLEXIBILITY ||
    HealthWorkoutActivityType.MIND_AND_BODY => 'yoga',
    HealthWorkoutActivityType.ROWING || HealthWorkoutActivityType.ROWING_MACHINE => 'indoor_rowing',
    HealthWorkoutActivityType.ELLIPTICAL => 'elliptical',
    _ => 'other',
  };
}
