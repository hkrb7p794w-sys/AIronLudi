import '../util/enum_codec.dart';

/// Datenarten, die Anbieter liefern können. Herstellerunabhängig: Jede Art wird intern immer gleich abgebildet,
/// egal woher sie kommt.
enum DataKind implements RawEnum {
  activities('Sportaktivitäten'),
  workoutHeartRate('Herzfrequenz im Training'),
  sleep('Schlaf'),
  hrv('HRV'),
  restingHeartRate('Ruhepuls'),
  stress('Stress'),
  calories('Kalorien'),
  steps('Schritte'),
  trainingLoad('Trainingsbelastung'),
  recovery('Erholung (Recovery)'),
  body('Körperwerte');

  const DataKind(this.label);

  final String label;

  @override
  String get rawValue => name;
}

/// Stand der Anbindung in dieser App – nur was wirklich funktioniert, gilt als verfügbar.
enum ProviderAvailability implements RawEnum {
  /// Eingebaut und nutzbar.
  available,

  /// Offizielle API vorhanden, Anbindung in der App noch nicht gebaut.
  planned,

  /// Derzeit nicht anbindbar (z. B. API abgeschaltet).
  unavailable;

  @override
  String get rawValue => name;
}

/// Externe Datenquellen. Jeder Anbieter ist ein eigenes Modul; zentrale Modelle hängen nicht davon ab.
///
/// Der Rohwert `appleHealth` bleibt auch auf Android bestehen (Sicherungen); dort steht er für Health Connect.
enum DataProvider implements RawEnum {
  garmin('Garmin'),
  appleHealth('Apple Health'),
  whoop('WHOOP'),
  polar('Polar'),
  fitbit('Fitbit');

  const DataProvider(this.label);

  final String label;

  @override
  String get rawValue => name;

  ProviderAvailability get availability => switch (this) {
    garmin || appleHealth => ProviderAvailability.available,
    whoop || polar => ProviderAvailability.planned,
    fitbit => ProviderAvailability.unavailable,
  };

  /// Kurz, warum (für die Einstellungen).
  String get availabilityNote => switch (this) {
    garmin => 'Garmin-Konto (Connect) oder Personal API.',
    appleHealth => 'Über HealthKit auf dem iPhone, sofern SideStore die Berechtigung erhält.',
    whoop =>
      'Offizielle API (v2, OAuth). Noch nicht eingebaut; braucht eine eigene WHOOP-App im Developer-Dashboard und '
          'den Worker für den Token-Tausch. Bis dahin: WHOOP schreibt Schlaf, Ruhepuls und Workouts in Apple Health '
          '(keine HRV).',
    polar =>
      'Offizielle AccessLink-API (OAuth). Noch nicht eingebaut; braucht einen eigenen Polar-Client und den Worker. '
          'Bis dahin: Polar Flow schreibt Trainings in Apple Health.',
    fitbit =>
      'Die Fitbit Web API wurde laut Google am 30.10.2026 abgeschaltet; Nachfolger ist die Google Health API '
          '(Google-OAuth, Prüfung durch Google). Fitbit schreibt nicht in Apple Health.',
  };

  /// Was der Anbieter grundsätzlich liefern kann (über seine API bzw. bei Apple Health über HealthKit).
  Set<DataKind> get capabilities => switch (this) {
    garmin => DataKind.values.toSet(),
    appleHealth => {
      DataKind.activities,
      DataKind.workoutHeartRate,
      DataKind.sleep,
      DataKind.hrv,
      DataKind.restingHeartRate,
      DataKind.calories,
      DataKind.steps,
      DataKind.body,
    },
    whoop => {
      DataKind.activities,
      DataKind.workoutHeartRate,
      DataKind.sleep,
      DataKind.hrv,
      DataKind.restingHeartRate,
      DataKind.calories,
      DataKind.recovery,
      DataKind.body,
    },
    polar => {
      DataKind.activities,
      DataKind.workoutHeartRate,
      DataKind.sleep,
      DataKind.hrv,
      DataKind.restingHeartRate,
      DataKind.calories,
      DataKind.steps,
      DataKind.trainingLoad,
      DataKind.recovery,
    },
    fitbit => {
      DataKind.activities,
      DataKind.sleep,
      DataKind.hrv,
      DataKind.restingHeartRate,
      DataKind.calories,
      DataKind.steps,
      DataKind.body,
    },
  };

  /// Stärken: Hier ist der Anbieter als primäres Gerät auch die bevorzugte Quelle.
  Set<DataKind> get strengths => switch (this) {
    garmin => {
      DataKind.activities,
      DataKind.workoutHeartRate,
      DataKind.trainingLoad,
      DataKind.stress,
      DataKind.recovery,
      DataKind.steps,
      DataKind.calories,
    },
    appleHealth => {DataKind.steps, DataKind.calories},
    whoop => {DataKind.sleep, DataKind.hrv, DataKind.restingHeartRate, DataKind.recovery},
    polar => {DataKind.activities, DataKind.workoutHeartRate, DataKind.trainingLoad},
    fitbit => {DataKind.steps, DataKind.sleep},
  };

  /// Allgemeine Rangfolge je Datenart (beste zuerst). Apple Health steht hinten, weil es meist nur weitergibt, was
  /// ein Gerät geschrieben hat (Gefahr doppelter Werte), und HRV dort SDNN statt RMSSD ist.
  static List<DataProvider> defaultOrder(DataKind kind) => switch (kind) {
    DataKind.hrv || DataKind.recovery || DataKind.sleep => [whoop, garmin, polar, fitbit, appleHealth],
    DataKind.restingHeartRate => [garmin, whoop, polar, fitbit, appleHealth],
    DataKind.activities ||
    DataKind.workoutHeartRate ||
    DataKind.trainingLoad => [garmin, polar, whoop, fitbit, appleHealth],
    DataKind.stress => [garmin, appleHealth, whoop, polar, fitbit],
    DataKind.calories || DataKind.steps || DataKind.body => [garmin, polar, fitbit, whoop, appleHealth],
  };
}

/// Welche Quelle je Datenart gilt: ein primäres Gerät und einzelne Ausnahmen.
final class SourcePreferences {
  SourcePreferences({this.primary, Map<DataKind, DataProvider>? overrides}) : overrides = overrides ?? {};

  DataProvider? primary;
  Map<DataKind, DataProvider> overrides;

  Map<String, Object?> toJson() => {
    'primary': ?primary?.rawValue,
    'overrides': {for (final MapEntry(:key, :value) in overrides.entries) key.rawValue: value.rawValue},
  };

  /// Tolerant: unbekannte Anbieter oder Datenarten (aus neueren Versionen) werden übersprungen.
  static SourcePreferences fromJson(Object? json) {
    final map = json is Map ? json : const <String, Object?>{};
    final rawPrimary = map['primary'];
    final rawOverrides = map['overrides'];
    final overrides = <DataKind, DataProvider>{};
    if (rawOverrides is Map && rawOverrides.values.every((value) => value is String)) {
      for (final MapEntry(:key, :value) in rawOverrides.entries) {
        final kind = enumFromRaw(DataKind.values, key);
        final provider = enumFromRaw(DataProvider.values, value);
        if (kind != null && provider != null) overrides[kind] = provider;
      }
    }
    return SourcePreferences(
      primary: rawPrimary is String ? enumFromRaw(DataProvider.values, rawPrimary) : null,
      overrides: overrides,
    );
  }

  /// Reihenfolge der verbundenen Quellen für eine Datenart: gewählte Quelle, dann das primäre Gerät (nur bei seinen
  /// Stärken), dann die allgemeine Rangfolge. Nur Anbieter, die die Art liefern können.
  List<DataProvider> order(DataKind kind, {required Set<DataProvider> connected}) {
    final result = <DataProvider>[];
    void add(DataProvider? provider) {
      if (provider == null ||
          !connected.contains(provider) ||
          !provider.capabilities.contains(kind) ||
          result.contains(provider)) {
        return;
      }
      result.add(provider);
    }

    add(overrides[kind]);
    if (primary case final primary? when primary.strengths.contains(kind)) add(primary);
    DataProvider.defaultOrder(kind).forEach(add);
    return result;
  }

  /// Bevorzugte Quelle (erste der Reihenfolge).
  DataProvider? preferred(DataKind kind, {required Set<DataProvider> connected}) =>
      order(kind, connected: connected).firstOrNull;

  @override
  bool operator ==(Object other) =>
      other is SourcePreferences &&
      other.primary == primary &&
      other.overrides.length == overrides.length &&
      overrides.entries.every((entry) => other.overrides[entry.key] == entry.value);

  @override
  int get hashCode => Object.hash(primary, Object.hashAllUnordered(overrides.entries.map((e) => (e.key, e.value))));
}
