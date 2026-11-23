import 'package:coach_core/coach_core.dart';
import 'package:drift/drift.dart';

import '../db/database.dart';
import 'json_bytes.dart';

/// Gespeicherte Routen (Tabelle `RouteRecords`): je Benutzer und Route eine Zeile, Speichern schreibt nur diese.
final class RouteRepository {
  RouteRepository(this._db);

  final CoachDatabase _db;

  /// Routen des Benutzers, zuletzt gespeicherte zuerst; unlesbare Zeilen fallen weg.
  Future<List<(PlannedRoute, DateTime)>> all(String username) async {
    final query = _db.select(_db.routeRecords)
      ..where((t) => t.username.equals(username))
      ..orderBy([(t) => OrderingTerm(expression: t.savedAt, mode: OrderingMode.desc)]);
    return [
      for (final row in await query.get())
        if (decodeJson(row.payload, (json) => PlannedRoute.fromJson(json, username: username)) case final route?)
          (route, row.savedAt),
    ];
  }

  Future<void> putAll(Iterable<(PlannedRoute, DateTime)> routes) => _db.batch((batch) {
    batch.insertAllOnConflictUpdate(_db.routeRecords, [
      for (final (route, savedAt) in routes)
        RouteRecordsCompanion.insert(
          username: route.username,
          id: route.id,
          savedAt: savedAt,
          payload: encodeJson(route.toJson()),
        ),
    ]);
  });

  Future<void> delete(String username, Iterable<String> ids) async {
    final list = ids.toList();
    if (list.isEmpty) return;
    await (_db.delete(_db.routeRecords)..where((t) => t.username.equals(username) & t.id.isIn(list))).go();
  }

  /// Für die Sicherung: alle Routen als `RouteLibrary`-JSON (wie bisher unter `coach.routes`). Je Datenbank gibt es
  /// normalerweise nur einen Benutzer; sonst zählt der mit den meisten Routen. `null` ohne Routen.
  Future<Map<String, Object?>?> libraryJson() async {
    final rows = await _db.select(_db.routeRecords).get();
    if (rows.isEmpty) return null;
    final counts = <String, int>{};
    for (final row in rows) {
      counts[row.username] = (counts[row.username] ?? 0) + 1;
    }
    final username = counts.entries.reduce((a, b) => b.value > a.value ? b : a).key;
    final routes = await all(username);
    return RouteLibrary(username: username, routes: [for (final (route, _) in routes) route]).toJson();
  }
}
