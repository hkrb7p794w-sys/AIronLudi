import 'package:coach_core/coach_core.dart';
import 'package:drift/drift.dart';

import '../db/database.dart';
import '../settings/settings_store.dart';
import 'json_bytes.dart';
import 'metrics_repository.dart';

/// Gemeinsame Ablage aller Datenquellen (Port von `SourceStore`). Jeder Anbieter liefert seine Tageswerte und
/// Aktivitäten hier ab; die App liest weiter `DailyMetricsRecords` und `ActivityRecords`, die daraus nach den
/// Quellen-Einstellungen entstehen: je Datenart eine Quelle (`MetricsMerge`), Aktivitäten ohne Doppelte
/// (`ActivityMerge`). Jeder Datensatz behält seine Herkunft (`SourceRecords`).
final class SourceStore {
  SourceStore(this._db, this._settings, {SourcePreferences Function()? preferences})
    : preferences = preferences ?? SourcePreferences.new;

  final CoachDatabase _db;
  final SettingsStore _settings;

  /// Aktuelle Einstellungen (aus den Quellen-Einstellungen).
  SourcePreferences Function() preferences;

  static const migratedKey = SettingsKeys.sourcesMigrated;
  static const statesKey = SettingsKeys.sourcesSyncStates;
  static const dailyKind = 'daily';

  late final _metrics = MetricsRepository(_db);

  // Synchronisierungsstatus

  Map<DataProvider, ProviderSyncState> get syncStates {
    final raw = _settings.json(statesKey);
    if (raw is! Map) return {};
    final result = <DataProvider, ProviderSyncState>{};
    for (final MapEntry(:key, :value) in raw.entries) {
      final provider = enumFromRaw(DataProvider.values, key);
      final state = ProviderSyncState.fromJson(value);
      // Wie `JSONDecoder`: ein kaputter Eintrag macht das ganze Verzeichnis ungültig.
      if (state == null) return {};
      if (provider != null) result[provider] = state;
    }
    return result;
  }

  Future<void> setSyncStates(Map<DataProvider, ProviderSyncState> states) =>
      _settings.setJson(statesKey, {for (final MapEntry(:key, :value) in states.entries) key.rawValue: value.toJson()});

  Future<void> recordSuccess(DataProvider provider, {DateTime? now}) {
    final at = now ?? DateTime.now();
    final states = syncStates;
    (states[provider] ??= ProviderSyncState()).recordSuccess(now: at, day: CalendarDay.fromDate(at));
    return setSyncStates(states);
  }

  Future<void> recordFailure(DataProvider provider, {required String error, DateTime? now}) {
    final states = syncStates;
    (states[provider] ??= ProviderSyncState()).recordFailure(now: now ?? DateTime.now(), error: error);
    return setSyncStates(states);
  }

  // Altbestand

  /// Einmalig: Bisherige Tageswerte gelten als Garmin-Werte (vorher gab es nur Garmin, Apple Health füllte Lücken).
  /// Ohne diesen Schritt würde das erste Neuberechnen Werte ohne Herkunft verwerfen.
  Future<void> migrateIfNeeded() async {
    if (_settings.boolValue(migratedKey)) return;
    await _db.transaction(() async {
      final known = {for (final row in await _db.select(_db.sourceRecords).get()) row.key};
      for (final row in await _db.select(_db.dailyMetricsRecords).get()) {
        final metrics = decodeJson(row.payload, DailyMetrics.fromJson);
        if (metrics == null) continue;
        final entry = SourceEntry(
          provider: DataProvider.garmin,
          kind: null,
          externalID: metrics.day.iso,
          day: metrics.day,
          importedAt: row.updatedAt,
          contentHash: SyncLedger.hash(metrics),
        );
        if (known.contains(entry.id)) continue;
        await _db.into(_db.sourceRecords).insert(_companion(entry, payload: row.payload));
      }
    });
    await _settings.setBool(migratedKey, true);
  }

  // Tageswerte

  /// Tageswerte eines Anbieters übernehmen: mit dem bisher Gespeicherten dieses Anbieters zusammengeführt (vorhandene
  /// Felder bleiben, neue überschreiben), danach die betroffenen Tage neu berechnen. Gibt die Zahl der Tage zurück,
  /// deren Werte sich geändert haben.
  Future<int> ingestDays(Map<CalendarDay, DailyMetrics> map, {required DataProvider from, DateTime? now}) async {
    if (map.isEmpty) return 0;
    final at = now ?? DateTime.now();
    final touched = <String>{};
    await _db.transaction(() async {
      final byKey = await _sourcesByKey();
      for (final MapEntry(key: day, value: incoming) in map.entries) {
        final key = SourceEntry.key(from, null, day.iso);
        final row = byKey[key];
        if (row != null) {
          final stored = row.payload == null ? null : decodeJson(row.payload!, DailyMetrics.fromJson);
          final merged = stored?.merging(incoming) ?? incoming;
          final hash = SyncLedger.hash(merged);
          if (hash == row.contentHash && row.status == SourceEntryStatus.active.rawValue) continue;
          await (_db.update(_db.sourceRecords)..where((t) => t.key.equals(key))).write(
            SourceRecordsCompanion(
              payload: Value(encodeJson(merged.toJson())),
              contentHash: Value(hash),
              updatedAt: Value(at),
              status: Value(SourceEntryStatus.active.rawValue),
            ),
          );
        } else {
          final entry = SourceEntry(
            provider: from,
            kind: null,
            externalID: day.iso,
            day: day,
            importedAt: at,
            contentHash: SyncLedger.hash(incoming),
          );
          await _db.into(_db.sourceRecords).insert(_companion(entry, payload: encodeJson(incoming.toJson())));
        }
        touched.add(day.iso);
      }
    });
    return rebuild(days: touched, now: at);
  }

  /// Tageswerte der Tage aus den Werten aller Anbieter neu berechnen (`null` = alle Tage mit Herkunft, z. B. nach
  /// geänderten Einstellungen). Tage ohne Herkunft (Beispieldaten) bleiben unberührt.
  Future<int> rebuild({Set<String>? days, DateTime? now}) async {
    final at = now ?? DateTime.now();
    final query = _db.select(_db.sourceRecords)
      ..where((t) => t.kind.equals(dailyKind) & t.status.equals(SourceEntryStatus.active.rawValue));
    if (days != null) query.where((t) => t.dayKey.isIn(days.toList()));
    final grouped = <String, List<SourceRow>>{};
    for (final row in await query.get()) {
      (grouped[row.dayKey] ??= []).add(row);
    }
    final prefs = preferences();
    var changed = 0;
    await _db.transaction(() async {
      for (final MapEntry(key: dayKey, value: rows) in grouped.entries) {
        final day = CalendarDay.tryParse(dayKey);
        if (day == null) continue;
        final merged = MetricsMerge.merge(_perProvider(rows), day: day, preferences: prefs).metrics;
        if (await _metrics.day(day) == merged) continue;
        await _metrics.replace(merged, at: at);
        changed += 1;
      }
    });
    return changed;
  }

  /// Welche Quelle je Datenart an einem Tag gewonnen hat (für „Herkunft“ in den Einstellungen).
  Future<Map<DataKind, DataProvider>> sources(CalendarDay day) async {
    final rows =
        await (_db.select(_db.sourceRecords)..where(
              (t) =>
                  t.dayKey.equals(day.iso) &
                  t.kind.equals(dailyKind) &
                  t.status.equals(SourceEntryStatus.active.rawValue),
            ))
            .get();
    return MetricsMerge.merge(_perProvider(rows), day: day, preferences: preferences()).sources;
  }

  static Map<DataProvider, DailyMetrics> _perProvider(List<SourceRow> rows) => {
    for (final row in rows)
      if ((enumFromRaw(DataProvider.values, row.provider), row.payload) case (final provider?, final payload?))
        provider: ?decodeJson(payload, DailyMetrics.fromJson),
  };

  // Aktivitäten

  /// Herkunft der gelieferten Aktivitäten festhalten. [complete]: Der Abruf hat alle Aktivitäten im Zeitraum
  /// geliefert – dann gelten fehlende als beim Anbieter gelöscht und werden entfernt. Gibt zurück, welche IDs neu
  /// angelegt werden dürfen (nicht als ersetzt markiert).
  Future<Set<int>> recordActivities(
    List<GarminActivity> activities, {
    required DataProvider from,
    required DateRange? window,
    required bool complete,
    DateTime? now,
  }) async {
    final at = now ?? DateTime.now();
    late SyncChanges changes;
    await _db.transaction(() async {
      final mine = await (_db.select(
        _db.sourceRecords,
      )..where((t) => t.provider.equals(from.rawValue) & t.kind.equals(DataKind.activities.rawValue))).get();
      final incoming = [
        for (final activity in activities)
          if (activity.day case final day?)
            SyncIncoming(externalID: externalID(activity), day: day, contentHash: SyncLedger.hash(activity)),
      ];
      changes = SyncLedger.reconcile(
        known: [for (final row in mine) ?entry(row)],
        incoming: incoming,
        provider: from,
        kind: DataKind.activities,
        window: window,
        complete: complete,
        now: at,
      );
      for (final entry in changes.newEntries) {
        await _db.into(_db.sourceRecords).insertOnConflictUpdate(_companion(entry));
      }
      for (final entry in [...changes.changed, ...changes.deleted]) {
        await _apply(entry);
      }
      if (changes.deleted.isNotEmpty) {
        final gone = {for (final entry in changes.deleted) entry.externalID};
        final ids = <int>[];
        for (final row in await _db.select(_db.activityRecords).get()) {
          final activity = decodeJson(row.payload, GarminActivity.fromJson);
          if (activity != null && ActivityMerge.provider(activity) == from && gone.contains(externalID(activity))) {
            ids.add(row.garminID);
          }
        }
        await (_db.delete(_db.activityRecords)..where((t) => t.garminID.isIn(ids))).go();
      }
    });
    final skipped = changes.skipped.toSet();
    return {
      for (final activity in activities)
        if (!skipped.contains(externalID(activity))) activity.id,
    };
  }

  /// Doppelte Einheiten verschiedener Anbieter entfernen: Nur die bevorzugte Quelle bleibt als Aktivität, die anderen
  /// werden im Herkunftsverzeichnis als ersetzt markiert. Gibt die Zahl entfernter Doppelter zurück.
  Future<int> deduplicateActivities({required Set<DataProvider> connected, DateTime? now}) async {
    final at = now ?? DateTime.now();
    final rows = await _db.select(_db.activityRecords).get();
    final decoded = [
      for (final row in rows)
        if (decodeJson(row.payload, GarminActivity.fromJson) case final activity?) (row: row, activity: activity),
    ];
    final plan = ActivityMerge.plan(
      [for (final item in decoded) item.activity],
      preferences: preferences(),
      connected: connected,
    );
    if (plan.superseded.isEmpty) return 0;
    await _db.transaction(() async {
      final byKey = await _sourcesByKey();
      for (final (:row, :activity) in decoded) {
        if (!plan.superseded.containsKey(row.garminID)) continue;
        final day = activity.day;
        if (day == null) continue;
        final entry = SourceEntry(
          provider: ActivityMerge.provider(activity),
          kind: DataKind.activities,
          externalID: externalID(activity),
          day: day,
          importedAt:
              byKey[SourceEntry.key(ActivityMerge.provider(activity), DataKind.activities, externalID(activity))]
                  ?.importedAt ??
              at,
          updatedAt: at,
          contentHash: SyncLedger.hash(activity),
          status: SourceEntryStatus.superseded,
        );
        if (byKey.containsKey(entry.id)) {
          await _apply(entry);
        } else {
          await _db.into(_db.sourceRecords).insert(_companion(entry));
        }
        await (_db.delete(_db.activityRecords)..where((t) => t.garminID.equals(row.garminID))).go();
      }
    });
    return plan.superseded.length;
  }

  /// Externe ID: beim Anbieter vergebene, sonst die lokale Aktivitäts-ID.
  static String externalID(GarminActivity activity) => activity.externalID ?? '${activity.id}';

  // Herkunftsverzeichnis

  /// Alle Herkunftseinträge (Diagnose, Tests).
  Future<List<SourceEntry>> entries() async => [
    for (final row in await _db.select(_db.sourceRecords).get()) ?entry(row),
  ];

  static SourceEntry? entry(SourceRow row) {
    final provider = enumFromRaw(DataProvider.values, row.provider);
    final day = CalendarDay.tryParse(row.dayKey);
    if (provider == null || day == null) return null;
    return SourceEntry(
      provider: provider,
      kind: enumFromRaw(DataKind.values, row.kind),
      externalID: row.externalID,
      day: day,
      start: row.start,
      importedAt: row.importedAt,
      updatedAt: row.updatedAt,
      contentHash: row.contentHash,
      status: enumFromRaw(SourceEntryStatus.values, row.status) ?? SourceEntryStatus.active,
    );
  }

  Future<Map<String, SourceRow>> _sourcesByKey() async => {
    for (final row in await _db.select(_db.sourceRecords).get()) row.key: row,
  };

  static SourceRecordsCompanion _companion(SourceEntry entry, {Uint8List? payload}) => SourceRecordsCompanion.insert(
    key: entry.id,
    provider: entry.provider.rawValue,
    kind: entry.kind?.rawValue ?? dailyKind,
    externalID: entry.externalID,
    dayKey: entry.day.iso,
    start: Value(entry.start),
    importedAt: entry.importedAt,
    updatedAt: entry.updatedAt,
    contentHash: entry.contentHash,
    status: entry.status.rawValue,
    payload: Value(payload),
  );

  Future<void> _apply(SourceEntry entry) => (_db.update(_db.sourceRecords)..where((t) => t.key.equals(entry.id))).write(
    SourceRecordsCompanion(
      dayKey: Value(entry.day.iso),
      start: Value(entry.start),
      updatedAt: Value(entry.updatedAt),
      contentHash: Value(entry.contentHash),
      status: Value(entry.status.rawValue),
    ),
  );
}
