import 'package:coach_core/coach_core.dart';
import 'package:drift/drift.dart';

import '../db/database.dart';
import 'json_bytes.dart';

/// Eine gespeicherte Krafteinheit mit Status (wie `GymSessionRecord`).
final class StoredGymSession {
  const StoredGymSession({required this.session, required this.savedToHealth, required this.uploadedToGarmin});

  final GymSession session;

  /// In Apple Health bzw. Health Connect gespeichert.
  final bool savedToHealth;

  /// Als Krafttraining nach Garmin Connect übertragen.
  final bool uploadedToGarmin;
}

/// Krafteinheiten.
final class GymRepository {
  GymRepository(this._db);

  final CoachDatabase _db;

  /// Beim Lesen vereinheitlicht (`ExerciseAliases`); die gespeicherten Daten bleiben unverändert.
  static StoredGymSession? _stored(GymSessionRow row) {
    final session = decodeJson(row.payload, GymSession.fromJson);
    if (session == null) return null;
    return StoredGymSession(
      session: ExerciseAliases.normalized(session),
      savedToHealth: row.savedToHealth,
      uploadedToGarmin: row.uploadedToGarmin,
    );
  }

  Future<List<StoredGymSession>> all() async => [
    for (final row in await (_db.select(
      _db.gymSessionRecords,
    )..orderBy([(t) => OrderingTerm(expression: t.start)])).get())
      ?_stored(row),
  ];

  Future<List<GymSession>> sessions() async => [for (final stored in await all()) stored.session];

  Future<StoredGymSession?> byID(String id) async {
    final row = await (_db.select(_db.gymSessionRecords)..where((t) => t.id.equals(id))).getSingleOrNull();
    return row == null ? null : _stored(row);
  }

  /// Speichert die Einheit; der Status (Health, Garmin) bleibt, wenn sie schon existiert.
  Future<void> save(GymSession session, {bool? savedToHealth, bool? uploadedToGarmin}) => _db
      .into(_db.gymSessionRecords)
      .insertOnConflictUpdate(
        GymSessionRecordsCompanion(
          id: Value(session.id),
          dayKey: Value(session.day.iso),
          start: Value(session.start),
          payload: Value(encodeJson(session.toJson())),
          savedToHealth: savedToHealth == null ? const Value.absent() : Value(savedToHealth),
          uploadedToGarmin: uploadedToGarmin == null ? const Value.absent() : Value(uploadedToGarmin),
        ),
      );

  Future<void> setSavedToHealth(String id, {required bool value}) => (_db.update(
    _db.gymSessionRecords,
  )..where((t) => t.id.equals(id))).write(GymSessionRecordsCompanion(savedToHealth: Value(value)));

  Future<void> setUploadedToGarmin(String id, {required bool value}) => (_db.update(
    _db.gymSessionRecords,
  )..where((t) => t.id.equals(id))).write(GymSessionRecordsCompanion(uploadedToGarmin: Value(value)));

  /// Garmin-Verbindung setzen, ohne die übrigen gespeicherten Daten umzudeuten (roh lesen, nur `garmin` ändern).
  Future<void> setGarmin(String id, GarminLink? link) async {
    final row = await (_db.select(_db.gymSessionRecords)..where((t) => t.id.equals(id))).getSingleOrNull();
    if (row == null) return;
    final raw = decodeJson(row.payload, (json) => json is Map ? Map<String, Object?>.from(json) : null);
    if (raw == null) return;
    if (link == null) {
      raw.remove('garmin');
    } else {
      raw['garmin'] = link.toJson();
    }
    await (_db.update(
      _db.gymSessionRecords,
    )..where((t) => t.id.equals(id))).write(GymSessionRecordsCompanion(payload: Value(encodeJson(raw))));
  }

  Future<void> delete(String id) => (_db.delete(_db.gymSessionRecords)..where((t) => t.id.equals(id))).go();
}
