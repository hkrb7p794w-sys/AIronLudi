/// Schreibstatus für Workouts, unabhängig von der Plattform.
enum WorkoutShareStatus { notDetermined, denied, authorized }

/// Fehler, den die Health-Schnittstelle geliefert hat (Domain, Code, Text).
final class HealthErrorInfo {
  const HealthErrorInfo({required this.domain, required this.code, required this.message});

  final String domain;
  final int code;
  final String message;

  /// HealthKit meldet ein fehlendes Entitlement als `com.apple.healthkit` Code 4 mit „Missing
  /// com.apple.developer.healthkit entitlement.“
  bool get isMissingEntitlement => message.toLowerCase().contains('entitlement');
}

/// Bewertet, ob Apple Health bzw. Health Connect in dieser Installation nutzbar ist.
///
/// Hintergrund: SideStore übernimmt beim Signieren mit kostenloser Apple-ID nur Entitlements, die im
/// Provisioning-Profil stehen, und schaltet HealthKit für die App-ID nicht frei. Dann fehlt
/// `com.apple.developer.healthkit` und jeder HealthKit-Aufruf scheitert. Die App muss das erkennen und
/// Health-Funktionen abschalten, statt Fehler anzuzeigen.
///
/// Leserechte meldet HealthKit aus Datenschutzgründen nie zurück. Verlässlich ist nur der Schreibstatus – er belegt,
/// dass das Entitlement wirkt.
sealed class HealthAccessDiagnosis {
  const HealthAccessDiagnosis();

  /// Gerät ohne Health-Datenbank (z. B. manche iPads).
  static const unavailable = _Plain('unavailable');

  /// Signatur ohne HealthKit-Entitlement (typisch für SideStore mit kostenloser Apple-ID).
  static const missingEntitlement = _Plain('missingEntitlement');

  /// Nutzer hat das Schreiben von Workouts abgelehnt.
  static const denied = _Plain('denied');

  /// Noch nicht gefragt.
  static const notDetermined = _Plain('notDetermined');

  bool get isUsable => this is HealthWorking;

  String get title => switch (this) {
    _Plain(name: 'unavailable') => 'Nicht verfügbar',
    _Plain(name: 'missingEntitlement') => 'Berechtigung fehlt in der Signatur',
    _Plain(name: 'denied') => 'Zugriff abgelehnt',
    _Plain() => 'Noch nicht angefragt',
    HealthWorking() => 'HealthKit funktioniert',
    HealthFailed() => 'Fehler',
  };

  String get detail => switch (this) {
    _Plain(name: 'unavailable') => 'Auf diesem Gerät gibt es keine Health-Daten.',
    _Plain(name: 'missingEntitlement') =>
      'Die installierte App hat kein HealthKit-Entitlement (SideStore mit kostenloser Apple-ID '
          'entfernt es). Die App läuft ohne HealthKit weiter; Garmin-Daten kommen über das Backend.',
    _Plain(name: 'denied') => 'Bitte in Einstellungen › Apps › Health › Datenzugriff › AIronLudi freigeben.',
    _Plain() => 'Tippe auf „HealthKit prüfen“.',
    HealthWorking(readableWorkouts: final count?) => 'Schreiben erlaubt, $count Workouts der letzten 30 Tage lesbar.',
    HealthWorking() => 'Schreiben erlaubt.',
    HealthFailed(:final message) => message,
  };

  /// Leitet die Diagnose aus den Rohergebnissen der Health-Aufrufe ab.
  static HealthAccessDiagnosis evaluate({
    required bool isHealthDataAvailable,
    required HealthErrorInfo? authorizationError,
    required WorkoutShareStatus? workoutShareStatus,
    required int? readableWorkouts,
    HealthErrorInfo? queryError,
  }) {
    if (!isHealthDataAvailable) return unavailable;
    for (final error in [authorizationError, queryError].nonNulls) {
      if (error.isMissingEntitlement) return missingEntitlement;
    }
    if (authorizationError != null) {
      return HealthFailed('${authorizationError.message} (${authorizationError.domain} ${authorizationError.code})');
    }
    return switch (workoutShareStatus) {
      WorkoutShareStatus.authorized => HealthWorking(queryError == null ? readableWorkouts : null),
      WorkoutShareStatus.denied => denied,
      WorkoutShareStatus.notDetermined || null => notDetermined,
    };
  }
}

final class _Plain extends HealthAccessDiagnosis {
  const _Plain(this.name);

  final String name;

  @override
  String toString() => name;
}

/// Health funktioniert; [readableWorkouts] = gelesene Workouts der letzten 30 Tage.
final class HealthWorking extends HealthAccessDiagnosis {
  const HealthWorking(this.readableWorkouts);

  final int? readableWorkouts;

  @override
  bool operator ==(Object other) => other is HealthWorking && other.readableWorkouts == readableWorkouts;

  @override
  int get hashCode => readableWorkouts.hashCode;

  @override
  String toString() => 'working($readableWorkouts)';
}

/// Sonstiger Fehler mit Originaltext.
final class HealthFailed extends HealthAccessDiagnosis {
  const HealthFailed(this.message);

  final String message;

  @override
  bool operator ==(Object other) => other is HealthFailed && other.message == message;

  @override
  int get hashCode => message.hashCode;

  @override
  String toString() => 'failed($message)';
}
