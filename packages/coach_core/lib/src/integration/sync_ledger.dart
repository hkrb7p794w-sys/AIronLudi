import '../calendar/calendar_day.dart';
import '../util/enum_codec.dart';
import '../util/fnv.dart';
import '../util/swift_date.dart';
import '../util/swift_json.dart';
import 'data_provider.dart';

enum SourceEntryStatus implements RawEnum {
  /// Aktuell und genutzt.
  active,

  /// Gleiche Einheit von einer bevorzugten Quelle vorhanden – nicht doppelt zählen, nicht neu anlegen.
  superseded,

  /// Beim Anbieter gelöscht.
  deleted;

  @override
  String get rawValue => name;
}

/// Herkunft eines importierten Datensatzes. Für die Nutzeroberfläche nicht nötig, aber jeder Wert bleibt
/// nachvollziehbar: wer ihn geliefert hat, unter welcher ID, für welche Zeit, wann er kam und ob er noch gilt.
final class SourceEntry {
  SourceEntry({
    required this.provider,
    required this.kind,
    required this.externalID,
    required this.day,
    this.start,
    required this.importedAt,
    DateTime? updatedAt,
    required this.contentHash,
    this.status = SourceEntryStatus.active,
  }) : updatedAt = updatedAt ?? importedAt;

  final DataProvider provider;

  /// `null` = Tageswerte des Anbieters (alle Arten eines Tages in einem Datensatz).
  final DataKind? kind;

  /// Eindeutige ID beim Anbieter; bei Tageswerten der Tag (`2026-11-02`).
  final String externalID;
  CalendarDay day;

  /// Beginn des Datensatzes (Aktivität, Schlaf), falls bekannt.
  DateTime? start;
  final DateTime importedAt;
  DateTime updatedAt;

  /// Prüfsumme des Inhalts, um Änderungen zu erkennen.
  String contentHash;
  SourceEntryStatus status;

  String get id => key(provider, kind, externalID);

  static String key(DataProvider provider, DataKind? kind, String externalID) =>
      '${provider.rawValue}|${kind?.rawValue ?? 'daily'}|$externalID';

  SourceEntry copy() => SourceEntry(
    provider: provider,
    kind: kind,
    externalID: externalID,
    day: day,
    start: start,
    importedAt: importedAt,
    updatedAt: updatedAt,
    contentHash: contentHash,
    status: status,
  );

  Map<String, Object?> toJson() => {
    'provider': provider.rawValue,
    'kind': ?kind?.rawValue,
    'externalID': externalID,
    'day': day.toJson(),
    'start': ?switch (start) {
      final date? => swiftDateToJson(date),
      null => null,
    },
    'importedAt': swiftDateToJson(importedAt),
    'updatedAt': swiftDateToJson(updatedAt),
    'contentHash': contentHash,
    'status': status.rawValue,
  };

  static SourceEntry? fromJson(Object? json) {
    if (json is! Map) return null;
    final provider = enumFromRaw(DataProvider.values, json['provider']);
    final rawKind = json['kind'];
    final kind = rawKind == null ? null : enumFromRaw(DataKind.values, rawKind);
    final externalID = json['externalID'];
    final rawDay = json['day'];
    final rawStart = json['start'];
    final start = rawStart == null ? null : swiftDateFromJson(rawStart);
    final importedAt = swiftDateFromJson(json['importedAt']);
    final updatedAt = swiftDateFromJson(json['updatedAt']);
    final contentHash = json['contentHash'];
    final status = enumFromRaw(SourceEntryStatus.values, json['status']);
    if (provider == null ||
        (rawKind != null && kind == null) ||
        externalID is! String ||
        rawDay is! Map ||
        (rawStart != null && start == null) ||
        importedAt == null ||
        updatedAt == null ||
        contentHash is! String ||
        status == null) {
      return null;
    }
    final CalendarDay day;
    try {
      day = CalendarDay.fromJson(rawDay.cast<String, Object?>());
    } on Object {
      return null;
    }
    return SourceEntry(
      provider: provider,
      kind: kind,
      externalID: externalID,
      day: day,
      start: start,
      importedAt: importedAt,
      updatedAt: updatedAt,
      contentHash: contentHash,
      status: status,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is SourceEntry &&
      other.provider == provider &&
      other.kind == kind &&
      other.externalID == externalID &&
      other.day == day &&
      other.start?.microsecondsSinceEpoch == start?.microsecondsSinceEpoch &&
      other.importedAt.isAtSameMomentAs(importedAt) &&
      other.updatedAt.isAtSameMomentAs(updatedAt) &&
      other.contentHash == contentHash &&
      other.status == status;

  @override
  int get hashCode => Object.hash(provider, kind, externalID, day, contentHash, status);

  @override
  String toString() => 'SourceEntry($id, ${status.rawValue})';
}

/// Ein geliefertes Element eines Abrufs.
final class SyncIncoming {
  const SyncIncoming({required this.externalID, required this.day, this.start, required this.contentHash});

  final String externalID;
  final CalendarDay day;
  final DateTime? start;
  final String contentHash;
}

/// Ergebnis des Abgleichs.
final class SyncChanges {
  final List<SourceEntry> newEntries = [];
  final List<SourceEntry> changed = [];
  final List<String> unchanged = [];

  /// Im vollständig abgerufenen Zeitraum nicht mehr geliefert.
  final List<SourceEntry> deleted = [];

  /// Wieder geliefert, war aber als ersetzt markiert – bleibt ersetzt.
  final List<String> skipped = [];

  bool get isEmpty => newEntries.isEmpty && changed.isEmpty && deleted.isEmpty;
}

/// Abgleich eines Abrufs mit dem schon Importierten: neu, geändert, unverändert, beim Anbieter gelöscht.
abstract final class SyncLedger {
  /// [complete]: Der Abruf hat den ganzen Zeitraum [window] geliefert (sonst keine Löschungen ableiten, z. B. wenn
  /// nur eine Seite der Aktivitätsliste kam oder ein Endpunkt ausfiel).
  static SyncChanges reconcile({
    required List<SourceEntry> known,
    required List<SyncIncoming> incoming,
    required DataProvider provider,
    required DataKind? kind,
    required DateRange? window,
    required bool complete,
    required DateTime now,
  }) {
    final mine = known.where((entry) => entry.provider == provider && entry.kind == kind).toList();
    final byID = <String, SourceEntry>{};
    for (final entry in mine) {
      byID.putIfAbsent(entry.externalID, () => entry);
    }
    final changes = SyncChanges();
    final seen = <String>{};
    for (final item in incoming) {
      if (!seen.add(item.externalID)) continue;
      final existing = byID[item.externalID];
      if (existing == null) {
        changes.newEntries.add(
          SourceEntry(
            provider: provider,
            kind: kind,
            externalID: item.externalID,
            day: item.day,
            start: item.start,
            importedAt: now,
            contentHash: item.contentHash,
          ),
        );
      } else if (existing.status == SourceEntryStatus.superseded) {
        changes.skipped.add(item.externalID);
      } else if (existing.contentHash != item.contentHash || existing.status == SourceEntryStatus.deleted) {
        changes.changed.add(
          existing.copy()
            ..contentHash = item.contentHash
            ..updatedAt = now
            ..day = item.day
            ..start = item.start ?? existing.start
            ..status = SourceEntryStatus.active,
        );
      } else {
        changes.unchanged.add(item.externalID);
      }
    }
    if (complete && window != null) {
      for (final entry in mine) {
        if (entry.status == SourceEntryStatus.active &&
            !seen.contains(entry.externalID) &&
            window.start <= entry.day &&
            entry.day <= window.end) {
          changes.deleted.add(
            entry.copy()
              ..status = SourceEntryStatus.deleted
              ..updatedAt = now,
          );
        }
      }
    }
    return changes;
  }

  /// Prüfsumme über die JSON-Darstellung (FNV-1a, 64 Bit; reicht zum Erkennen von Änderungen). [value] ist ein
  /// JSON-Wert oder ein Objekt mit `toJson()`; kodiert wie Swift mit sortierten Schlüsseln.
  static String hash(Object? value) => fnv1a64Text(swiftSortedJson(value)).toRadixString(16);
}

/// Zustand der Synchronisierung je Anbieter: letzter Erfolg, Fehler und wann der nächste Versuch sinnvoll ist.
/// Nach einem Fehlschlag bleibt `lastSuccessDay` stehen, der nächste Abruf holt die Lücke also nach.
final class ProviderSyncState {
  ProviderSyncState();

  DateTime? lastAttempt;
  DateTime? lastSuccess;
  CalendarDay? lastSuccessDay;
  String? lastError;
  int failures = 0;

  /// Wartezeit nach [failures] Fehlschlägen: 1, 5, 15, 60 Minuten, danach 6 Stunden.
  static Duration backoff(int failures) => switch (failures) {
    <= 0 => Duration.zero,
    1 => const Duration(minutes: 1),
    2 => const Duration(minutes: 5),
    3 => const Duration(minutes: 15),
    4 => const Duration(hours: 1),
    _ => const Duration(hours: 6),
  };

  /// Automatischer Abruf fällig? Manuell („Jetzt abrufen“) geht immer.
  bool isDue({required DateTime now, required Duration minimumInterval}) {
    final last = lastAttempt;
    if (last == null || now.isBefore(last)) return true;
    final wait = failures > 0 ? backoff(failures) : minimumInterval;
    return now.difference(last) >= wait;
  }

  void recordSuccess({required DateTime now, required CalendarDay day}) {
    lastAttempt = now;
    lastSuccess = now;
    lastSuccessDay = day;
    lastError = null;
    failures = 0;
  }

  void recordFailure({required DateTime now, required String error}) {
    lastAttempt = now;
    lastError = error;
    failures += 1;
  }

  /// Zeitraum des nächsten Abrufs: ab dem letzten erfolgreichen Tag mit Überlappung (Werte kommen nachträglich),
  /// beim ersten Mal [initialDays], höchstens [maxDays].
  DateRange window({required CalendarDay today, required int initialDays, int overlapDays = 3, int maxDays = 180}) {
    final last = lastSuccessDay;
    if (last == null || last > today) return DateRange.last(initialDays, endingOn: today);
    final a = last.adding(-overlapDays);
    final b = today.adding(-(maxDays - 1));
    return DateRange(a > b ? a : b, today);
  }

  Map<String, Object?> toJson() => {
    'lastAttempt': ?_date(lastAttempt),
    'lastSuccess': ?_date(lastSuccess),
    'lastSuccessDay': ?lastSuccessDay?.toJson(),
    'lastError': ?lastError,
    'failures': failures,
  };

  static Object? _date(DateTime? date) => date == null ? null : swiftDateToJson(date);

  static ProviderSyncState? fromJson(Object? json) {
    if (json is! Map) return null;
    final failures = json['failures'];
    if (failures is! int) return null;
    final rawDay = json['lastSuccessDay'];
    final lastError = json['lastError'];
    CalendarDay? day;
    if (rawDay is Map) {
      try {
        day = CalendarDay.fromJson(rawDay.cast<String, Object?>());
      } on Object {
        return null;
      }
    }
    return ProviderSyncState()
      ..lastAttempt = swiftDateFromJson(json['lastAttempt'])
      ..lastSuccess = swiftDateFromJson(json['lastSuccess'])
      ..lastSuccessDay = day
      ..lastError = lastError is String ? lastError : null
      ..failures = failures;
  }
}
