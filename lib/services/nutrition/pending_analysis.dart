import 'dart:io';
import 'dart:typed_data';

import 'package:coach_core/coach_core.dart';
import 'package:path/path.dart' as p;

import '../../data/settings/settings_store.dart';

/// Mahlzeit, die ohne Netz nicht ausgewertet werden konnte: Beschreibung in den Einstellungen, Foto als Datei im Ordner
/// „pending-meals“ (App-Support). Wird ausgewertet, sobald die App wieder online ist.
final class PendingAnalysis {
  PendingAnalysis({String? id, DateTime? created, required this.text, required this.hasPhoto})
    : id = id ?? newUuid(),
      created = created ?? DateTime.now();

  final String id;
  final DateTime created;
  final String text;
  final bool hasPhoto;

  Map<String, Object?> toJson() => {'id': id, 'created': swiftDateToJson(created), 'text': text, 'hasPhoto': hasPhoto};

  static PendingAnalysis? fromJson(Object? json) {
    if (json case {'id': final String id, 'text': final String text, 'hasPhoto': final bool hasPhoto}) {
      final created = swiftDateFromJson(json['created']);
      if (created == null) return null;
      return PendingAnalysis(id: id, created: created, text: text, hasPhoto: hasPhoto);
    }
    return null;
  }

  @override
  bool operator ==(Object other) =>
      other is PendingAnalysis && other.id == id && other.text == text && other.hasPhoto == hasPhoto;

  @override
  int get hashCode => Object.hash(id, text, hasPhoto);
}

/// Ablage der wartenden Auswertungen (Schlüssel `nutrition.pendingAnalyses`, Fotos als Dateien).
final class PendingAnalysisStore {
  PendingAnalysisStore(this._settings, {required String? folder})
    : _folder = folder == null ? null : p.join(folder, 'pending-meals');

  static const key = SettingsKeys.pendingAnalyses;

  final SettingsStore _settings;
  final String? _folder;

  /// Neue wartende Auswertung; das Foto wird als Datei abgelegt.
  PendingAnalysis create({required String text, Uint8List? photo}) {
    final item = PendingAnalysis(text: text, hasPhoto: photo != null);
    final file = _photoFile(item);
    if (photo != null && file != null) {
      try {
        file.parent.createSync(recursive: true);
        file.writeAsBytesSync(photo, flush: true);
      } on Object {
        // Wie `try? write`: ohne Foto weiter.
      }
    }
    return item;
  }

  File? _photoFile(PendingAnalysis item) =>
      _folder == null ? null : File(p.join(_folder, '${item.id.toUpperCase()}.jpg'));

  Uint8List? photo(PendingAnalysis item) {
    if (!item.hasPhoto) return null;
    try {
      return _photoFile(item)?.readAsBytesSync();
    } on Object {
      return null;
    }
  }

  void deletePhoto(PendingAnalysis item) {
    try {
      _photoFile(item)?.deleteSync();
    } on Object {
      // Schon weg.
    }
  }

  List<PendingAnalysis> load() =>
      _settings.read(key, (json) => listStrict(json, PendingAnalysis.fromJson), const <PendingAnalysis>[]);

  Future<void> save(List<PendingAnalysis> items) => _settings.setJson(key, [for (final item in items) item.toJson()]);
}
