import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:coach_core/coach_core.dart';
import 'package:path/path.dart' as p;

/// Liest eine JSON-Liste aus einer Datei; fehlt sie oder ist sie kaputt: `null`.
List<T>? _readList<T extends Object>(File file, T? Function(Object? json) read) {
  try {
    final json = jsonDecode(file.readAsStringSync());
    if (json is! List) return null;
    final items = <T?>[for (final item in json) read(item)];
    // Wie `JSONDecoder`: ein kaputter Eintrag macht die ganze Datei ungültig.
    return items.contains(null) ? null : items.nonNulls.toList();
  } on Object {
    return null;
  }
}

void _writeAtomic(File file, String text) {
  try {
    file.parent.createSync(recursive: true);
    final temp = File('${file.path}.tmp')..writeAsStringSync(text, flush: true);
    temp.renameSync(file.path);
  } on Object {
    // Wie `try? data.write`: Fehler beim Speichern bleiben still, beim nächsten Abruf erneut.
  }
}

/// Ergebnisse der FIT-Auswertung als JSON-Datei im App-Support-Ordner (wenige KB, keine Tabelle nötig).
final class ActivityAnalysisStore {
  /// [folder] `null` = nur im Arbeitsspeicher (Vorschauen und Tests).
  ActivityAnalysisStore({String? folder})
    : _file = folder == null ? null : File(p.join(folder, 'activity-analysis.json'));

  /// Einträge älter als das bleiben nicht liegen (Kopplung zeigt 60 Tage, Pace-Check 6 Wochen).
  static const keepDays = 90;

  final File? _file;
  Map<int, ActivityAnalysis> _memory = {};

  Map<int, ActivityAnalysis> load() {
    final file = _file;
    if (file == null) return {..._memory};
    final list = _readList(file, ActivityAnalysis.fromJson);
    if (list == null) return {};
    return {for (final item in list) item.id: item};
  }

  void save(Map<int, ActivityAnalysis> analyses, {required CalendarDay today}) {
    final cutoff = today.adding(-keepDays);
    final kept = {
      for (final MapEntry(:key, :value) in analyses.entries)
        if (value.day >= cutoff) key: value,
    };
    final file = _file;
    if (file == null) {
      _memory = kept;
      return;
    }
    final list = kept.values.toList()..sort((a, b) => a.id.compareTo(b.id));
    _writeAtomic(file, jsonEncode([for (final item in list) item.toJson()]));
  }
}

/// Vollständige Aktivitätsberichte (Runden, Splits, Verlauf) als JSON-Datei im App-Support-Ordner sowie die Dateien der
/// Uhr (FIT) im Cache-Ordner. Die Berichte bleiben erhalten, auch wenn das System den Cache leert.
final class ActivityReportStore {
  /// [folder] `null` = Berichte nur im Arbeitsspeicher; [cacheFolder] `null` = keine FIT-Dateien zwischenspeichern.
  ActivityReportStore({String? folder, String? cacheFolder})
    : _file = folder == null ? null : File(p.join(folder, 'activity-reports.json')),
      _fitFolder = cacheFolder == null ? null : p.join(cacheFolder, 'fit');

  /// Ältere Berichte bleiben nicht liegen (rund 15 KB je Aktivität).
  static const keepDays = 180;

  final File? _file;
  final String? _fitFolder;
  Map<int, ActivityReport> _memory = {};
  Map<int, ActivityReport>? _cache;

  Map<int, ActivityReport> load() {
    if (_cache case final cache?) return {...cache};
    final file = _file;
    if (file == null) return {..._memory};
    final list = _readList(file, ActivityReport.fromJson);
    if (list == null) return {};
    final loaded = {for (final item in list) item.id: item};
    _cache = loaded;
    return {...loaded};
  }

  ActivityReport? report(int id) => load()[id];

  void save(Map<int, ActivityReport> reports, {required CalendarDay today}) {
    final cutoff = today.adding(-keepDays);
    final kept = {
      for (final MapEntry(:key, :value) in reports.entries)
        if (value.day >= cutoff) key: value,
    };
    _cache = kept;
    final file = _file;
    if (file == null) {
      _memory = kept;
      return;
    }
    final list = kept.values.toList()..sort((a, b) => a.id.compareTo(b.id));
    _writeAtomic(file, jsonEncode([for (final item in list) item.toJson()]));
  }

  /// Einen Bericht ergänzen (z. B. nach dem Öffnen einer älteren Aktivität).
  void store(ActivityReport report, {required CalendarDay today}) => save({...load(), report.id: report}, today: today);

  // Dateien der Uhr

  File? fitFile(int id) => _fitFolder == null ? null : File(p.join(_fitFolder, '$id.fit'));

  Uint8List? cachedFile(int id) {
    try {
      return fitFile(id)?.readAsBytesSync();
    } on Object {
      return null;
    }
  }

  void cacheFile(List<int> data, {required int id}) {
    final file = fitFile(id);
    if (file == null) return;
    try {
      file.parent.createSync(recursive: true);
      file.writeAsBytesSync(data);
    } on Object {
      // Nur ein Zwischenspeicher.
    }
  }
}
