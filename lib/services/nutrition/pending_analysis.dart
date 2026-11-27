import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:coach_core/coach_core.dart';
import 'package:path/path.dart' as p;

import '../../data/settings/settings_store.dart';

/// Mahlzeit, deren Auswertung noch aussteht: Foto und Beschreibung bleiben gespeichert, bis die KI sie ausgewertet hat
/// (ohne Netz, KI überlastet, Zeitüberschreitung). Mit [autoLog] trägt die App das Ergebnis selbst ein – auch im
/// Hintergrund, wenn die App geschlossen ist.
final class PendingAnalysis {
  PendingAnalysis({
    String? id,
    DateTime? created,
    required this.text,
    required this.hasPhoto,
    this.mealTime,
    this.category,
    this.autoLog = false,
    this.attempts = 0,
    this.nextAttempt,
    this.lastError,
  }) : id = id ?? newUuid(),
       created = created ?? DateTime.now();

  final String id;

  /// Zeitpunkt der Aufnahme.
  final DateTime created;
  final String text;
  final bool hasPhoto;

  /// Zeitpunkt der Mahlzeit (gewählter Tag zur Uhrzeit der Aufnahme); fehlt bei älteren Einträgen.
  final DateTime? mealTime;

  /// Vorgewählte Mahlzeit (z. B. „+“ bei „Mittagessen“); sonst Vorschlag der KI bzw. Uhrzeit.
  final MealCategory? category;

  /// Ergebnis ohne Rückfrage eintragen (Wahl „Später automatisch eintragen“); sonst öffnet die App den Editor.
  final bool autoLog;

  /// Fehlgeschlagene Versuche bisher.
  final int attempts;

  /// Frühester nächster automatischer Versuch; `null` = sofort.
  final DateTime? nextAttempt;

  /// Meldung des letzten Fehlschlags.
  final String? lastError;

  /// Zeitpunkt, zu dem die Mahlzeit eingetragen wird.
  DateTime get eatenAt => mealTime ?? created;

  /// Darf ein automatischer Versuch jetzt laufen? Antippen von „Jetzt auswerten“ wartet nie.
  bool isDue(DateTime now) => nextAttempt == null || !now.isBefore(nextAttempt!);

  PendingAnalysis copyWith({
    bool? autoLog,
    int? attempts,
    DateTime? Function()? nextAttempt,
    String? Function()? lastError,
  }) => PendingAnalysis(
    id: id,
    created: created,
    text: text,
    hasPhoto: hasPhoto,
    mealTime: mealTime,
    category: category,
    autoLog: autoLog ?? this.autoLog,
    attempts: attempts ?? this.attempts,
    nextAttempt: nextAttempt == null ? this.nextAttempt : nextAttempt(),
    lastError: lastError == null ? this.lastError : lastError(),
  );

  /// Nach einem Fehlschlag: Versuch zählen und den nächsten nach [PendingMealRetry.delay] einplanen.
  PendingAnalysis failed(String message, {required DateTime now, bool keepAuto = true}) => copyWith(
    autoLog: autoLog && keepAuto,
    attempts: attempts + 1,
    nextAttempt: () => now.add(PendingMealRetry.delay(attempts + 1)),
    lastError: () => message,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'created': swiftDateToJson(created),
    'text': text,
    'hasPhoto': hasPhoto,
    if (mealTime case final time?) 'mealTime': swiftDateToJson(time),
    if (category case final category?) 'category': category.rawValue,
    if (autoLog) 'autoLog': true,
    if (attempts > 0) 'attempts': attempts,
    if (nextAttempt case final next?) 'nextAttempt': swiftDateToJson(next),
    'lastError': ?lastError,
  };

  /// Liest auch das ältere Format (nur Kennung, Zeitpunkt, Text, Foto).
  static PendingAnalysis? fromJson(Object? json) {
    if (json case {'id': final String id, 'text': final String text, 'hasPhoto': final bool hasPhoto}) {
      // JSON liefert UTC; Tag und Mahlzeit gelten in Ortszeit (sonst rutscht 0:30 Uhr auf den Vortag).
      final created = swiftDateFromJson(json['created'])?.toLocal();
      if (created == null) return null;
      return PendingAnalysis(
        id: id,
        created: created,
        text: text,
        hasPhoto: hasPhoto,
        mealTime: swiftDateFromJson(json['mealTime'])?.toLocal(),
        category: MealCategory.fromRaw(json['category'] as String?),
        autoLog: json['autoLog'] == true,
        attempts: (json['attempts'] as num?)?.toInt() ?? 0,
        nextAttempt: swiftDateFromJson(json['nextAttempt'])?.toLocal(),
        lastError: json['lastError'] as String?,
      );
    }
    return null;
  }

  @override
  bool operator ==(Object other) =>
      other is PendingAnalysis &&
      other.id == id &&
      other.text == text &&
      other.hasPhoto == hasPhoto &&
      _same(other.mealTime, mealTime) &&
      other.category == category &&
      other.autoLog == autoLog &&
      other.attempts == attempts &&
      _same(other.nextAttempt, nextAttempt) &&
      other.lastError == lastError;

  /// Gleicher Zeitpunkt, egal ob UTC oder Ortszeit (JSON liefert UTC).
  static bool _same(DateTime? a, DateTime? b) => a == null || b == null ? a == b : a.isAtSameMomentAs(b);

  @override
  int get hashCode => Object.hash(id, text, hasPhoto, category, autoLog, attempts, lastError);
}

/// Abstände zwischen automatischen Versuchen: erst kurz (KI kurz überlastet), dann höchstens stündlich.
abstract final class PendingMealRetry {
  static const _minutes = [2, 5, 15, 30, 60];

  static Duration delay(int attempts) =>
      Duration(minutes: _minutes[(attempts - 1).clamp(0, _minutes.length - 1).toInt()]);

  /// So lange gilt eine laufende Auswertung als belegt; danach (App beendet, Hintergrundzeit abgelaufen) darf ein
  /// anderer Ablauf sie übernehmen. Länger als eine Anfrage an den Worker (120 s).
  static const claimTimeout = Duration(minutes: 4);
}

/// Ablage der wartenden Auswertungen im Ordner „pending-meals“ (App-Support des Benutzers): je Mahlzeit eine JSON-Datei
/// und das Foto daneben. Dateien statt Einstellungen, weil App und Hintergrundabruf (eigenes Isolate, eigener
/// Zwischenspeicher der Einstellungen) dieselbe Warteschlange sehen müssen. Eine Sperrdatei verhindert, dass beide
/// dieselbe Mahlzeit gleichzeitig auswerten und sie doppelt eingetragen wird. Ohne Ordner (Tests) im Arbeitsspeicher.
final class PendingAnalysisStore {
  PendingAnalysisStore(this._settings, {required String? folder})
    : _folder = folder == null ? null : p.join(folder, 'pending-meals');

  /// Früherer Ort der Liste (bis 26.11.2026); wird beim ersten Laden in Dateien übernommen.
  static const legacyKey = SettingsKeys.pendingAnalyses;

  final SettingsStore _settings;
  final String? _folder;
  final _memory = <String, (PendingAnalysis, Uint8List?)>{};
  final _memoryClaims = <String>{};

  /// Neue wartende Auswertung; Foto und Beschreibung werden sofort gesichert.
  PendingAnalysis create({
    required String text,
    Uint8List? photo,
    DateTime? created,
    DateTime? mealTime,
    MealCategory? category,
    bool autoLog = false,
  }) {
    final item = PendingAnalysis(
      text: text,
      hasPhoto: photo != null,
      created: created,
      mealTime: mealTime,
      category: category,
      autoLog: autoLog,
    );
    if (_folder == null) {
      _memory[item.id] = (item, photo);
      return item;
    }
    try {
      Directory(_folder).createSync(recursive: true);
      if (photo != null) _photoFile(item.id)!.writeAsBytesSync(photo, flush: true);
    } on Object {
      // Wie `try? write`: ohne Foto weiter.
    }
    put(item);
    return item;
  }

  /// Speichert den Stand einer Auswertung (Versuche, automatisch eintragen).
  void put(PendingAnalysis item) {
    if (_folder == null) {
      final photo = _memory[item.id]?.$2;
      _memory[item.id] = (item, photo);
      return;
    }
    try {
      Directory(_folder).createSync(recursive: true);
      // Erst vollständig schreiben, dann umbenennen: ein abgebrochener Schreibvorgang hinterlässt keine halbe Datei.
      final temp = File(p.join(_folder, '${_name(item.id)}.json.tmp'))
        ..writeAsStringSync(jsonEncode(item.toJson()), flush: true);
      temp.renameSync(_jsonFile(item.id)!.path);
    } on Object {
      // Ablage nicht beschreibbar: bleibt beim nächsten Versuch beim alten Stand.
    }
  }

  String _name(String id) => id.toUpperCase();

  File? _photoFile(String id) => _folder == null ? null : File(p.join(_folder, '${_name(id)}.jpg'));

  File? _jsonFile(String id) => _folder == null ? null : File(p.join(_folder, '${_name(id)}.json'));

  File? _lockFile(String id) => _folder == null ? null : File(p.join(_folder, '${_name(id)}.lock'));

  Uint8List? photo(PendingAnalysis item) {
    if (!item.hasPhoto) return null;
    if (_folder == null) return _memory[item.id]?.$2;
    try {
      return _photoFile(item.id)!.readAsBytesSync();
    } on Object {
      return null;
    }
  }

  /// Ausgewertet oder verworfen: Beschreibung, Foto und Sperre löschen.
  void remove(PendingAnalysis item) {
    _memory.remove(item.id);
    _memoryClaims.remove(item.id);
    for (final file in [_jsonFile(item.id), _photoFile(item.id), _lockFile(item.id)]) {
      try {
        file?.deleteSync();
      } on Object {
        // Schon weg.
      }
    }
  }

  /// Aktueller Stand einer Auswertung; `null`, wenn sie inzwischen eingetragen oder verworfen wurde.
  PendingAnalysis? reload(PendingAnalysis item) {
    if (_folder == null) return _memory[item.id]?.$1;
    return _read(_jsonFile(item.id)!);
  }

  static PendingAnalysis? _read(File file) {
    try {
      return PendingAnalysis.fromJson(jsonDecode(file.readAsStringSync()));
    } on Object {
      return null;
    }
  }

  /// Alle wartenden Auswertungen, älteste zuerst.
  List<PendingAnalysis> load() {
    _migrateLegacy();
    final List<PendingAnalysis> items;
    if (_folder == null) {
      items = [for (final (item, _) in _memory.values) item];
    } else {
      final folder = Directory(_folder);
      if (!folder.existsSync()) return [];
      items = [
        for (final file in folder.listSync().whereType<File>())
          if (file.path.endsWith('.json')) ?_read(file),
      ];
    }
    return items..sort((a, b) => a.created.compareTo(b.created));
  }

  /// Liste aus den Einstellungen (älteres Format) in Dateien übernehmen; die Fotos lagen schon im Ordner.
  void _migrateLegacy() {
    final legacy = _settings.read(legacyKey, (json) => listStrict(json, PendingAnalysis.fromJson), null);
    if (legacy == null) return;
    for (final item in legacy) {
      if (_folder == null) {
        _memory[item.id] = (item, null);
      } else {
        put(item);
      }
    }
    _settings.remove(legacyKey);
  }

  /// Auswertung für diesen Ablauf belegen; `false`, wenn gerade ein anderer (App oder Hintergrund) daran arbeitet.
  bool claim(PendingAnalysis item, {DateTime? now}) {
    if (_folder == null) return _memoryClaims.add(item.id);
    final lock = _lockFile(item.id)!;
    try {
      Directory(_folder).createSync(recursive: true);
      if (lock.existsSync()) {
        final age = (now ?? DateTime.now()).difference(lock.lastModifiedSync());
        if (age < PendingMealRetry.claimTimeout) return false;
        // Liegengeblieben (App beendet, Hintergrundzeit abgelaufen): übernehmen.
        lock.deleteSync();
      }
      lock.createSync(exclusive: true);
      return true;
    } on Object {
      return false;
    }
  }

  void release(PendingAnalysis item) {
    _memoryClaims.remove(item.id);
    try {
      _lockFile(item.id)?.deleteSync();
    } on Object {
      // Schon frei.
    }
  }
}
