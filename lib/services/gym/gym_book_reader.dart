import 'dart:io';

import 'package:coach_core/coach_core.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

import '../../data/repositories/gym_repository.dart';
import '../../data/settings/coach_settings.dart';

/// Fehler beim Lesen eines GymBook-Backups.
sealed class GymBookReadError implements Exception {
  const GymBookReadError(this.detail);

  final String detail;

  String get message;

  @override
  String toString() => message;
}

final class GymBookOpenError extends GymBookReadError {
  const GymBookOpenError(super.detail);

  @override
  String get message => 'Die Datei ließ sich nicht öffnen ($detail). Ist es ein GymBook-Backup?';
}

final class GymBookQueryError extends GymBookReadError {
  const GymBookQueryError(super.detail);

  @override
  String get message => 'Die Datei enthält kein GymBook-Protokoll ($detail).';
}

/// Liest ein GymBook-Backup (SQLite) nur lesend und übernimmt den Verlauf als Krafteinheiten.
abstract final class GymBookReader {
  static const query = '''
SELECT l.ZDAY, l.ZTIME, e.ZNAME, e.ZTARGETREGION, e.ZTARGETMUSCLESPRIMARY, e.ZEQUIPMENT,
       l.ZFREQUENCYVALUE, l.ZFREQUENCYUNIT, l.ZQUANTITYVALUE, l.ZQUANTITYUNIT, l.ZSKIPPED, w.ZNAME
FROM ZEXERCISELOG l
JOIN ZEXERCISE e ON e.Z_PK = l.ZEXERCISE
LEFT JOIN ZWORKOUT w ON w.Z_PK = l.ZWORKOUT
''';

  static String? _text(Object? value) => value?.toString();

  static double? _number(Object? value) => switch (value) {
    final num number => number.toDouble(),
    final String text => double.tryParse(text),
    _ => null,
  };

  static List<GymBookLogRow> rows(String path) {
    final Database database;
    try {
      database = sqlite3.open(path, mode: OpenMode.readOnly);
    } on Object catch (error) {
      throw GymBookOpenError('$error');
    }
    try {
      final ResultSet result;
      try {
        result = database.select(query);
      } on Object catch (error) {
        throw GymBookQueryError(error is SqliteException ? error.message : '$error');
      }
      return [
        for (final row in result.rows)
          if ((_text(row[0]), _text(row[2])) case (final day?, final name?))
            GymBookLogRow(
              day: day,
              secondsOfDay: _number(row[1]) ?? 0,
              exercise: name,
              region: _text(row[3]),
              muscles: _text(row[4]),
              equipment: _text(row[5]),
              frequency: _number(row[6]),
              frequencyUnit: _text(row[7]),
              quantity: _number(row[8]),
              quantityUnit: _text(row[9]),
              skipped: (_number(row[10]) ?? 0) != 0,
              workout: _text(row[11]),
            ),
      ];
    } finally {
      database.close();
    }
  }

  /// Übernimmt die Einheiten, die noch nicht da sind (gleiche GymBook-Einheit oder schon in der App erfasster Tag), und
  /// legt fehlende Übungen als eigene Übungen an. Gibt eine kurze Zusammenfassung zurück.
  static Future<String> importBackup(String path, {required GymRepository gym, required CoachSettings settings}) async {
    // Kopie im Temp-Ordner: SQLite braucht eine echte Datei, und das Original bleibt unberührt.
    final copy = p.join(Directory.systemTemp.path, 'gymbook-import.sqlite');
    try {
      File(copy).deleteSync();
    } on Object {
      // Nicht vorhanden.
    }
    File(path).copySync(copy);
    try {
      final result = GymBookImport.sessions(rows(copy), custom: settings.gym.customExercises);
      final existing = await gym.sessions();
      final knownKeys = {for (final session in existing) ?session.workoutKey};
      final appDays = {
        for (final session in existing)
          if (!(session.workoutKey ?? '').startsWith('gymbook:')) session.day,
      };
      final fresh = [
        for (final session in result.sessions)
          if (!knownKeys.contains(session.workoutKey ?? '') && !appDays.contains(session.day)) session,
      ];
      for (final session in fresh) {
        await gym.save(session);
      }
      final added = fresh.length;
      if (result.newCustom.isNotEmpty) {
        settings.gym = settings.gym..customExercises = [...settings.gym.customExercises, ...result.newCustom];
      }
      final sets = result.sessions.fold(0, (sum, session) => sum + session.doneSetCount);
      final buffer = StringBuffer('$added Einheiten übernommen (${result.sessions.length} im Backup, $sets Sätze)');
      if (result.newCustom.isNotEmpty) buffer.write(', ${result.newCustom.length} Übungen neu angelegt');
      if (added < result.sessions.length) buffer.write(', ${result.sessions.length - added} schon vorhanden');
      return '$buffer.';
    } finally {
      try {
        File(copy).deleteSync();
      } on Object {
        // Bleibt im Temp-Ordner.
      }
    }
  }
}
