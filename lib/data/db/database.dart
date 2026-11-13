import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

part 'database.g.dart';

/// Tageswerte eines Kalendertags. Die Werte liegen als JSON (`DailyMetrics`) vor, damit neue Felder keine
/// Datenbank-Migration brauchen (wie `DailyMetricsRecord` der Swift-App).
@DataClassName('DailyMetricsRow')
class DailyMetricsRecords extends Table {
  TextColumn get dayKey => text()();
  BlobColumn get payload => blob()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {dayKey};
}

/// Eine Aktivität (Zusammenfassung, JSON `GarminActivity`).
@DataClassName('ActivityRow')
class ActivityRecords extends Table {
  IntColumn get garminID => integer()();
  TextColumn get dayKey => text()();
  TextColumn get startLocal => text()();
  BlobColumn get payload => blob()();

  @override
  Set<Column<Object>> get primaryKey => {garminID};
}

/// Letzte Rohantwort je Endpunkt – für die Diagnose und um die Zuordnung später ohne neuen Abruf anpassen zu können.
@DataClassName('RawResponseRow')
class RawResponseRecords extends Table {
  TextColumn get endpoint => text()();
  DateTimeColumn get fetchedAt => dateTime()();
  BlobColumn get body => blob()();

  @override
  Set<Column<Object>> get primaryKey => {endpoint};
}

/// Ein importierter Datensatz eines Anbieters mit Herkunft (`SourceEntry`); bei Tageswerten zusätzlich der Rohwert des
/// Anbieters (`payload`), aus dem die Tageswerte je nach Quellen-Einstellung neu berechnet werden.
@DataClassName('SourceRow')
class SourceRecords extends Table {
  /// `provider|kind|externalID`
  TextColumn get key => text()();
  TextColumn get provider => text()();
  TextColumn get kind => text()();
  TextColumn get externalID => text()();
  TextColumn get dayKey => text()();
  DateTimeColumn get start => dateTime().nullable()();
  DateTimeColumn get importedAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  TextColumn get contentHash => text()();
  TextColumn get status => text()();
  BlobColumn get payload => blob().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {key};
}

/// Eine gespeicherte Mahlzeit; die Positionen liegen als JSON (`[MealItem]`) vor.
@DataClassName('MealRow')
class MealRecords extends Table {
  TextColumn get id => text()();
  TextColumn get dayKey => text()();
  DateTimeColumn get createdAt => dateTime()();
  TextColumn get categoryRaw => text()();
  TextColumn get title => text()();
  TextColumn get hint => text()();
  BlobColumn get itemsPayload => blob()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Eigenes bzw. zuletzt genutztes Lebensmittel (auch Open-Food-Facts-Zwischenspeicher je Barcode).
@DataClassName('FoodRow')
class FoodRecords extends Table {
  TextColumn get key => text()();
  TextColumn get name => text()();
  BlobColumn get payload => blob()();
  DateTimeColumn get lastUsed => dateTime()();
  IntColumn get useCount => integer()();

  @override
  Set<Column<Object>> get primaryKey => {key};
}

/// Eine gespeicherte Krafteinheit (JSON `GymSession`).
@DataClassName('GymSessionRow')
class GymSessionRecords extends Table {
  TextColumn get id => text()();
  TextColumn get dayKey => text()();
  DateTimeColumn get start => dateTime()();
  BlobColumn get payload => blob()();

  /// In Apple Health bzw. Health Connect gespeichert.
  BoolColumn get savedToHealth => boolean().withDefault(const Constant(false))();

  /// Als Krafttraining nach Garmin Connect übertragen.
  BoolColumn get uploadedToGarmin => boolean().withDefault(const Constant(false))();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Einstellungen der App (`coach.*` und die Worker-Adresse) wie die UserDefaults der Swift-App: Typ und Wert je
/// Schlüssel. So bleibt jeder Wert beim Sichern und Einspielen genau erhalten (`AppBackup.Value`).
@DataClassName('SettingRow')
class SettingRecords extends Table {
  TextColumn get key => text()();

  /// `data`, `string`, `bool`, `int` oder `double`.
  TextColumn get type => text()();

  /// Bei `data` die Bytes (meist JSON), sonst der Wert als UTF-8-Text.
  BlobColumn get value => blob()();

  @override
  Set<Column<Object>> get primaryKey => {key};
}

@DriftDatabase(
  tables: [
    DailyMetricsRecords,
    ActivityRecords,
    RawResponseRecords,
    SourceRecords,
    MealRecords,
    FoodRecords,
    GymSessionRecords,
    SettingRecords,
  ],
)
final class CoachDatabase extends _$CoachDatabase {
  CoachDatabase(super.executor);

  /// Datei `coach.sqlite` im Anwendungsverzeichnis.
  factory CoachDatabase.open() => CoachDatabase(driftDatabase(name: 'coach'));

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (migrator) => migrator.createAll(),
    beforeOpen: (details) async => customStatement('PRAGMA foreign_keys = ON'),
  );
}
