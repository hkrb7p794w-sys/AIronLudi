import 'package:coach_core/coach_core.dart';
import 'package:drift/drift.dart';

import '../db/database.dart';
import 'json_bytes.dart';

/// Tageswerte (wie `DailyMetricsRecord`): je Tag ein Datensatz mit JSON `DailyMetrics`.
final class MetricsRepository {
  MetricsRepository(this._db);

  final CoachDatabase _db;

  Future<List<DailyMetrics>> all() async => [
    for (final row in await (_db.select(
      _db.dailyMetricsRecords,
    )..orderBy([(t) => OrderingTerm(expression: t.dayKey)])).get())
      ?decodeJson(row.payload, DailyMetrics.fromJson),
  ];

  /// Tage von [from] bis [to] (einschließlich), aufsteigend.
  Future<List<DailyMetrics>> range({required CalendarDay from, required CalendarDay to}) async {
    final query = _db.select(_db.dailyMetricsRecords)
      ..where((t) => t.dayKey.isBetweenValues(from.iso, to.iso))
      ..orderBy([(t) => OrderingTerm(expression: t.dayKey)]);
    return [for (final row in await query.get()) ?decodeJson(row.payload, DailyMetrics.fromJson)];
  }

  Future<DailyMetrics?> day(CalendarDay day) async {
    final row = await (_db.select(_db.dailyMetricsRecords)..where((t) => t.dayKey.equals(day.iso))).getSingleOrNull();
    return row == null ? null : decodeJson(row.payload, DailyMetrics.fromJson);
  }

  /// Mit dem Gespeicherten zusammenführen (vorhandene Felder bleiben, neue überschreiben), wie `update(_:)`.
  Future<void> merge(DailyMetrics metrics, {DateTime? at}) async {
    final existing = await day(metrics.day);
    await replace(existing == null ? metrics : existing.merging(metrics), at: at);
  }

  /// Ersetzt die Werte des Tages (nach dem Zusammenführen aller Quellen).
  Future<void> replace(DailyMetrics metrics, {DateTime? at}) => _db
      .into(_db.dailyMetricsRecords)
      .insertOnConflictUpdate(
        DailyMetricsRecordsCompanion.insert(
          dayKey: metrics.day.iso,
          payload: encodeJson(metrics.toJson()),
          updatedAt: at ?? DateTime.now(),
        ),
      );

  /// Zeitpunkt der letzten Änderung je Tag.
  Future<Map<String, DateTime>> updatedAt() async => {
    for (final row in await _db.select(_db.dailyMetricsRecords).get()) row.dayKey: row.updatedAt,
  };
}

/// Aktivitäten (wie `ActivityRecord`): je ID ein Datensatz mit JSON `GarminActivity`.
final class ActivityRepository {
  ActivityRepository(this._db);

  final CoachDatabase _db;

  Future<List<GarminActivity>> all() async => [
    for (final row in await (_db.select(
      _db.activityRecords,
    )..orderBy([(t) => OrderingTerm(expression: t.startLocal)])).get())
      ?decodeJson(row.payload, GarminActivity.fromJson),
  ];

  Future<List<GarminActivity>> range({required CalendarDay from, required CalendarDay to}) async {
    final query = _db.select(_db.activityRecords)
      ..where((t) => t.dayKey.isBetweenValues(from.iso, to.iso))
      ..orderBy([(t) => OrderingTerm(expression: t.startLocal)]);
    return [for (final row in await query.get()) ?decodeJson(row.payload, GarminActivity.fromJson)];
  }

  Future<GarminActivity?> byID(int id) async {
    final row = await (_db.select(_db.activityRecords)..where((t) => t.garminID.equals(id))).getSingleOrNull();
    return row == null ? null : decodeJson(row.payload, GarminActivity.fromJson);
  }

  Future<void> upsert(GarminActivity activity) => _db
      .into(_db.activityRecords)
      .insertOnConflictUpdate(
        ActivityRecordsCompanion.insert(
          garminID: Value(activity.id),
          dayKey: activity.day?.iso ?? '',
          startLocal: activity.startLocal ?? '',
          payload: encodeJson(activity.toJson()),
        ),
      );

  Future<void> upsertAll(Iterable<GarminActivity> activities) => _db.batch((batch) {
    batch.insertAllOnConflictUpdate(_db.activityRecords, [
      for (final activity in activities)
        ActivityRecordsCompanion.insert(
          garminID: Value(activity.id),
          dayKey: activity.day?.iso ?? '',
          startLocal: activity.startLocal ?? '',
          payload: encodeJson(activity.toJson()),
        ),
    ]);
  });

  Future<int> delete(Iterable<int> ids) =>
      (_db.delete(_db.activityRecords)..where((t) => t.garminID.isIn(ids.toList()))).go();
}

/// Letzte Rohantwort je Endpunkt (Diagnose).
final class RawResponseRepository {
  RawResponseRepository(this._db);

  final CoachDatabase _db;

  Future<void> store(String endpoint, List<int> body, {DateTime? at}) => _db
      .into(_db.rawResponseRecords)
      .insertOnConflictUpdate(
        RawResponseRecordsCompanion.insert(
          endpoint: endpoint,
          fetchedAt: at ?? DateTime.now(),
          body: Uint8List.fromList(body),
        ),
      );

  Future<List<RawResponseRow>> all() =>
      (_db.select(_db.rawResponseRecords)..orderBy([(t) => OrderingTerm(expression: t.endpoint)])).get();
}
