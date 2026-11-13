import 'dart:io';

import 'package:coach_core/coach_core.dart';
import 'package:health/health.dart';

/// Fehler beim Speichern eines Workouts in Health.
enum WorkoutWriterError implements Exception {
  unavailable('Apple Health ist auf diesem Gerät nicht verfügbar.'),
  notAuthorized('Keine Schreibberechtigung für Workouts. Einstellungen › Health › Datenzugriff › AIronLudi prüfen.');

  const WorkoutWriterError(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Speichert eine Krafteinheit als Workout in Health.
abstract interface class WorkoutSaving {
  Future<bool> get isAvailable;

  Future<void> save(GymSession session);
}

/// Health ist optional (SideStore kann das Entitlement entfernen); Fehler landen als Text in der App.
final class HealthWorkoutWriter implements WorkoutSaving {
  HealthWorkoutWriter({Health? health}) : _health = health ?? Health();

  final Health _health;

  @override
  Future<bool> get isAvailable async {
    if (!Platform.isIOS && !Platform.isAndroid) return false;
    try {
      await _health.configure();
      return await _health.isHealthConnectAvailable();
    } on Object {
      return false;
    }
  }

  @override
  Future<void> save(GymSession session) async {
    if (!await isAvailable) throw WorkoutWriterError.unavailable;
    const types = [HealthDataType.WORKOUT];
    const access = [HealthDataAccess.READ_WRITE];
    if (await _health.hasPermissions(types, permissions: access) != true) {
      await _health.requestAuthorization(types, permissions: access);
    }
    final saved = await _health.writeWorkoutData(
      activityType: HealthWorkoutActivityType.TRADITIONAL_STRENGTH_TRAINING,
      start: session.start,
      end: session.end ?? DateTime.now(),
      title: session.title,
    );
    if (!saved) throw WorkoutWriterError.notAuthorized;
  }
}

/// Prüft, ob Health in dieser Installation funktioniert (wie `HealthKitProbe`): Rechte anfragen, Workouts der letzten
/// 30 Tage lesen und das Ergebnis mit `HealthAccessDiagnosis.evaluate` bewerten.
final class HealthProbe {
  HealthProbe({Health? health}) : _health = health ?? Health();

  final Health _health;

  static const readTypes = [
    HealthDataType.WORKOUT,
    HealthDataType.SLEEP_ASLEEP,
    HealthDataType.HEART_RATE,
    HealthDataType.RESTING_HEART_RATE,
    HealthDataType.HEART_RATE_VARIABILITY_SDNN,
  ];

  static HealthErrorInfo _info(Object error) =>
      HealthErrorInfo(domain: error.runtimeType.toString(), code: 0, message: '$error');

  Future<HealthAccessDiagnosis> run() async {
    if (!Platform.isIOS && !Platform.isAndroid) return HealthAccessDiagnosis.unavailable;
    try {
      await _health.configure();
      if (!await _health.isHealthConnectAvailable()) return HealthAccessDiagnosis.unavailable;
    } on Object {
      return HealthAccessDiagnosis.unavailable;
    }
    final types = readTypes.where(_health.isDataTypeAvailable).toList();
    HealthErrorInfo? authorizationError;
    try {
      await _health.requestAuthorization(
        types,
        permissions: [
          for (final type in types)
            type == HealthDataType.WORKOUT ? HealthDataAccess.READ_WRITE : HealthDataAccess.READ,
        ],
      );
    } on Object catch (error) {
      authorizationError = _info(error);
    }

    int? readableWorkouts;
    HealthErrorInfo? queryError;
    if (authorizationError == null) {
      try {
        final now = DateTime.now();
        readableWorkouts = (await _health.getHealthDataFromTypes(
          types: const [HealthDataType.WORKOUT],
          startTime: now.subtract(const Duration(days: 30)),
          endTime: now,
        )).length;
      } on Object catch (error) {
        queryError = _info(error);
      }
    }
    final share = await _health
        .hasPermissions(const [HealthDataType.WORKOUT], permissions: const [HealthDataAccess.WRITE])
        .catchError((Object _) => null);
    return HealthAccessDiagnosis.evaluate(
      isHealthDataAvailable: true,
      authorizationError: authorizationError,
      workoutShareStatus: switch (share) {
        true => WorkoutShareStatus.authorized,
        false => WorkoutShareStatus.denied,
        null => WorkoutShareStatus.notDetermined,
      },
      readableWorkouts: readableWorkouts,
      queryError: queryError,
    );
  }
}
